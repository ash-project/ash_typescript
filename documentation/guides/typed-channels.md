<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Typed Channels

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

Typed channels require **Ash >= 3.21.1**, which introduced `returns`, `public?`, and calculation `transform` support on PubSub publications, as well as `:auto`-typed calculations as transforms.

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

    calculate :post_title, :auto, expr(%{title: title}) do
      public? true
    end
  end

  # ... attributes, actions, etc.
end
```

Every publication a typed channel declares needs a `returns` type, and it must be
a typed map: Phoenix only pushes JSON objects, so a payload is an object whose
fields are declared. A `:auto` calculation over a map expression (like the two
above) gives one. A scalar calculation (`expr(title)`) doesn't: wrap the value in a
map (`expr(%{title: title})`).

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

A typed channel is a Phoenix channel that also uses the `AshTypescript.TypedChannel` DSL to declare which events get TypeScript types. Both `use` statements go in the same module — a compile warning is emitted if `use Phoenix.Channel` is missing, because the typed channel machinery hooks into the channel itself (see [Payload formatting](#payload-formatting) below).

```elixir
defmodule MyAppWeb.OrgChannel do
  # Phoenix channel for runtime behavior
  use Phoenix.Channel

  # DSL for TypeScript codegen — declares which events to type
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

  # Authorization — you own this logic (define authorized?/2 yourself)
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

List the channel on your manifest module, and set the output file in config:

```elixir
# lib/my_app/ash_typescript_manifest.ex
defmodule MyApp.AshTypescriptManifest do
  use AshTypescript.Manifest,
    otp_app: :my_app,
    typed_channels: [MyAppWeb.OrgChannel]
end

# config/config.exs
config :ash_typescript,
  typed_channels_output_file: "assets/js/ash_typed_channels.ts"
```

The manifest stores every declared event of each listed channel, with its publication's `returns` type. Codegen generates exactly the listed channels (topic and events come from the channel's DSL) and warns about any typed channel that isn't listed (`warn_on_unlisted_typed_modules`), and payloads are formatted from the stored type. The manifest depends on the listed channels at compile time, so a typed channel must not read the manifest at compile time. In an umbrella app, the manifest module must live in an app that compiles after the channels (usually the web app).

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
  join(timeout?: number): unknown;
  leave(timeout?: number): unknown;
};

// Payload type aliases (one per event)
export type PostCreatedPayload = {id: UUID, title: string | null};
export type PostUpdatedPayload = {title: string | null};
export type CommentCreatedPayload = {id: UUID, body: string | null};

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

Payloads are plain data, checked when the manifest module compiles (which raises
with the channel, event and path to the offending type):

| `returns` Value | Result |
|----------------|--------|
| `:map` with `fields` | `{fieldName: type, ...}` (`calculate :my_calc, :auto, expr(%{id: id, name: name})`, or explicit `returns: :map` with `constraints`) |
| `:struct`, `:keyword` or `:tuple` with `fields`, an `Ash.TypedStruct`, or a NewType of a typed map | An object type with those fields |
| Not set (no `transform :calc` and no explicit `returns`) | Rejected: set `returns:` with `constraints`, or `transform:` a calculation typed as a map |
| A scalar, an enum, an array (even of typed maps), or a custom type that isn't declared as a `map` | Rejected: Phoenix only pushes JSON objects. Put the value in a field of a typed map |
| `:term` or `:map` without `fields` | Rejected: declare the `fields` |
| A resource, an embedded resource (or `:struct` with `instance_of` a resource), or a union, at any depth | Rejected: declare a typed map and build it from the record (`%{email: user.email}` with `fields: [email: [type: :string]]`); for a union, a typed map with a field per variant (all `allow_nil?: true`) |
| A named type that contains itself | Rejected: payload types are expanded inline. Expand it to a fixed depth or use an untyped `:map` field |

Fields inside a payload may be anything a typed field can be, untyped ones (`:term`,
`:map` without `fields`) included; only resources, unions and recursion are rejected
at every depth, including inside NewTypes and custom types declared in the manifest
module's `custom_types` section.

Map types with `:fields` constraints, nested ones included, generate plain object types without the `__type`/`__primitiveFields` metadata used by the RPC field-selection system. A map-like custom type with declared fields references its exported alias (`Money`, see [Custom Types](../advanced/custom-types.md#generated-typescript)), and so does a NewType or scalar with an alias (see [Naming the Type](../advanced/custom-types.md#naming-the-type)).

### Multi-Channel Payload Deduplication

When multiple channels are configured, payload type aliases are deduplicated by name. If two channels both subscribe to `article_published` from the same resource, only one `ArticlePublishedPayload` type is emitted in `ash_types.ts`.

If two different resources declare publications with the same event name but different `returns` types (whether auto-derived or explicit) and those resources appear in separate channels, codegen will raise an error:

```
Payload type name conflict detected across typed channels.
```

To fix this, rename the conflicting events to be unique, or ensure they return the same type.

## Payload Formatting

The generated payload types use the configured `output_field_formatter` (e.g. `conversation_id` becomes `conversationId` with `:camel_case`), matching the rest of the generated TypeScript. To make the wire payload match, `use AshTypescript.TypedChannel` automatically intercepts every declared event (via `Phoenix.Channel.intercept/1`) and injects `handle_out/3` clauses that format the broadcast payload — using the publication's `returns` type and the same type-driven formatter as RPC results — before pushing to the client.

Things to know:

- Formatting happens at the websocket boundary only. Elixir-side subscribers of the same PubSub topics (e.g. LiveViews) still receive the raw, untransformed payload.
- Your own `intercept` calls and `handle_out/3` clauses are preserved — the typed events are merged into the intercept list, and no clause is injected for an event you already handle yourself, so your clause owns the push (and you are responsible for formatting that payload).
- If you do write your own `handle_out/3` for a declared event, add it to your own `intercept/1` list as well. Phoenix checks the intercept list at definition time, before AshTypescript merges the typed events in, so it otherwise prints a spurious "An intercept for event ... has not yet been defined" warning. Listing it twice is harmless — the lists are deduplicated.
- Intercepting disables Phoenix's fastlane optimization for the declared events: payloads are encoded once per subscriber instead of once per broadcast. This is the standard cost of `Phoenix.Channel.intercept/1` and is usually negligible.
- The payload type comes from the manifest. A channel that isn't listed in the manifest module's `typed_channels:` option pushes its payloads unformatted and logs a warning naming the channel, event and resource.
- Because the interception must live in the channel that serves the topic, the DSL module must itself be a Phoenix channel — a compile warning is emitted otherwise, and payloads would reach clients unformatted.

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
  post_updated: (payload) => updatePostTitle(payload.title),
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

The payload rules above (`returns` required, a typed map, plain data) are checked
when the manifest module compiles, not by this verifier.

## Configuration

Channels are listed on the manifest module, not in config:

```elixir
defmodule MyApp.AshTypescriptManifest do
  use AshTypescript.Manifest,
    otp_app: :my_app,
    typed_channels: [MyApp.OrgChannel, MyApp.ActivityChannel]
end
```

| Manifest option | Type | Default | Description |
|--------|------|---------|-------------|
| `typed_channels` | `list(module)` | `[]` | Modules using `AshTypescript.TypedChannel`. The only source of typed channels |

```elixir
config :ash_typescript,
  typed_channels_output_file: "assets/js/ash_typed_channels.ts"
```

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `typed_channels_output_file` | `string \| nil` | `nil` | Output file for channel functions (when `nil`, no file is generated) |

Channel types are appended to `ash_types.ts`. Channel functions go into the separate `typed_channels_output_file` and import their types from `ash_types.ts`. A project without RPC output (no `output_file`) gets an `ash_types.ts` holding just the channel types and the aliases the payloads use (see [Multi-File Output](../reference/configuration.md#multi-file-output)).

## Next Steps

- [Phoenix Channel-based RPC](phoenix-channels.md) - Request/response RPC over channels
- [Configuration Reference](../reference/configuration.md) - All configuration options
- [Lifecycle Hooks](lifecycle-hooks.md) - Add hooks for logging and telemetry
