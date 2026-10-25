<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik

SPDX-License-Identifier: MIT
-->

# Typed Channel

## Overview

The `AshTypescript.TypedChannel` DSL generates typed TypeScript event subscriptions from Ash PubSub publications. It reads the `returns` type from each declared publication and generates branded channel types, typed payload aliases, event maps, and subscription helper functions.

**Recommended approach**: Use `transform :some_calc` on publications to reference a resource calculation. When the calculation uses `:auto` typing, Ash automatically derives the `returns` type from the expression, so AshTypescript gets full type information without any manual `returns` declarations. This keeps the type and the transform logic in sync via a single source of truth (the calculation). You can also use explicit `returns:` (a typed map, with `constraints`) with an anonymous function transform, but this requires manually keeping the type and transform in sync. Every declared publication needs a `returns` that is a typed map (checked when the manifest compiles; see [Payloads are plain data](#payloads-are-plain-data-manifest-compile)).

**Key distinction**: `AshTypescript.Rpc` with `generate_phx_channel_rpc_actions` is for request/response RPC over channels. `AshTypescript.TypedChannel` is for one-way push events (PubSub broadcasts) where the server pushes typed payloads to the client.

**Important**: `AshTypescript.TypedChannel` is a standalone Spark DSL — completely independent from `Ash.Resource` and `AshTypescript.Rpc`. The developer owns channel authorization via Phoenix's `join/3`.

## Requirements

Typed channels rely on `returns`, `public?`, and calculation `transform` support on PubSub publications, as well as `:auto`-typed calculations as transforms — all introduced in **Ash 3.21.1**. AshTypescript 0.18 requires `~> 3.27` regardless (see `mix.exs`).

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

Channel payload types use `TypeMapper.map_channel_payload_type/1` instead of `map_type/3`. It takes the decorated `%Ash.Info.Manifest.Type{}` of the channel's manifest `%Publication{}` (the publication's `returns`, which Ash auto-populates when `transform :some_calc` references a calculation, or which can be set explicitly via `returns:`), so field names match the pushed payload. It maps like a typed controller route result (`map_route_result_type/1`, the same code): typed containers (`Ash.Type.Map`/`Keyword`/`Tuple`/`Struct` carrying a `:fields` constraint, declared custom types included), at any depth and inside arrays, generate plain object types without the `__type`/`__primitiveFields` metadata that the RPC field-selection system needs. Containers with no `:fields` fall back to the configured `untyped_map_type`. Other types (primitives, resources, unions) delegate to `map_type/3` with `:output` direction.

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
    calculate :comment_body, :auto, expr(%{body: body}) do
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
defmodule MyAppWeb.OrgChannel do
  use Phoenix.Channel
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

  @impl true
  def join("org:" <> _org_id, _payload, socket), do: {:ok, socket}
end
```

The module must also `use Phoenix.Channel` (compile warning otherwise). `use AshTypescript.TypedChannel` injects — via Spark's `handle_before_compile/1` and `AshTypescript.TypedChannel.Interception` — an intercept for every declared event plus `handle_out/3` clauses that format the broadcast payload through `AshTypescript.TypedChannel.PayloadFormatter` (the decorated `returns` of the channel's manifest `%Publication{}` + `ValueFormatter`, same as RPC output; see [Publications in the Manifest](#publications-in-the-manifest)) before pushing. This makes the wire payload match the generated TypeScript types, which use the `output_field_formatter`. User-defined `intercept` calls are merged into the intercept list, and no `handle_out/3` clause is injected for an event the module already handles itself (detected via `Module.get_definition/2`, since `before_compile` clauses shadow an identical clause head in the module body). Such a module should also `intercept` that event itself to avoid a spurious Phoenix definition-time warning. Interception disables Phoenix's fastlane for the declared events (per-subscriber encoding).

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

| Check | Severity | Config toggle | Description |
|-------|----------|---------------|-------------|
| Event exists | Error | — | Each declared event must match a publication on the resource |
| Unique events | Error | — | Event names must be unique across all resources in a channel |
| `public?: true` | Warning | `warn_on_non_public_publications` (default `true`) | Publications should be marked `public?: true` |

The warning can be silenced via config; the two hard errors cannot.

### Payloads are plain data (manifest compile)

`AshTypescript.Manifest.PlainData.check_publication!/2`, run from
`TypedRoutes.decorate/5` right after the untyped-struct check, raises a
`Spark.Error.DslError` (path `[:typed_channel]`; Spark sets `module` to the manifest
module, the message names the channel, event and resource) when a listed channel's
publication:

- has no `returns` (no `transform :calc` and no explicit `returns:`);
- reaches a resource, an embedded resource (a `:struct` `instance_of` a resource is a
  resource node once decorated) or a union at any depth, through NewTypes and declared
  `custom_types` included, or a named type that contains itself (walked with
  `AshRpc.Introspection.find_type_root/4`, `cycles: :report`; codegen expands named
  types inline);
- is not a typed map at the top level after resolving `:type_ref`s: a scalar, an
  enum, an array, an opaque custom type (all "not a typed map", since Phoenix only
  pushes JSON objects), or untyped data (`:term`, `:map` without `fields`).

Allowed: `:map`/`:struct`/`:keyword`/`:tuple` with `fields` (an `Ash.TypedStruct`, a
declared `map` custom type, a NewType of one), with any fields inside, untyped ones
included. The rule is on declared types: a typed map built from a record is fine.
The `warn_on_missing_channel_returns` config key is gone (a legacy-key warning names it).

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
export type CommentCreatedPayload = {body: string | null};

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

## Publications in the Manifest

The manifest module's `typed_channels:` option is the only source of typed channels
(`config :ash_typescript, :typed_channels` is ignored and triggers a compile-time
warning). `BuildManifest` reads every declared event of each listed channel with
`TypedRouteCollector`, and `AshTypescript.Manifest.TypedRoutes` decorates them during
`DecorateManifest`.

- `%AshTypescript.Manifest.Publication{}` (`lib/ash_typescript/manifest/publication.ex`):
  `channel_module`, `resource`, `event` and the decorated `returns`, keyed
  `{channel_module, resource, event}` under `custom.ash_typescript.publications`. Two
  channels declaring the same publication get one entry each
- `returns` is always a typed map: a publication without one is rejected when the
  manifest compiles (see [Payloads are plain data](#payloads-are-plain-data-manifest-compile))
- Read with `AshTypescript.Manifest.Custom.publication/4` / `publications/1` (`nil`
  source reads the configured manifest and honours `AshTypescript.with_manifest/2`)
- `PayloadFormatter.format_payload(channel_module, resource, event, payload)` and
  `push_formatted(socket, channel_module, resource, event, payload)` look the
  publication up; the `handle_out/3` clauses `Interception` injects pass `__MODULE__`.
  No publication for the key (channel not listed, or a stale manifest) → payload pushed
  unchanged plus a `Logger.warning` naming the channel, event, resource and the
  `typed_channels:` option. There is no DSL fallback
- The manifest has a compile-time edge on every listed channel, so a typed channel must
  never read the manifest at compile time
- Codegen's channel set is `Orchestrator.channel_entries/0`: the unique
  `channel_module`s of `Custom.publications/0`, with topic and declared events from the
  channel's DSL
- Codegen warns about typed channels (and typed controllers) among
  `Application.spec(otp_app, :modules)` that declare publications (routes) but have
  none in the manifest: `TypeDiscovery.build_unlisted_typed_modules_warning/3`, toggle
  `warn_on_unlisted_typed_modules`
- Tests that need other channels build a scoped manifest with
  `AshTypescript.Test.InlineManifest.build!(typed_channels: [...])` and use
  `AshTypescript.with_manifest/2`, never `Application.put_env/3`

## Configuration

```elixir
use AshTypescript.Manifest, otp_app: :my_app, typed_channels: [MyApp.OrgChannel, MyApp.ContentFeedChannel]

config :ash_typescript,
  typed_channels_output_file: "assets/js/ash_typed_channels.ts"
```

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `typed_channels_output_file` | `string \| nil` | `nil` | Output file for channel functions (when `nil`, no file is generated) |
| `warn_on_non_public_publications` | `boolean` | `true` | Warn when a referenced publication is not `public?: true` |
| `warn_on_unlisted_typed_modules` | `boolean` | `true` | Warn at codegen when a typed channel or controller isn't listed in the manifest |

## Orchestrator Integration

The `Orchestrator.generate/2` handles typed channels in two steps:

1. **Types**: `channel_entries/0` gathers `{module, topic}` tuples for the channels in the manifest, then `generate_all_channel_types/1` appends branded types and event maps to `ash_types.ts`
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
| `lib/ash_typescript/codegen/type_mapper.ex` | `map_channel_payload_type/1` |
| `lib/ash_typescript/typed_channel/payload_formatter.ex` | Formats pushed payloads from the manifest publication |
| `lib/ash_typescript/typed_channel/interception.ex` | Injected `intercept` and `handle_out/3` clauses |
| `lib/ash_typescript/manifest/publication.ex` | `%Publication{}` stored in the manifest |
| `lib/ash_typescript/codegen/orchestrator.ex` | Integration into multi-file generation |
| `lib/ash_typescript.ex` | Config accessor `typed_channels_output_file/0` |

## Testing

### Test Files

| File | Purpose |
|------|---------|
| `test/ash_typescript/typed_channel/codegen_test.exs` | Single-channel codegen, static topic, deduplication, orchestrator integration |
| `test/ash_typescript/typed_channel/multi_resource_codegen_test.exs` | Multi-resource channels, cross-channel isolation, batch generation, payload type conflict detection |
| `test/ash_typescript/typed_channel/verify_typed_channel_test.exs` | Verifier tests: missing events, duplicate events, the non-public warning |
| `test/ash_typescript/typed_channel/interception_test.exs` | Injected `handle_out/3`, payload formatting, unlisted-channel warning |
| `test/ash_typescript/typed_channel/payload_formatter_test.exs` | Keyword, tuple, struct and map NewType payloads through Phoenix's JSON serializer; typed scalar structs; `:term` values sent as produced |
| `test/ash_typescript/manifest/publications_test.exs` | Stored `%Publication{}` data per channel |
| `test/ash_typescript/manifest/plain_data_test.exs` | The plain-data rule for publication (and route) `returns`, at manifest compile |

### Test Resources

| File | Purpose |
|------|---------|
| `test/support/resources/channel_item.ex` | Resource with typed-map publications whose fields are maps, integers and strings (explicit `returns:` + fn transforms) |
| `test/support/resources/channel_article.ex` | Resource with typed-map publications with map, string and boolean fields (explicit `returns:`) |
| `test/support/resources/channel_review.ex` | Resource with typed-map publications with integer and boolean fields (explicit `returns:`) |
| `test/support/resources/channel_alert.ex` | Resource with typed-map publications, one with a utc_datetime field (explicit `returns:`) |
| `test/support/resources/channel_tracker.ex` | **Calculation-transform fixtures** (`transform :calc` + `:auto` calcs) — the recommended path. 10 map publications whose fields cover string, aggregate, boolean, nested-map and relationship-loading expressions |
| `test/support/resources/channel_tracker_author.ex` | Related resource loaded through tracker calculations |
| `test/support/resources/channel_tracker_entry.ex` | Related resource behind tracker aggregate calculations |
| `test/support/resources/org_channel.ex` | Single-resource channel (ChannelItem) |
| `test/support/resources/content_feed_channel.ex` | Two-resource channel (Article + Review) |
| `test/support/resources/moderation_channel.ex` | Three-resource channel (Article + Review + Alert) |
| `test/support/resources/full_activity_channel.ex` | All events from all resources |
| `test/support/resources/tracker_channel.ex` | Channel over ChannelTracker — exercises the calculation-transform path end to end |

Inline test resources (defined in test files to avoid compile-time warnings in CI):

| File | Inline Modules | Purpose |
|------|---------------|---------|
| `codegen_test.exs` | `StaticTopicChannel` (in `test/support/resources/static_topic_channel.ex`) | Static topic factory |
| `multi_resource_codegen_test.exs` | `ConflictItemA/B`, `ConflictChannelA/B` | Payload type conflict detection |
| `verify_typed_channel_test.exs` | `NoReturnsItem/Channel`, `NotPublicItem/Channel`, `DuplicateEventItem`, `ChannelWithMissingEvent`, `ChannelWithDuplicateEvents` | Verifier error and warning paths (a missing `returns` isn't the verifier's) |

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
| "publication ... has no `returns`" at manifest compile | Publication missing `returns` (no `transform :calc` or explicit `returns:`) | Use `transform :some_calc` with an `:auto` map calculation (recommended), or add explicit `returns:` with `constraints` and a `transform:` function |
| "publication ... returns X, which is not a typed map" / "returns untyped data" | A scalar, enum, array, opaque custom type, `:term` or unconstrained `:map` payload | Return a typed map (`returns: :map` with `fields`) and put the value in a field |
| "publication ... returns a resource / an embedded resource / a union / a recursive type" | Payloads are plain data | Declare a typed map built from the record; a field per union variant; a fixed depth for recursion |
| Channel types not in output, codegen warning "not listed in the manifest" | Channel not in the manifest module's `typed_channels:` | Add it: `use AshTypescript.Manifest, ..., typed_channels: [...]` |
| Payload pushed unformatted, warning "is not in the manifest" | Channel not in the manifest module's `typed_channels:`, or a stale manifest | List it on the manifest module and recompile |
| Channel functions not generated | `typed_channels_output_file` not configured | Set `typed_channels_output_file:` in config |
