<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik

SPDX-License-Identifier: MIT
-->

# Typed Channel

## Overview

The `AshTypescript.TypedChannel` DSL generates typed TypeScript event subscriptions from Ash PubSub publications. It reads the `returns` type from each declared publication and generates branded channel types, typed payload aliases, event maps, and subscription helper functions.

**Recommended approach**: Use `transform :some_calc` on publications to reference a resource calculation. When the calculation uses `:auto` typing, Ash automatically derives the `returns` type from the expression, so AshTypescript gets full type information without any manual `returns` declarations. This keeps the type and the transform logic in sync via a single source of truth (the calculation). You can also use explicit `returns: :type` with an anonymous function transform, but this requires manually keeping the type and transform in sync.

**Key distinction**: `AshTypescript.Rpc` with `generate_phx_channel_rpc_actions` is for request/response RPC over channels. `AshTypescript.TypedChannel` is for one-way push events (PubSub broadcasts) where the server pushes typed payloads to the client.

**Important**: `AshTypescript.TypedChannel` is a standalone Spark DSL — completely independent from `Ash.Resource` and `AshTypescript.Rpc`. The developer owns channel authorization via Phoenix's `join/3`.

## Requirements

Typed channels require **Ash >= 3.17.1**, which introduced `returns`, `public?`, and calculation `transform` support on PubSub publications. **Ash >= 3.21.1 is recommended**, as it added support for `:auto`-typed calculations as transforms, allowing Ash to automatically derive the `returns` type from the calculation expression.

## Architecture

### Three-Layer Design

```
┌─────────────────────────────────────────────────────────┐
│  DSL Layer: AshTypescript.TypedChannel.Dsl               │
│  - Topic pattern configuration                          │
│  - Resource + publish declarations                      │
│  - Compile-time verification (event existence, uniq)    │
├─────────────────────────────────────────────────────────┤
│  Type Resolution Layer: Codegen                          │
│  - Reads `returns` type from publication (auto-derived  │
│    via `transform :calc` or explicit `returns:`)        │
│  - Maps types via TypeMapper.map_channel_payload_type   │
│  - Plain object types (no __type/__primitiveFields)     │
├─────────────────────────────────────────────────────────┤
│  Output Layer: Codegen (types + functions)                │
│  - Branded channel types (prevent mixing instances)     │
│  - Payload type aliases per event                       │
│  - Events map, Handlers type, Refs type per channel     │
│  - Factory, subscription, and cleanup functions         │
└─────────────────────────────────────────────────────────┘
```

### File Output Split

Types and functions are split across two files:

| Content | Output File | Reason |
|---------|------------|--------|
| Branded types, payload aliases, events maps, handlers/refs types | `ash_types.ts` | Shared types importable by other generated files |
| Factory functions, subscription helpers, cleanup functions | `typed_channels_output_file` | Runtime code, imports types from `ash_types.ts` |

The Orchestrator appends channel types to the end of `ash_types.ts` after all resource schemas. Channel functions go into a separate file configured via `typed_channels_output_file`.

### Type Mapping

Channel payload types use `TypeMapper.map_channel_payload_type/2` instead of `map_type/3`. The codegen reads the publication's `returns` type — which Ash auto-populates when `transform :some_calc` references a calculation, or which can be set explicitly via `returns:`. The difference from RPC types: typed containers (maps/structs with `:fields`) generate plain object types without the `__type`/`__primitiveFields` metadata that the RPC field-selection system needs. Non-container types (primitives, lists, etc.) delegate to `map_type/3` with `:output` direction.

## DSL Reference

### Resource setup (recommended: calculation transforms)

Publications should use `transform :some_calc` to reference a resource calculation.
When the calculation uses `:auto` typing, Ash auto-derives `returns` from the expression:

```elixir
defmodule MyApp.Post do
  use Ash.Resource, notifiers: [Ash.Notifier.PubSub]

  pub_sub do
    module MyApp.Endpoint
    prefix "posts"

    publish :create, [:id], event: "post_created", public?: true, transform: :post_summary
    publish :update, [:id], event: "post_updated", public?: true, transform: :post_summary
  end

  calculations do
    calculate :post_summary, :auto, expr(%{id: id, title: title}) do
      public? true
    end
  end
  # ...
end

defmodule MyApp.Comment do
  use Ash.Resource, notifiers: [Ash.Notifier.PubSub]

  pub_sub do
    module MyApp.Endpoint
    prefix "comments"

    publish :create, [:id], event: "comment_created", public?: true, transform: :comment_body
  end

  calculations do
    calculate :comment_body, :auto, expr(body) do
      public? true
    end
  end
  # ...
end
```

You can also use explicit `returns` with an anonymous function transform:

```elixir
publish :create, [:id],
  event: "post_created",
  public?: true,
  returns: :map,
  constraints: [fields: [id: [type: :uuid], title: [type: :string]]],
  transform: fn notification -> %{id: notification.data.id, title: notification.data.title} end
```

### Channel definition

```elixir
defmodule MyApp.OrgChannel do
  use AshTypescript.TypedChannel

  typed_channel do
    topic "org:*"

    resource MyApp.Post do
      publish :post_created
      publish :post_updated
    end

    resource MyApp.Comment do
      publish :comment_created
    end
  end
end
```

### Section Options

| Option | Type | Required | Description |
|--------|------|----------|-------------|
| `topic` | string | Yes | Phoenix channel topic pattern (e.g. `"org:*"`) |

### Entity: `resource`

| Option | Type | Required | Description |
|--------|------|----------|-------------|
| `module` | atom | Yes | Ash resource module with PubSub publications (positional arg) |

### Entity: `publish`

| Option | Type | Required | Description |
|--------|------|----------|-------------|
| `event` | atom/string | Yes | Event name matching a publication on the resource (positional arg) |

## Compile-Time Verification

The `VerifyTypedChannel` verifier runs at compile time:

| Check | Severity | Description |
|-------|----------|-------------|
| Event exists | Error | Each declared event must match a publication on the resource |
| Unique events | Error | Event names must be unique across all resources in a channel |
| `public?: true` | Warning | Publications should be marked `public?: true` |
| `returns` set | Warning | Publications without `returns` (no `transform :calc` or explicit `returns:`) produce `unknown` TypeScript type |

## Generated TypeScript

### Types (in `ash_types.ts`)

```typescript
// Branded channel type — only creatable via factory
export type OrgChannel = {
  readonly __channelType: "OrgChannel";
  on(event: string, callback: (payload: unknown) => void): number;
  off(event: string, ref: number): void;
};

// Payload type aliases (deduplicated across channels)
export type PostCreatedPayload = {id: UUID, title: string | null};
export type CommentCreatedPayload = string;

// Events map
export type OrgChannelEvents = {
  post_created: PostCreatedPayload;
  comment_created: CommentCreatedPayload;
};

// Utility types for multi-subscribe and cleanup
export type OrgChannelHandlers = {
  [E in keyof OrgChannelEvents]?: (payload: OrgChannelEvents[E]) => void;
};
export type OrgChannelRefs = {
  [E in keyof OrgChannelEvents]?: number;
};
```

### Functions (in typed channels output file)

```typescript
// Factory — the only way to obtain a branded OrgChannel
export function createOrgChannel(
  socket: { channel(topic: string, params?: object): unknown },
  suffix: string
): OrgChannel { ... }

// Single-event subscription (generic over event name)
export function onOrgChannelMessage<E extends keyof OrgChannelEvents>(
  channel: OrgChannel, event: E,
  handler: (payload: OrgChannelEvents[E]) => void
): number { ... }

// Multi-event subscription
export function onOrgChannelMessages(
  channel: OrgChannel, handlers: OrgChannelHandlers
): OrgChannelRefs { ... }

// Cleanup
export function unsubscribeOrgChannel(
  channel: OrgChannel, refs: OrgChannelRefs
): void { ... }
```

### Topic Pattern Handling

The factory function adapts to the topic pattern:

| Topic | Factory Signature | Channel Construction |
|-------|-------------------|---------------------|
| `"org:*"` | `createOrgChannel(socket, suffix: string)` | `` socket.channel(`org:${suffix}`) `` |
| `"global"` (no wildcard) | `createOrgChannel(socket)` | `socket.channel("global")` |

### Payload Deduplication

When `generate_all_channel_types/1` processes multiple channels, payload type aliases are deduplicated by name. If two channels both declare `article_published` events from the same resource, only one `ArticlePublishedPayload` type is emitted.

### Payload Type Conflict Detection

Before deduplication, `validate_no_payload_type_conflicts!/2` checks that events sharing a payload type name also share the same TypeScript type. If two events across different channels produce the same type name (e.g., `ItemCreatedPayload`) but map to different TypeScript types (e.g., `{id: UUID}` vs `string`), codegen raises a `RuntimeError` with details about the conflicting events and channels.

This can happen when two resources declare publications with the same event name but different `returns` types (whether auto-derived from calculation transforms or explicitly declared), and those resources are used in separate channels. The verifier's unique-event check only applies within a single channel, so this cross-channel conflict is caught at codegen time instead.

## Configuration

```elixir
config :ash_typescript,
  typed_channels: [MyApp.OrgChannel, MyApp.ContentFeedChannel],
  typed_channels_output_file: "assets/js/ash_typed_channels.ts"
```

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `typed_channels` | `list(module)` | `[]` | Modules using `AshTypescript.TypedChannel` |
| `typed_channels_output_file` | `string \| nil` | `nil` | Output file for channel functions (when `nil`, no file is generated) |

## Orchestrator Integration

The `Orchestrator.generate/2` handles typed channels in two steps:

1. **Types**: `collect_typed_channel_entries/0` gathers `{module, topic}` tuples, then `generate_all_channel_types/1` appends branded types and event maps to `ash_types.ts`
2. **Functions**: `generate_all_channel_functions/1` produces subscription helpers, `ImportResolver` adds type imports, and the result is written to `typed_channels_output_file`

Channel entries are collected once and reused for both steps.

## Key Files

| File | Purpose |
|------|---------|
| `lib/ash_typescript/typed_channel.ex` | Main DSL module (`use Spark.Dsl`) |
| `lib/ash_typescript/typed_channel/dsl.ex` | DSL extension (Publication, ChannelResource structs, Spark entities) |
| `lib/ash_typescript/typed_channel/info.ex` | Spark introspection helpers |
| `lib/ash_typescript/typed_channel/codegen.ex` | Type and function generation |
| `lib/ash_typescript/typed_channel/verifiers/verify_typed_channel.ex` | Compile-time validation |
| `lib/ash_typescript/codegen/type_mapper.ex` | `map_channel_payload_type/2` and `build_plain_map_type/2` |
| `lib/ash_typescript/codegen/orchestrator.ex` | Integration into multi-file generation |
| `lib/ash_typescript.ex` | Config accessors (`typed_channels/0`, `typed_channels_output_file/0`) |

## Testing

### Test Files

| File | Purpose |
|------|---------|
| `test/ash_typescript/typed_channel/codegen_test.exs` | Single-channel codegen, static topic, deduplication, orchestrator integration |
| `test/ash_typescript/typed_channel/multi_resource_codegen_test.exs` | Multi-resource channels, cross-channel isolation, batch generation, payload type conflict detection |
| `test/ash_typescript/typed_channel/verify_typed_channel_test.exs` | Verifier tests: missing events, duplicate events, missing returns/public warnings |

### Test Resources

| File | Purpose |
|------|---------|
| `test/support/resources/channel_item.ex` | Resource with map, integer, string publications |
| `test/support/resources/channel_article.ex` | Resource with map, string, boolean publications |
| `test/support/resources/channel_review.ex` | Resource with integer, boolean publications |
| `test/support/resources/channel_alert.ex` | Resource with map, utc_datetime publications |
| `test/support/resources/org_channel.ex` | Single-resource channel (ChannelItem) |
| `test/support/resources/content_feed_channel.ex` | Two-resource channel (Article + Review) |
| `test/support/resources/moderation_channel.ex` | Three-resource channel (Article + Review + Alert) |
| `test/support/resources/full_activity_channel.ex` | All events from all resources |

Inline test resources (defined in test files to avoid compile-time warnings in CI):

| File | Inline Modules | Purpose |
|------|---------------|---------|
| `codegen_test.exs` | `NoReturnsItem`, `NoReturnsChannel`, `StaticTopicChannel` | Unknown payload type, static topic factory |
| `multi_resource_codegen_test.exs` | `ConflictItemA/B`, `ConflictChannelA/B` | Payload type conflict detection |
| `verify_typed_channel_test.exs` | `VerifierNoReturnsItem/Channel`, `VerifierNotPublicItem/Channel`, `DuplicateEventItem`, `ChannelWithMissingEvent`, `ChannelWithDuplicateEvents` | Verifier error and warning paths |

### Running Tests

```bash
mix test test/ash_typescript/typed_channel/   # Typed channel tests
```

## Common Issues

| Error | Cause | Solution |
|-------|-------|----------|
| "No publication with event X found" | Event name doesn't match any publication on the resource | Check the `event:` option (or action name fallback) on the resource's `pub_sub` block |
| "Duplicate event names found" | Same event name used across multiple resources in one channel | Use unique event names per channel |
| "Payload type name conflict" | Same event name across different channels maps to different TypeScript types | Rename conflicting events or ensure they return the same type |
| `unknown` TypeScript payload type | Publication missing `returns` type (no `transform :calc` or explicit `returns:`) | Use `transform :some_calc` with an `:auto`-typed calculation (recommended), or add explicit `returns:` |
| Channel types not in output | `typed_channels` not configured | Add modules to `typed_channels: [...]` in config |
| Channel functions not generated | `typed_channels_output_file` not configured | Set `typed_channels_output_file:` in config |
