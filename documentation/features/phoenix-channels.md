<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Phoenix Channel-based RPC Actions

AshTypescript can generate Phoenix channel-based RPC functions alongside the standard HTTP-based functions. This is useful for real-time applications that need to communicate over WebSocket connections.

## Configuration

Enable channel function generation in your configuration:

```elixir
# config/config.exs
config :ash_typescript,
  generate_phx_channel_rpc_actions: true,
  phoenix_import_path: "phoenix"  # customize if needed
```

## Generated Channel Functions

When enabled, AshTypescript generates channel functions with the suffix `Channel` for each RPC action:

```typescript
import { Channel } from "phoenix";
import { createTodo, createTodoChannel } from './ash_rpc';

// Standard HTTP-based function (always available)
const httpResult = await createTodo({
  fields: ["id", "title"],
  input: {
    title: "New Todo",
    userId: "user-123"
  }
});

// Channel-based function (generated when enabled)
createTodoChannel({
  channel: myChannel,
  fields: ["id", "title"],
  input: {
    title: "New Todo",
    userId: "user-123"
  },
  resultHandler: (result) => {
    if (result.success) {
      console.log("Todo created:", result.data);
    } else {
      console.error("Creation failed:", result.errors);
    }
  },
  errorHandler: (error) => {
    console.error("Channel error:", error);
  },
  timeoutHandler: () => {
    console.error("Request timed out");
  }
});
```

## Setting up Phoenix Channels

### Frontend Setup

First, establish a Phoenix channel connection:

```typescript
import { Socket } from "phoenix";

const socket = new Socket("/socket", {
  params: { authToken: "your-auth-token" }
});

socket.connect();

const ashTypeScriptRpcChannel = socket.channel("ash_typescript_rpc:<user-id or something else unique>", {});
ashTypeScriptRpcChannel.join()
  .receive("ok", () => console.log("Connected to channel"))
  .receive("error", resp => console.error("Unable to join", resp));
```

### Backend Channel Setup

To enable Phoenix Channel support for AshTypescript RPC actions, configure your Phoenix socket and channel handlers:

```elixir
# In your my_app_web/channels/user_socket.ex or equivalent
defmodule MyAppWeb.UserSocket do
  use Phoenix.Socket

  channel "ash_typescript_rpc:*", MyAppWeb.AshTypescriptRpcChannel

  @impl true
  def connect(params, socket, _connect_info) do
    # AshTypescript assumes that socket.assigns.ash_actor & socket.assigns.ash_tenant are correctly set if needed.
    # This should be done during the socket connection setup, usually by decrypting the auth token sent by the client.
    # See https://hexdocs.pm/phoenix/channels.html#using-token-authentication for more information.
    {:ok, socket}
  end

  @impl true
  def id(_socket), do: nil  # Return a unique identifier if you need presence tracking
end

# In your my_app_web/channels/ash_typescript_rpc_channel.ex
defmodule MyAppWeb.AshTypescriptRpcChannel do
  use Phoenix.Channel
  use AshRpc.Channel, profile: AshTypescript.RpcProfile

  @impl true
  def join("ash_typescript_rpc:" <> _user_id, _payload, socket) do
    {:ok, socket}
  end
end
```

`use AshRpc.Channel` injects `handle_in/3` clauses for the `"run"` and
`"validate"` events (replying `{:ok, result}`, with success or failure in the
result body) plus a catch-all that replies
`{:error, %{reason: "Unknown event: ...", payload: ...}}` to any other event.
Your module owns `join/3`, topics and socket authentication.

Because the injected clauses include a catch-all, don't define further
`handle_in/3` clauses in the same module. If your channel needs extra events,
skip the macro and call `AshRpc.Channel.run/3` / `AshRpc.Channel.validate/3`
from your own `handle_in/3`:

```elixir
defmodule MyAppWeb.AshTypescriptRpcChannel do
  use Phoenix.Channel

  @impl true
  def join("ash_typescript_rpc:" <> _user_id, _payload, socket), do: {:ok, socket}

  @impl true
  def handle_in("run", params, socket),
    do: {:reply, {:ok, AshRpc.Channel.run(AshTypescript.RpcProfile, socket, params)}, socket}

  def handle_in("validate", params, socket),
    do: {:reply, {:ok, AshRpc.Channel.validate(AshTypescript.RpcProfile, socket, params)}, socket}

  def handle_in("ping", _payload, socket), do: {:reply, {:ok, %{pong: true}}, socket}
end
```

**Important Notes:**
- Actor, tenant and context are read from `socket.assigns.ash_actor`, `socket.assigns.ash_tenant` and `socket.assigns.ash_context`. Set them during socket connection if your app uses authentication or multitenancy
- A `tenant` parameter sent with the request overrides `socket.assigns.ash_tenant`, exactly as it does over HTTP. The value is passed to Ash unvalidated, so invalid or unauthorized tenants surface as normal Ash/policy errors

## Channel Function Features

Channel functions support all the same features as HTTP functions:

```typescript
// Pagination with channels — the result narrows to the paginated shape,
// just like the HTTP functions
listTodosChannel({
  channel: ashTypeScriptRpcChannel,
  fields: ["id", "title", { user: ["name"] }],
  filter: { completed: { eq: false } },
  page: { limit: 10, offset: 0 },
  resultHandler: (result) => {
    if (result.success) {
      console.log("Todos:", result.data.results);
      console.log("Has more:", result.data.hasMore);
    }
  }
});

// Complex field selection
getTodoChannel({
  channel: ashTypeScriptRpcChannel,
  input: { id: "todo-123" },
  fields: [
    "id", "title", "description",
    {
      user: ["name", "email"],
      comments: ["text", { author: ["name"] }]
    }
  ],
  resultHandler: (result) => {
    // Fully type-safe result handling
  }
});
```

## Error Handling

Channel functions provide the same error structure as HTTP functions:

```typescript
createTodoChannel({
  channel: myChannel,
  fields: ["id", "title"],
  input: {
    title: "New Todo",
    userId: "user-123"
  },
  resultHandler: (result) => {
    if (result.success) {
      // result.data is fully typed based on selected fields
      console.log("Created:", result.data.title);
    } else {
      // Handle validation errors, etc.
      result.errors.forEach(error => {
        console.error(`Error: ${error.message}`);
        if (error.fields.length > 0) {
          console.error(`Fields: ${error.fields.join(', ')}`);
        }
      });
    }
  },
  errorHandler: (error) => {
    // Handle channel-level errors
    console.error("Channel communication error:", error);
  },
  timeoutHandler: () => {
    // Handle timeouts
    console.error("Request timed out");
  }
});
```

## Next Steps

- [Lifecycle Hooks](lifecycle-hooks.md) - Add hooks for logging and telemetry
- [Multitenancy](multitenancy.md) - Tenant support with channels
- [Error Handling](../guides/error-handling.md) - Comprehensive error handling patterns
- [Configuration Reference](../reference/configuration.md) - All channel configuration options
