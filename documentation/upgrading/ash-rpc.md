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
typed channels) and the generated TypeScript are unchanged, except for custom
types, which are now declared on the manifest module (see
[Custom types are declared on the manifest](#custom-types-are-declared-on-the-manifest)).
The wire format is the same, except for the error-type, tenant and custom-type
changes described below.

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

After, `output_field_formatter` and `not_found_error?` are read once, when your
manifest module compiles (`input_field_formatter` is removed, see below). The manifest
tracks them with `Application.compile_env/3`, so editing them in `config/*.exs`
recompiles it automatically. Changing them at runtime, including in
`config/runtime.exs`, has no effect.

For tests that need a different formatter, build a re-decorated manifest and
pass it explicitly instead of calling `put_env`:

```elixir
manifest = AshTypescript.Manifest.redecorate(AshTypescript.manifest(), output_formatter: :pascal_case)

AshRpc.run_action(AshTypescript.RpcProfile, conn, params, manifest: manifest)

# typed controllers / codegen
AshTypescript.with_manifest(manifest, fn -> ... end)
```

## `input_field_formatter` is removed

Before, request keys were parsed back to internal names with
`input_field_formatter`, so a client could send `user_name` or `userName`
depending on that setting.

After, request keys (params, `input`, nested map keys, filter and sort names)
must be the client names the `output_field_formatter` produces, matched
exactly. A key in another casing is rejected with `unknown_input` (or
`unknown_field` for field selection). The `input_field_formatter` config key is
no longer read; remove it from `config/*.exs`. If you set it to something other
than your `output_field_formatter`, update your clients to send the generated
names.

## Typed controller request keys are client names

Before, a typed controller read its arguments from Phoenix's merged params and
accepted either the generated client name or a key parsed with
`input_field_formatter`, at the top level and in nested maps. Nested keys that
matched nothing were left for Ash to reject or ignore.

After, keys are resolved per source and matched exactly:

- Query and body keys must be the argument's generated client name (`userId`
  under `:camel_case`). Keys in another casing, and segment names sent outside
  the path (`?user_id=`), are dropped.
- Router path params resolve by their segment name (`:user_id`).
- An argument reached by more than one key or source is an `ambiguous_param`
  error.
- Nested keys must be the client names of the argument's type, as in RPC
  input. Any other key is an `unknown_input` error whose `path` starts with
  the argument's client name.
- Errors name the argument by its client name (`fields: ["userId"]`, not
  `["user_id"]`), and every error is reported in one 422.

Generated route helpers already send these names; only hand-written requests
need to change.

## Typed controllers and channels are listed on the manifest module

Before, typed controller and typed channel modules were listed in config. After,
they're options of `use AshTypescript.Manifest`, which is their only source:

```elixir
# Before (config/config.exs)
config :ash_typescript,
  typed_controllers: [MyAppWeb.Session],
  typed_channels: [MyAppWeb.OrgChannel]

# After (lib/my_app/ash_typescript_manifest.ex)
defmodule MyApp.AshTypescriptManifest do
  use AshTypescript.Manifest,
    otp_app: :my_app,
    typed_controllers: [MyAppWeb.Session],
    typed_channels: [MyAppWeb.OrgChannel]
end
```

`router`, `routes_output_file` and `typed_channels_output_file` stay in config.
The old keys are ignored, and compiling the manifest prints a warning while
either is still set. `AshTypescript.typed_controllers/0` and
`AshTypescript.typed_channels/0` are removed.

- Codegen generates nothing for a typed controller or channel that isn't
  listed, and warns about it (`warn_on_unlisted_typed_modules`). At runtime an
  unlisted typed controller answers every request with a 500, and an unlisted
  typed channel pushes payloads unformatted and logs a warning.
- The manifest depends on the listed modules at compile time, so they must not
  read the manifest at compile time. In an umbrella app, the manifest module
  must live in an app that compiles after them (usually the web app).
- Codegen takes its route and channel sets from the compiled manifest. Tests
  that set `:typed_controllers` / `:typed_channels` at runtime to change
  codegen output build a scoped manifest with those options instead and pass
  it with `AshTypescript.with_manifest/2`.
- If you call `AshTypescript.TypedChannel.PayloadFormatter` yourself (for
  example from your own `handle_out/3`), `format_payload/3` is now
  `format_payload(channel_module, resource, event, payload)` and
  `push_formatted/4` is now
  `push_formatted(socket, channel_module, resource, event, payload)`.

## Route results and channel payloads are plain data

Typed controller route `returns` and typed channel publication `returns` are
checked when the manifest module compiles, and a violation raises naming the
route or publication and the path to the offending type:

- Resources, embedded resources (including `:struct` with `instance_of` a
  resource) and unions are rejected at any depth, including inside NewTypes and
  custom types declared in `custom_types`. Before, routes were checked when the
  controller compiled, without seeing declared custom types, and publications
  weren't checked at all.
- A named type that contains itself is rejected (result and payload types are
  expanded inline).
- A typed channel publication must have a `returns`, and it must be a typed map:
  `:map`, `:struct`, `:keyword` or `:tuple` with `fields`, an `Ash.TypedStruct`,
  or a NewType of one. A missing `returns` (before: a warning and an `unknown`
  payload type), a scalar, an enum, an array, `:term`, a `:map` without `fields`
  or a custom type that isn't declared as a `map` is rejected. Fields inside a
  payload may still be untyped.

The handler or transform decides what a value holds, so a resource's loaded
fields, field policies and relationships can't be typed for the client. Declare a
typed map and build it from the record; the rule is on declared types:

```elixir
# Before
publish :update, [:id],
  event: "user_updated",
  returns: :struct,
  constraints: [instance_of: MyApp.User],
  transform: fn notification -> notification.data end

# After
publish :update, [:id],
  event: "user_updated",
  returns: :map,
  constraints: [fields: [email: [type: :string], name: [type: :string]]],
  transform: fn %{data: user} -> %{email: user.email, name: user.name} end
```

A scalar payload becomes a field of a map (`expr(title)` becomes
`expr(%{title: title})` in an `:auto` calculation, and the client reads
`payload.title`). For a union, use a typed map with a field per variant (all
`allow_nil?: true`). Routes still accept scalars, enums, arrays and untyped values
at the top level.

`config :ash_typescript, warn_on_missing_channel_returns:` is no longer read;
compiling the manifest warns while it is still set. `AshTypescript.warn_on_missing_channel_returns?/0`
is removed.

## Custom types are declared on the manifest

### `typescript_type_name/0` is now `typescript_type/0`

The callback that gives a scalar custom type its TypeScript type is renamed:

```elixir
# Before
def typescript_type_name, do: "`#${string}`"

# After
def typescript_type, do: "`#${string}`"
```

Compiling the manifest fails while a type module it reaches still exports
`typescript_type_name/0`, with "MyApp.HexColor exports `typescript_type_name/0`,
which is now `typescript_type/0`: rename it." A map-like type that still has
it and declares no fields reports the undeclared custom type error first (see
[Map-like custom types declare fields](#map-like-custom-types-declare-fields)).
The callback that names a declared custom type's alias, new in this release,
is `typescript_type_alias/0`.

### Config keys move to `custom_types`

`type_mapping_overrides`, `zod_mapping_overrides` and
`valibot_mapping_overrides` are no longer read. Compiling the manifest prints a
warning while one is still set, and its entries have no effect. Declare the
types in the manifest module's `custom_types` section instead:

```elixir
# Before (config/config.exs)
config :ash_typescript,
  type_mapping_overrides: [
    {SomeLib.ObjectId, "string"},
    {SomeLib.Color, "CustomTypes.Color"}
  ],
  zod_mapping_overrides: [{SomeLib.ObjectId, "CustomZodSchemas.objectId"}],
  valibot_mapping_overrides: [{SomeLib.ObjectId, "CustomValibotSchemas.objectId"}]

# After (lib/my_app/ash_typescript_manifest.ex)
defmodule MyApp.AshTypescriptManifest do
  use AshTypescript.Manifest, otp_app: :my_app

  custom_types do
    scalar SomeLib.ObjectId, :string do
      zod "CustomZodSchemas.objectId"
      valibot "CustomValibotSchemas.objectId"
    end

    scalar SomeLib.Color, :string do
      ts_type "CustomTypes.Color"
    end
  end
end
```

A string override whose TypeScript type follows from a base type
(`{Mod, "string"}`) becomes `scalar Mod, :string`. Anything else keeps
`ts_type "…"`. A type with `typescript_type/0` (`typescript_type_name/0` in
v0.19) that only had zod or valibot overrides gets a `scalar` with just `zod`
and `valibot`: without `ts_type`, the entry doesn't replace `typescript_type/0`. `zod_import_into_generated` and
`valibot_import_into_generated` stay in config. A scoped manifest
(`domains: [...]`) declares its own `custom_types`.

### Map-like custom types declare fields

A custom type whose values are maps or structs (`storage_type :map`, or
composite) now behaves like a typed map. Before, such a type named a
hand-written TypeScript type, was selected whole, and every key of its values
went out through the output formatter (unknown input keys were passed on).
Now:

- it declares its fields, and compiling the manifest fails for one that
  doesn't, with a message naming the ways to declare them;
- clients select its sub-fields (`{ colorPalette: ["primary"] }`). Selecting
  it bare is a TypeScript error and `requires_field_selection` on the server,
  and a generic action that returns one needs `fields`;
- its keys are the fields' client names. Undeclared keys never reach the
  client, and in requests they are `unknown_input`;
- its TypeScript type, input type and zod/valibot schemas are generated from
  the fields. It can't declare a TypeScript type: `typescript_type/0` on
  it, or a `scalar` entry for it, fails compilation with a migration message.

For a v0.19 map-storage type with `typescript_type_name/0`:

```elixir
# Before
defmodule MyApp.ColorPalette do
  use Ash.Type
  def storage_type(_), do: :map
  # cast_input/2, ...
  def typescript_type_name, do: "CustomTypes.ColorPalette"
end

# After
defmodule MyApp.ColorPalette do
  use Ash.Type
  def storage_type(_), do: :map
  # cast_input/2, ...

  def typescript_fields do
    [
      primary: [type: :string, allow_nil?: false],
      secondary: [type: :string, allow_nil?: false],
      accent: [type: :string]
    ]
  end
end
```

```typescript
// Before
const todo = await getTodo({ input: { id }, fields: ["id", "colorPalette"] });

// After
const todo = await getTodo({
  input: { id },
  fields: ["id", { colorPalette: ["primary", "secondary", "accent"] }],
});
```

The hand-written `CustomTypes.ColorPalette` imported through
`import_into_generated` is no longer referenced. Delete it, or keep it for your
own code. For a type you don't own, declare a `map` entry instead of
`typescript_fields/0`:

```elixir
custom_types do
  map SomeLib.ColorPalette do
    field :primary, :string, allow_nil?: false
    field :secondary, :string, allow_nil?: false
    field :accent, :string
  end
end
```

A composite type's `composite_types/1` entries are its fields, with nothing to
add. Fields are per module (`composite_types/1` is read with the type's
default constraints), and a NewType over a custom type inherits the subtype's
fields. See [Custom Types](../advanced/custom-types.md#map-like-custom-types).

For more precise member types than the generated ones, use scalar custom
types with their own TypeScript mapping as field types:

```elixir
defmodule MyApp.HexColor do
  use Ash.Type.NewType, subtype_of: :string, constraints: [match: ~r/^#[0-9a-fA-F]{6}$/]
  def typescript_type, do: "`#${string}`"
end

defmodule MyApp.ColorPalette do
  use Ash.Type
  # storage_type :map, cast_input/2, …
  def typescript_fields do
    [
      primary: [type: MyApp.HexColor, allow_nil?: false],
      secondary: [type: MyApp.HexColor, allow_nil?: false],
      accent: [type: MyApp.HexColor]
    ]
  end

  def typescript_type_alias, do: "ColorPalette"
end
```

For a type you don't own, the same comes from the manifest:

```elixir
custom_types do
  scalar SomeLib.HexColor, :string do
    constraints match: ~r/^#[0-9a-fA-F]{6}$/
    ts_type "`#${string}`"
  end

  map SomeLib.ColorPalette do
    ts_alias "ColorPalette"
    field :primary, SomeLib.HexColor, allow_nil?: false
    field :secondary, SomeLib.HexColor, allow_nil?: false
    field :accent, SomeLib.HexColor
  end
end
```

Either form generates
``{primary: `#${string}`, secondary: `#${string}`, accent: `#${string}` | null, __type: "TypedMap", …}``
for results, the aliases `ColorPalette` and
``ColorPaletteInput = {primary: `#${string}`, secondary: `#${string}`, accent?: `#${string}` | null}``
for inputs, and zod/valibot string schemas with the regex. These are
client-side only: on the server the value is cast by `ColorPalette`'s own
`cast_input/2`, which enforces the regex only if it casts each entry through
`MyApp.HexColor` (the [Custom Types](../advanced/custom-types.md#precise-member-types)
guide shows one).

### Money, ULID and Ltree

These are built-in declarations now:

- `AshMoney.Types.Money` is a map of `currency` and `amount`. Select
  `{ price: ["currency", "amount"] }` instead of `"price"`. Responses no longer
  contain `format_options`. The generated `Money` alias stays, now generated
  from its fields like every declared custom type's alias (see below):
  `{currency: string, amount: Decimal}`, was `{ amount: string; currency: string }`.
  `Decimal` is `string`, so values stay assignable both ways.
- The `ULID`, `AshPostgresLtreeArray` and `AshPostgresLtreeFlexible` aliases
  stay, each now exported only when a field uses it (both Ltree aliases were
  exported whenever Ltree was used). Their zod/valibot schemas are unchanged.
- A `custom_types` entry for one of these modules replaces the built-in.

### Declared custom types are exported

Every map-like custom type with declared fields is exported from the types
file as an alias, plus `<Name>Input` when its input shape differs (nullable
fields optional). The alias is the `map` entry's `ts_alias`, else the type's
`typescript_type_alias/0`, else the module name joined (`MyApp.ColorPalette`
becomes `MyAppColorPalette`); the built-in Money keeps `Money`. Inputs,
typed controller route results, typed channel payloads, filter values,
identity and `getBy` values and action metadata reference it; result types
keep the field-selection form. The zod and valibot schemas get one named
schema per type, the alias plus the schema suffix (`MoneyZodSchema`),
referenced at each use. See
[Naming the Type](../advanced/custom-types.md#naming-the-type) and
[Generated TypeScript](../advanced/custom-types.md#generated-typescript).

- Hand-written aliases for these types can be replaced by imports of the
  generated ones. A `Money` (or other alias) of your own that your code
  imports next to the generated names needs one of them renamed: set
  `ts_alias "…"` on a `map` entry, or `typescript_type_alias/0` on a type
  without one.
- An alias that collides with a generated name is a warning when the manifest
  compiles (an error under `--warnings-as-errors`) and fails codegen, naming
  both (see
  [Name Collisions](../advanced/custom-types.md#name-collisions)).
- Filter operator values, identity and `getBy` values and action metadata of
  typed maps no longer carry `__type` / `__primitiveFields`: they are plain
  objects, so a filter like `{ price: { eq: { currency: "NOK", amount: "1" } } }`
  type-checks. Code that read those keys from a metadata type no longer
  compiles. Union filter values are unchanged.

### Typed maps and structs send declared fields only

Typed controller route results, typed channel payloads and action metadata
send only the declared fields of each typed map and struct, under their
client names. A route or channel that returned extra keys in a typed map or
struct loses them (its generated TypeScript type never had them). Struct
values (an `Ash.TypedStruct`, `%Money{}`) no longer crash formatting.

### Out-of-tree schema formatters

If you implement `AshTypescript.Codegen.SchemaFormatter` yourself, it drops
`mapping_overrides/0`, `third_party_types/0`, `ltree_array/0` and
`ltree_union/0`, and gains `library/0` (`:zod` or `:valibot`) and
`wrap_lazy/1` (a deferred reference: `z.lazy(() => schema)`,
`v.lazy(() => schema)`). The two in-tree formatters are updated.

## Unknown metadata fields, sort and filter names are errors

- A `metadataFields` entry that isn't the client name of a metadata field the
  RPC action exposes is now an `unknown_metadata_fields` error (one error,
  with the misses in `fields` and the allowed names in
  `details.allowedFields`). Before, such entries were dropped silently.
- A sort or filter field name that isn't a client name of the resource is now
  `unknown_field`, and an unknown filter operator is
  `unknown_filter_operator`. Before, both came back as `unknown_error`.
- Embedded resources that don't use the `AshTypescript.Resource` extension now
  have client names too, from the `output_field_formatter`. Their nested input
  keys must be those names, and any other key is `unknown_input`. Before,
  their keys were passed through as sent.

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
