<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Typed Channel Event Subscriptions

AshTypescript can generate typed TypeScript event subscriptions from Ash PubSub publications. This enables type-safe handling of server-pushed events over Phoenix channels.

## When to Use Typed Channels

Use `AshTypescript.TypedChannel` when your application pushes events to clients via Ash PubSub and you want typed payloads on the frontend.

| Use Case | Recommended Approach |
|----------|---------------------|
| Server pushes events to clients (notifications, updates) | **TypedChannel** |
| Client sends requests, server responds (CRUD, queries) | [RPC Actions](../guides/crud-operations.md) |
| Client sends requests over WebSocket | [Channel-based RPC](phoenix-channels.md) |
| Controller-style routes (Inertia, redirects) | [Typed Controllers](../guides/typed-controllers.md) |

## Requirements

Typed channels require **Ash >= 3.17.1**, which introduced `returns`, `public?`, and calculation `transform` support on PubSub publications. **Ash >= 3.21.1 is recommended**, as it added support for `:auto`-typed calculations as transforms, allowing Ash to automatically derive the `returns` type from the calculation expression.

## Quick Start

### 1. Add PubSub publications with calculation transforms

The recommended way to get typed payloads is to use `transform :some_calc` on
publications, pointing to a resource calculation with `:auto` typing. Ash
automatically derives the `returns` type from the calculation expression, so
AshTypescript gets the type information it needs without manual `returns`
declarations.

```elixir
defmodule MyApp.Post do
  use Ash.Resource,
    domain: MyApp.Domain,
    notifiers: [Ash.Notifier.PubSub]

  pub_sub do
    module MyAppWeb.Endpoint
    prefix "posts"

    publish :create, [:id],
      event: "post_created",
      public?: true,
      transform: :post_summary

    publish :update, [:id],
      event: "post_updated",
      public?: true,
      transform: :post_title
  end

  calculations do
    calculate :post_summary, :auto, expr(%{id: id, title: title}) do
      public? true
    end

    calculate :post_title, :auto, expr(title) do
      public? true
    end
  end

  # ... attributes, actions, etc.
end
```

You can also use explicit `returns` with an anonymous function transform, but
this requires manually keeping the type and transform in sync:

```elixir
publish :create, [:id],
  event: "post_created",
  public?: true,
  returns: :map,
  constraints: [
    fields: [
      id: [type: :uuid, allow_nil?: false],
      title: [type: :string, allow_nil?: true]
    ]
  ],
  transform: fn notification ->
    %{id: notification.data.id, title: notification.data.title}
  end
```

### 2. Define your channel

A typed channel consists of two parts: a DSL module that declares which events get TypeScript types, and a Phoenix channel that handles runtime behavior. You can put them in the same module or keep them separate.

```elixir
defmodule MyAppWeb.OrgChannel do
  # DSL for TypeScript codegen — declares which events to type
  use AshTypescript.TypedChannel

  # Phoenix channel for runtime behavior
  use Phoenix.Channel

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

  # Authorization — you own this logic
  @impl true
  def join("org:" <> org_id, _payload, socket) do
    if authorized?(socket, org_id) do
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  # Handle incoming messages from the client (if needed)
  @impl true
  def handle_in("ping", _payload, socket) do
    {:reply, {:ok, %{message: "pong"}}, socket}
  end
end
```

Register the channel in your socket:

```elixir
defmodule MyAppWeb.UserSocket do
  use Phoenix.Socket

  channel "org:*", MyAppWeb.OrgChannel

  @impl true
  def connect(params, socket, _connect_info) do
    {:ok, socket}
  end

  @impl true
  def id(_socket), do: nil
end
```

A single channel can subscribe to events from any number of resources. All events are merged into one typed events map. Event names must be unique across all resources in a channel.

### 3. Configure AshTypescript

```elixir
# config/config.exs
config :ash_typescript,
  typed_channels: [MyAppWeb.OrgChannel],
  typed_channels_output_file: "assets/js/ash_typed_channels.ts"
```

### 4. Generate TypeScript

```bash
mix ash_typescript.codegen
```

### 5. Use in your frontend

```typescript
import { createOrgChannel, onOrgChannelMessages, unsubscribeOrgChannel } from './ash_typed_channels';

// Create a branded channel instance
const channel = createOrgChannel(socket, orgId);
channel.join();

// Subscribe to events with full type safety
const refs = onOrgChannelMessages(channel, {
  post_created: (payload) => {
    // payload is typed as { id: UUID, title: string | null }
    console.log("New post:", payload.title);
  },
  post_updated: (payload) => {
    // payload is typed as string
    console.log("Updated title:", payload);
  },
});

// Cleanup when done
unsubscribeOrgChannel(channel, refs);
```

## DSL Reference

### `typed_channel` Section

| Option | Type | Required | Description |
|--------|------|----------|-------------|
| `topic` | string | Yes | Phoenix channel topic pattern (e.g. `"org:*"`) |

### `resource` Entity

Declares an Ash resource whose PubSub publications this channel subscribes to.

```elixir
resource MyApp.Post do
  publish :post_created
  publish :post_updated
end
```

| Option | Type | Required | Description |
|--------|------|----------|-------------|
| `module` | atom | Yes | Ash resource module (positional argument) |

### `publish` Entity

Declares a specific PubSub event to subscribe to.

| Option | Type | Required | Description |
|--------|------|----------|-------------|
| `event` | atom/string | Yes | Event name matching a publication on the resource (positional argument) |

The event name must match the `event:` option (or action name fallback) of a publication in the resource's `pub_sub` block.

## Generated TypeScript

### Types (in `ash_types.ts`)

For each configured channel, the following types are generated:

```typescript
// Branded channel type - prevents mixing channel instances
export type OrgChannel = {
  readonly __channelType: "OrgChannel";
  on(event: string, callback: (payload: unknown) => void): number;
  off(event: string, ref: number): void;
};

// Payload type aliases (one per event)
export type PostCreatedPayload = {id: UUID, title: string | null};
export type PostUpdatedPayload = string;
export type CommentCreatedPayload = unknown;

// Events map - maps event names to payload types
export type OrgChannelEvents = {
  post_created: PostCreatedPayload;
  post_updated: PostUpdatedPayload;
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
// Factory - creates a branded channel instance
export function createOrgChannel(
  socket: { channel(topic: string, params?: object): unknown },
  suffix: string
): OrgChannel {
  return socket.channel(`org:${suffix}`) as OrgChannel;
}

// Single-event subscription (generic over event name)
export function onOrgChannelMessage<E extends keyof OrgChannelEvents>(
  channel: OrgChannel,
  event: E,
  handler: (payload: OrgChannelEvents[E]) => void
): number { ... }

// Multi-event subscription (subscribe to multiple events at once)
export function onOrgChannelMessages(
  channel: OrgChannel,
  handlers: OrgChannelHandlers
): OrgChannelRefs { ... }

// Cleanup (unsubscribe all refs)
export function unsubscribeOrgChannel(
  channel: OrgChannel,
  refs: OrgChannelRefs
): void { ... }
```

## Topic Patterns

The topic string determines the factory function signature:

| Topic Pattern | Factory Signature | Usage |
|--------------|-------------------|-------|
| `"org:*"` (wildcard) | `createOrgChannel(socket, suffix)` | `createOrgChannel(socket, orgId)` |
| `"global"` (no wildcard) | `createGlobalChannel(socket)` | `createGlobalChannel(socket)` |

Wildcard topics require a `suffix` parameter that replaces the `*`. The factory constructs the full topic string (e.g., `org:${suffix}`).

## Payload Type Resolution

The TypeScript payload type is derived from the publication's `returns` type. When using `transform :some_calc`, Ash auto-populates `returns` from the calculation's type. You can also set `returns` explicitly.

| `returns` Value | TypeScript Type | How to Get It |
|----------------|-----------------|---------------|
| `:string` | `string` | `calculate :my_calc, :auto, expr(name)` or explicit `returns: :string` |
| `:integer` | `number` | `calculate :my_calc, :auto, expr(priority)` or explicit `returns: :integer` |
| `:boolean` | `boolean` | `calculate :my_calc, :auto, expr(active == true)` or explicit `returns: :boolean` |
| `:uuid` | `UUID` | `calculate :my_calc, :auto, expr(id)` or explicit `returns: :uuid` |
| `:utc_datetime` | `UtcDateTime` | Explicit `returns: :utc_datetime` |
| `:map` with `fields` | `{fieldName: type, ...}` | `calculate :my_calc, :auto, expr(%{id: id, name: name})` or explicit `returns: :map` with `constraints` |
| Not set | `unknown` | Missing `transform :calc` and no explicit `returns` |

Map types with `:fields` constraints generate plain object types without the `__type`/`__primitiveFields` metadata used by the RPC field-selection system.

### Multi-Channel Payload Deduplication

When multiple channels are configured, payload type aliases are deduplicated by name. If two channels both subscribe to `article_published` from the same resource, only one `ArticlePublishedPayload` type is emitted in `ash_types.ts`.

If two different resources declare publications with the same event name but different `returns` types (whether auto-derived or explicit) and those resources appear in separate channels, codegen will raise an error:

```
Payload type name conflict detected across typed channels.
```

To fix this, rename the conflicting events to be unique, or ensure they return the same type.

## Frontend Usage Patterns

### Single-Event Subscription

```typescript
const ref = onOrgChannelMessage(channel, "post_created", (payload) => {
  // payload is PostCreatedPayload
  addPostToList(payload);
});

// Unsubscribe later
channel.off("post_created", ref);
```

### Multi-Event Subscription

```typescript
const refs = onOrgChannelMessages(channel, {
  post_created: (payload) => addPostToList(payload),
  post_updated: (payload) => updatePostTitle(payload),
  comment_created: (payload) => showNotification(payload),
});

// Unsubscribe all at once
unsubscribeOrgChannel(channel, refs);
```

### With Svelte or React

```typescript
// Svelte example
onMount(() => {
  const channel = createOrgChannel(socket, orgId);
  channel.join();

  const refs = onOrgChannelMessages(channel, {
    post_created: (payload) => posts = [...posts, payload],
  });

  return () => {
    unsubscribeOrgChannel(channel, refs);
    channel.leave();
  };
});
```

## Compile-Time Verification

The DSL verifier checks your configuration at compile time:

| Check | Severity | What It Catches |
|-------|----------|----------------|
| Event exists | Error | Declared event doesn't match any publication on the resource |
| Unique events | Error | Same event name used across multiple resources in one channel |
| `public?: true` | Warning | Publication not marked as public |
| `returns` set | Warning | Publication missing `returns` — no `transform :calc` or explicit `returns:` (payload type becomes `unknown`) |

## Configuration

```elixir
config :ash_typescript,
  typed_channels: [MyApp.OrgChannel, MyApp.ActivityChannel],
  typed_channels_output_file: "assets/js/ash_typed_channels.ts"
```

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `typed_channels` | `list(module)` | `[]` | Modules using `AshTypescript.TypedChannel` |
| `typed_channels_output_file` | `string \| nil` | `nil` | Output file for channel functions (when `nil`, no file is generated) |

Channel types are appended to `ash_types.ts`. Channel functions go into the separate `typed_channels_output_file` and import their types from `ash_types.ts`.

## Next Steps

- [Phoenix Channel-based RPC](phoenix-channels.md) - Request/response RPC over channels
- [Configuration Reference](../reference/configuration.md) - All configuration options
- [Lifecycle Hooks](lifecycle-hooks.md) - Add hooks for logging and telemetry
