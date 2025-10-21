<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>

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

  @impl true
  def join("ash_typescript_rpc:" <> _user_id, _payload, socket) do
    {:ok, socket}
  end

  def handle_in("run", params, socket) do
    result =
      AshTypescript.Rpc.run_action(
        :my_app,
        socket,
        params
      )

    {:reply, {:ok, result}, socket}
  end

  def handle_in("validate", params, socket) do
    result =
      AshTypescript.Rpc.validate_action(
        :my_app,
        socket,
        params
      )

    {:reply, {:ok, result}, socket}
  end

  # Catch-all for unhandled messages
  @impl true
  def handle_in(event, payload, socket) do
    {:reply, {:error, %{reason: "Unknown event: #{event}", payload: payload}}, socket}
  end
end
```

**Important Notes:**
- Replace `:my_app` with your actual app's OTP application name (the atom used in `AshTypescript.Rpc.run_action/3`)
- The socket connection should set `socket.assigns.ash_actor` and `socket.assigns.ash_tenant` if your app uses authentication or multitenancy

## Channel Function Features

Channel functions support all the same features as HTTP functions:

```typescript
// Pagination with channels
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
        if (error.fieldPath) {
          console.error(`Field: ${error.fieldPath}`);
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
