<!--
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Upgrading to the AshRpc Runtime

The server-side RPC runtime (request parsing, field selection, execution, result
formatting and error handling) moved out of AshTypescript.Rpc into the
`AshRpc` namespace, provided by the separate, client-agnostic `ash_rpc`
package. ash_typescript depends on it, so you don't add it to your deps
yourself.

ash_typescript connects to it through **`AshTypescript.RpcProfile`**, an
`AshRpc.Profile` that points the runtime at your AshTypescript manifest and
reads error handling from each domain's `typescript_rpc` section. Pass it
wherever the old API took your OTP app name.

Code generation, the DSLs (`typescript_rpc`, `typescript`, typed controllers,
typed channels) and the generated TypeScript are unchanged. The wire format is
the same, except for the error-type and tenant changes described below.

## Running RPC actions from a controller

Before:

```elixir
defmodule MyAppWeb.AshTypescriptRpcController do
  use MyAppWeb, :controller

  def run(conn, params) do
    result = AshTypescript.Rpc.run_action(:my_app, conn, params)
    json(conn, result)
  end

  def validate(conn, params) do
    result = AshTypescript.Rpc.validate_action(:my_app, conn, params)
    json(conn, result)
  end
end
```

After:

```elixir
defmodule MyAppWeb.AshTypescriptRpcController do
  use MyAppWeb, :controller

  def run(conn, _params), do: AshRpc.Plug.run(conn, AshTypescript.RpcProfile)

  def validate(conn, _params), do: AshRpc.Plug.validate(conn, AshTypescript.RpcProfile)
end
```

`AshRpc.Plug.run/2` and `AshRpc.Plug.validate/2` read `conn.params` and send
the JSON response themselves, always with status 200 (success or failure is in
the body). If you need the response map, for example to post-process it, call
the functions directly:

```elixir
result = AshRpc.run_action(AshTypescript.RpcProfile, conn, params)
result = AshRpc.validate_action(AshTypescript.RpcProfile, conn, params)
```

Both return the same client-formatted maps as before
(`%{"success" => true, "data" => ...}` / `%{"success" => false, "errors" => [...]}`).
The second argument can be a `%Plug.Conn{}`, a `%Phoenix.Socket{}`, or an
`%AshRpc.Context{actor: ..., tenant: ..., context: ...}` (useful from LiveViews
or background jobs). `opts` accepts `manifest:` and `entrypoint:`.

New installs get the new controller from `mix igniter.install ash_typescript`.

## Validating RPC actions

Before:

```elixir
AshTypescript.Rpc.validate_action(:my_app, conn, params)
```

After:

```elixir
AshRpc.validate_action(AshTypescript.RpcProfile, conn, params)
# or, in a controller action that sends the response:
AshRpc.Plug.validate(conn, AshTypescript.RpcProfile)
```

## Running typed queries

Before:

```elixir
AshTypescript.Rpc.run_typed_query(:my_app, :dashboard_todo, %{}, conn)
AshTypescript.Rpc.run_typed_query(:my_app, :todo_detail, %{input: %{id: id}}, conn)
```

After:

```elixir
AshTypescript.run_typed_query(:dashboard_todo, %{}, conn)
AshTypescript.run_typed_query(:todo_detail, %{input: %{id: id}}, conn)
```

The OTP app argument is gone, and `params` is now **required** (pass `%{}` when
there are none). `params` still takes `:input`, `:page`, `:filter` and `:sort`
with atom keys. The return value is unchanged. An unknown name still returns a
`typed_query_not_found` error.

## Custom error protocol implementations

Before:

```elixir
defimpl AshTypescript.Rpc.Error, for: MyApp.CustomError do
  def to_error(error), do: %{message: ..., short_message: ..., type: ..., vars: ..., fields: ..., path: ...}
end
```

After:

```elixir
defimpl AshRpc.Error, for: MyApp.CustomError do
  def to_error(error), do: %{message: ..., short_message: ..., type: ..., vars: ..., fields: ..., path: ...}
end
```

The callback and the returned map are unchanged; only the protocol name moved.

## Custom error handlers

Before:

```elixir
defmodule MyApp.CustomErrorHandler do
  @behaviour AshTypescript.Rpc.ErrorHandler

  def handle_error(error, context), do: error
end
```

After:

```elixir
defmodule MyApp.CustomErrorHandler do
  @behaviour AshRpc.ErrorHandler

  def handle_error(error, context), do: error
end
```

You still configure it the same way, with `error_handler` in the domain's
`typescript_rpc` section. The default handler is now
`AshRpc.DefaultErrorHandler` (it was `AshTypescript.Rpc.DefaultErrorHandler`).
If you referenced it explicitly, rename the reference.

## Phoenix channel handlers

Before:

```elixir
defmodule MyAppWeb.AshTypescriptRpcChannel do
  use Phoenix.Channel

  def join("ash_typescript_rpc:" <> _id, _payload, socket), do: {:ok, socket}

  def handle_in("run", params, socket) do
    {:reply, {:ok, AshTypescript.Rpc.run_action(:my_app, socket, params)}, socket}
  end

  def handle_in("validate", params, socket) do
    {:reply, {:ok, AshTypescript.Rpc.validate_action(:my_app, socket, params)}, socket}
  end

  def handle_in(event, payload, socket) do
    {:reply, {:error, %{reason: "Unknown event: #{event}", payload: payload}}, socket}
  end
end
```

After:

```elixir
defmodule MyAppWeb.AshTypescriptRpcChannel do
  use Phoenix.Channel
  use AshRpc.Channel, profile: AshTypescript.RpcProfile

  def join("ash_typescript_rpc:" <> _id, _payload, socket), do: {:ok, socket}
end
```

`use AshRpc.Channel` injects the `"run"` and `"validate"` handlers plus the
catch-all, so don't add your own `handle_in/3` clauses next to it. If your
channel handles other events too, leave out the macro and call the helpers from
your own `handle_in/3`:

```elixir
def handle_in("run", params, socket),
  do: {:reply, {:ok, AshRpc.Channel.run(AshTypescript.RpcProfile, socket, params)}, socket}

def handle_in("validate", params, socket),
  do: {:reply, {:ok, AshRpc.Channel.validate(AshTypescript.RpcProfile, socket, params)}, socket}
```

The helpers also turn exceptions raised in the pipeline into wire errors instead
of crashing the channel.

## Field formatters are fixed at compile time

Before, `input_field_formatter`, `output_field_formatter` and the global
`not_found_error?` were read from the application environment on every request,
so changing them at runtime (for example with `Application.put_env/3` in a test)
took effect immediately.

After, they are read once, when your manifest module compiles. The manifest
tracks them with `Application.compile_env/3`, so editing them in `config/*.exs`
recompiles it automatically. Changing them at runtime, including in
`config/runtime.exs`, has no effect.

For tests that need a different formatter, build a re-decorated manifest and
pass it explicitly instead of calling `put_env`:

```elixir
manifest = AshRpc.Manifest.redecorate(AshTypescript.manifest(), output_formatter: :pascal_case)

AshRpc.run_action(AshTypescript.RpcProfile, conn, params, manifest: manifest)

# typed controllers / codegen
AshTypescript.with_manifest(manifest, fn -> ... end)
```

## Missing required inputs are reported as `required`

Before, a missing required attribute or argument came back as
`invalid_attribute` (message `"is required"`), especially from validation:

```json
{ "type": "invalid_attribute", "message": "is required", "fields": ["title"] }
```

After, both `run_action` and `validate_action` report the native Ash error type:

```json
{ "type": "required", "message": "attribute title is required", "fields": ["title"] }
```

Missing arguments read `"argument user_id is required"`. Values that fail to
cast to an action argument's type are reported as `invalid_argument`. If your
client switches on `error.type`, handle `"required"`.

## The `typed_query_action` wire parameter is removed

Before, a request could name a typed query with
`{"typed_query_action": "dashboard_todo", ...}` instead of `action`.

After, typed queries only run server-side, through
`AshTypescript.run_typed_query(name, params, conn)` (see above), which passes the query's
entrypoint directly. A wire request that carries only `typed_query_action` now
fails with `missing_required_parameter` for `action`. The generated TypeScript
client never sent this parameter, so only hand-written requests are affected.

## A `tenant` parameter now overrides the tenant on channels too

Before, HTTP requests honoured a `tenant` request parameter, but channel
requests ignored it and always used `socket.assigns[:ash_tenant]`.

After, a `tenant` parameter overrides the transport's tenant on both
transports: `Ash.PlugHelpers.get_tenant/1` on HTTP, `socket.assigns[:ash_tenant]`
on channels. The value is passed to Ash unvalidated. Invalid or unauthorized
tenants surface as normal Ash or policy errors. If your channel relies on the
socket tenant being the only possible tenant, enforce that in your resources'
policies or multitenancy configuration.

## Validation no longer depends on AshPhoenix; atomic validations on update/destroy only run during `run_action`

`validate_action` used to build an `AshPhoenix.Form`. It now builds the
action's query, changeset or action input natively, so error types match
`run_action` exactly (see "Missing required inputs" above). ash_typescript
depends on `phoenix` instead of `ash_phoenix`. If your app used AshPhoenix only
because ash_typescript pulled it in, add it to your own deps.

Two behaviour details:

- For update and destroy actions, the target record is loaded with the RPC
  action's `read_action` (the primary read action when unset), so records that
  action hides are reported as not found.
- Atomic validations on update and destroy actions only run when the action
  executes. `validate_action` can therefore succeed where `run_action` then
  fails, so always handle errors from the real call too.

## Domain `error_handler` now also applies to execution errors in `run_action`

Before, a domain's `typescript_rpc` `error_handler` and `show_raised_errors?`
were only applied to errors from `validate_action`. Errors raised while
executing the action in `run_action` skipped them.

After, execution errors carry the domain, resource, action and context, and
pass through the same domain `error_handler` and `show_raised_errors?`
setting. If your handler assumed it only ever saw validation errors, check that
it handles execution errors (for example `forbidden` or `not_found`) as well.

Policy breakdowns (`config :ash_typescript, policies: [show_policy_breakdowns?: true]`)
work as before.

## Other changes

- If you call internal runtime modules directly (pipeline, field processing,
  formatters, error builder), they moved from `AshTypescript.Rpc.*` to
  `AshRpc.*` (for example `AshRpc.Pipeline`, `AshRpc.RequestedFieldsProcessor`,
  `AshRpc.ErrorBuilder`), and `AshTypescript.ErrorFormatter` is now
  `AshRpc.ErrorFormatter`. They now take an explicit `AshRpc.Runtime`
  (`AshRpc.Runtime.new(AshTypescript.RpcProfile)`) instead of an OTP app name
  or global config.
  `AshTypescript.FieldFormatter` remains for codegen.
- `AshTypescript.Rpc.ValidationErrorSchemas` was removed.
