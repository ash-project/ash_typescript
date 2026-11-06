<!--
SPDX-FileCopyrightText: 2026 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Upgrading to v0.20

v0.20 moves the server-side RPC runtime (request parsing, field selection,
execution, result formatting and errors) into the `ash_rpc` package, which
ash_typescript depends on, so you don't add it yourself. The runtime functions
your app calls now live under `AshRpc.*`, and ash_typescript's
`AshTypescript.RpcProfile` connects them to your manifest: pass it wherever the
old API took your OTP app name.

The release also moves the remaining configuration onto the manifest module,
makes request keys exact client names, and types map-like custom types from
their declared fields. This guide lists what to change, and links each change
to the page that documents the current behaviour where there is one.

## Checklist

1. Replace the RPC controller and channel handlers, and rename calls to
   `AshTypescript.Rpc.*` ([Server endpoints](#server-endpoints)).
2. Remove `input_field_formatter` and `warn_on_missing_channel_returns`, move
   `typed_controllers`, `typed_channels` and the `*_mapping_overrides` keys
   from config onto the manifest module, and move a resource's
   `typescript_field_names/0` to `field_names` ([Configuration](#configuration)).
3. Fix what the manifest now rejects when it compiles: untyped structs,
   invalid generated names (client names, function and schema names, type
   aliases), metadata names that collide with fields, load restrictions
   with entries under leaf fields ([Compile-time checks](#compile-time-checks)).
4. Check hand-written clients, error handling and error handlers: request keys,
   `required` errors, `unknown_*` errors, the `tenant` param, untyped data,
   `typed_query_action`, validation without AshPhoenix
   ([Requests and errors](#requests-and-errors)).
5. Check client code that reads `nextPage` after a page with only `limit`,
   and `beforeChannelPush` hooks that return a new config
   ([Generated client](#generated-client)).
6. Fix typed controller request keys, route arguments and publication
   `returns` that aren't plain data, structured route arguments sent in the
   URL, and reserved route, action and typed query names
   ([Typed controllers](#typed-controllers), [Typed channels](#typed-channels)).
7. Rename `typescript_type_name/0`, remove `typescript_type/0` from NewTypes
   with fields or over a union, declare the fields of map-like custom types,
   update client field selections and filter values, and check the Money,
   ULID, Ltree and AshUUID changes ([Custom types](#custom-types)).
8. If you call internal modules or implement a schema formatter, see
   [For library and extension authors](#for-library-and-extension-authors).

## Server endpoints

### RPC controller

```elixir
# Before
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

# After
defmodule MyAppWeb.AshTypescriptRpcController do
  use MyAppWeb, :controller

  def run(conn, _params), do: AshRpc.Plug.run(conn, AshTypescript.RpcProfile)

  def validate(conn, _params), do: AshRpc.Plug.validate(conn, AshTypescript.RpcProfile)
end
```

`AshRpc.Plug.run/2` and `AshRpc.Plug.validate/2` send the JSON response
themselves, always with status 200. New installs get this controller from
`mix igniter.install ash_typescript`. See
[Create RPC Controller](../getting-started/installation.md#3-create-rpc-controller).

### Phoenix channel

```elixir
# Before
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

# After
defmodule MyAppWeb.AshTypescriptRpcChannel do
  use Phoenix.Channel
  use AshRpc.Channel, profile: AshTypescript.RpcProfile

  def join("ash_typescript_rpc:" <> _id, _payload, socket), do: {:ok, socket}
end
```

`use AshRpc.Channel` injects the `"run"`, `"validate"` and catch-all clauses,
so remove your own `handle_in/3` clauses. A channel that handles other events
too skips the macro and calls `AshRpc.Channel.run/3` and
`AshRpc.Channel.validate/3` from its own clauses. See
[Backend Channel Setup](../features/phoenix-channels.md#backend-channel-setup).

### Calling run and validate from Elixir

| Before | After |
|--------|-------|
| `AshTypescript.Rpc.run_action(:my_app, conn, params)` | `AshRpc.run_action(AshTypescript.RpcProfile, conn, params)` |
| `AshTypescript.Rpc.validate_action(:my_app, conn, params)` | `AshRpc.validate_action(AshTypescript.RpcProfile, conn, params)` |

Both return the same client-formatted maps as before. The second argument can
also be a socket or an `%AshRpc.Context{}` (for LiveViews and background jobs).
An exception raised while handling a request no longer propagates to the
caller: it is logged and returned as an `unknown_error` failure response. See
[Calling the Runtime from Elixir](../getting-started/installation.md#calling-the-runtime-from-elixir).

### Typed queries

```elixir
# Before
AshTypescript.Rpc.run_typed_query(:my_app, :dashboard_todo, %{}, conn)
AshTypescript.Rpc.run_typed_query(:my_app, :todo_detail, %{input: %{id: id}}, conn)

# After
AshTypescript.run_typed_query(:dashboard_todo, %{}, conn)
AshTypescript.run_typed_query(:todo_detail, %{input: %{id: id}}, conn)
```

The OTP app argument is gone, and `params` is required (pass `%{}` when there
are none). The return value is unchanged. See
[Typed Queries](../guides/typed-queries.md#step-2-use-in-your-phoenix-controller).

### Error protocol and error handlers

| Before | After |
|--------|-------|
| `defimpl AshTypescript.Rpc.Error, for: ...` | `defimpl AshRpc.Error, for: ...` |
| `@behaviour AshTypescript.Rpc.ErrorHandler` | `@behaviour AshRpc.ErrorHandler` |
| `AshTypescript.Rpc.DefaultErrorHandler` | `AshRpc.DefaultErrorHandler` |

The callbacks and the maps they return are unchanged, and `error_handler` is
still set in the domain's `typescript_rpc` section. See
[Custom Error Protocol](../guides/error-handling.md#custom-error-protocol) and
[Custom Error Handlers](../guides/error-handling.md#custom-error-handlers).

## Configuration

### Field formatters are fixed at compile time

`output_field_formatter` and the global `not_found_error?` are read when the
manifest module compiles. Editing them in `config/*.exs` recompiles the
manifest, but changing them at runtime (`Application.put_env/3`,
`config/runtime.exs`) has no effect. Tests that changed the formatter with
`put_env` re-decorate the manifest and pass it explicitly instead: see
[Testing with another formatter](../advanced/field-name-mapping.md#testing-with-another-formatter).

### `input_field_formatter` is removed

Request keys are no longer parsed back with `input_field_formatter`. Remove the
key from `config/*.exs` (compiling the manifest warns while it is set). If it
differed from your `output_field_formatter`, hand-written clients must now send
the generated names (see
[Request keys are exact client names](#request-keys-are-exact-client-names)).

### Typed controllers and channels move to the manifest module

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
The old keys are ignored, and compiling the manifest warns while either is set.
The functions `AshTypescript.typed_controllers()` and
`AshTypescript.typed_channels()` are removed.

- The manifest depends on the listed modules at compile time, so they must not
  read the manifest at compile time. In an umbrella app, move the manifest
  module to an app that compiles after them (usually the web app).
- A module you don't list gets no generated code, a codegen warning, and fails
  at runtime (a typed controller answers 500, a typed channel pushes
  unformatted payloads).
- Tests that set `:typed_controllers` / `:typed_channels` at runtime to change
  codegen output build a scoped manifest with those options instead and run
  codegen under `AshTypescript.with_manifest(manifest, fun)`.

See [Typed controllers and typed channels](../reference/configuration.md#typed-controllers-and-typed-channels).

### Mapping overrides move to `custom_types`

`type_mapping_overrides`, `zod_mapping_overrides` and
`valibot_mapping_overrides` are no longer read; compiling the manifest warns
while one is set. Declare the types in the manifest module's `custom_types`
section:

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

- An override whose TypeScript type follows from a base type
  (`{Mod, "string"}`) becomes `scalar Mod, :string`; any other keeps
  `ts_type "…"`.
- A type with `typescript_type/0` that only had zod or valibot overrides gets a
  `scalar` entry with just `zod` and `valibot`. Without `ts_type`, the entry
  doesn't replace `typescript_type/0`.
- An override for a map-like type becomes a `map` entry with fields (see
  [Map-like custom types declare fields](#map-like-custom-types-declare-fields)).
- `zod_import_into_generated` and `valibot_import_into_generated` stay in
  config. A scoped manifest (`domains: [...]`) declares its own `custom_types`.

See [Scalar Custom Types](../advanced/custom-types.md#scalar-custom-types).

### `warn_on_missing_channel_returns` is removed

A publication without `returns` is now a compile error (see
[Publications need a typed-map `returns`](#publications-need-a-typed-map-returns)),
so the setting is no longer read. Remove it from config; compiling the manifest
warns while it is set. `AshTypescript.warn_on_missing_channel_returns?()` is
removed.

### `typescript_field_names/0` on a resource is ignored

Codegen applied a `typescript_field_names/0` function defined on a resource,
which the runtime ignored. Codegen ignores it now too, so generated names are
the ones the server accepts. Move the mappings to `field_names` in the
resource's `typescript` section; `typescript_field_names/0` still applies to
types (NewTypes and typed structs). See
[Resource Field Mapping](../advanced/field-name-mapping.md#resource-field-mapping).

## Compile-time checks

### Untyped structs are rejected

Compiling the manifest fails when an RPC action or typed query accepts or
returns an untyped struct anywhere it can reach: arguments, accepted
attributes, the return, the records of its resource and of exposed resources
reached through relationships, embedded resources, union members, named types
and exposed metadata. Typed controller route arguments and `returns`, and
publication `returns`, are checked the same way. The error names the
entrypoint, route or publication, the struct and the path.

An untyped struct is a `:struct` without `fields`: `instance_of` a plain
struct, `instance_of` an Ash type such as an `Ash.TypedStruct`, or no
constraints (and `fields: []` unless `instance_of` is an Ash type). A
composite custom type's `composite_types/1` entries are checked too, and
`typed_struct_fields/0` is no longer read. Use instead:

- the `Ash.TypedStruct` itself as the type, not through `instance_of`;
- a NewType over `:struct` with `fields` constraints;
- `instance_of` an Ash resource;
- or an unconstrained `:map` that you build in the action.

See [Untyped Map Type Configuration](../advanced/custom-types.md#untyped-map-type-configuration).

### Generated names are checked when the manifest compiles

Compiling the manifest now checks every name the generated code uses: client
names (the keys of generated objects), the function, const, type and schema
names generated for RPC actions, typed queries and typed controller routes, and
type aliases. Every problem is reported at once, in one error that replaces the
old per-check messages ("Invalid field names found …", "Invalid metadata field
names found …", "Invalid names found that contain question marks …", "Invalid
names for TypeScript generation found."). The verifier
modules behind those messages are removed:
`AshTypescript.Resource.Verifiers.VerifyFieldNames`,
`AshTypescript.Resource.Verifiers.VerifyMapFieldNames`,
`AshTypescript.Manifest.Verifiers.VerifyActionTypes` and
`AshTypescript.Manifest.Verifiers.VerifyMetadataFieldNames`. Each line names
the owner and the fix:

```
Invalid generated names found.

Client names (keys of generated objects) must be TypeScript identifiers
([A-Za-z_$][A-Za-z0-9_$]*). A name the formatter makes from a raw name with an underscore
before a digit (line_1) is rejected too, since its client name (line1) doesn't tell line_1
from line1.

  Resource MyApp.Task:
    - field :address_line_1 → "addressLine1" (formatted), underscore before a digit: add it to field_names in the resource's typescript block, e.g. address_line_1: "addressLine1"
    - field :is_active? → "isActive?" (formatted), not an identifier: add it to field_names in the resource's typescript block, e.g. is_active?: "isActive"

Function, const, type and schema names must be TypeScript identifiers that aren't
JavaScript reserved words, and a type name can't be a predefined TypeScript type name
(string, any, …).

  RPC action :delete in MyApp.Domain:
    - function "delete", a JavaScript reserved word: rename the rpc_action, for example :delete_item

Type aliases:

  MyApp.Types.GeoPoint:
    - The ts_alias "Geo-Point" of MyApp.Types.GeoPoint is not a TypeScript identifier.
```

Update anything that matches the old messages. What changes:

- **Earlier and harder.** These were a compile warning (an error under
  `--warnings-as-errors`) and a codegen error, and now fail the manifest
  compile: formatter-made client names with a `?` or an underscore before a
  digit, and invalid `field_names`, `argument_names`, `metadata_field_names`
  and `typescript_field_names/0` values; `rpc_action` and `typed_query` names;
  typed controller route names, arguments and `returns` fields.
- **Newly reported**, since no check covered them:
  - client names that aren't TypeScript identifiers, wherever they sit (a
    resource field or action argument named `:"due-at"` was emitted as is);
  - calculation arguments, and union members in action arguments and
    results, by both rules;
  - the metadata fields of an `rpc_action` without `show_metadata`, which
    exposes them all (before, only a `show_metadata` list was checked);
  - function, const, type and schema names that aren't identifiers: an
    `rpc_action :"list-todos"`, a `ts_fields_const_name`, `ts_result_type_name`,
    `zod_schema_name` or `valibot_schema_name` that isn't one, and every name
    derived from an RPC action, typed query or route (validation and channel
    functions, input types, schemas), whatever the feature flags;
  - JavaScript reserved words in every generated function, const, type and
    schema name, the names you set included (`ts_fields_const_name "default"`,
    `zod_schema_name "class"`), and predefined TypeScript type names (`string`,
    `any`, `never`, …) in type names (`ts_result_type_name "string"`);
  - typed channel events that aren't identifiers (`event: "post-created"`),
    and their `<Event>Payload` type names: the event is a key of the generated
    `<Channel>Events` type;
  - under a custom (MFA) `output_field_formatter`, the generated code's own
    keys (`hasMore`, `results`, `fetchOptions`, …) when the formatter doesn't
    make identifiers of them. The built-in formatters always do.
- **Generated differently:** with `typed_controller_path_params_style: :args`,
  a path parameter whose client name is a JavaScript reserved word is bound as
  the name plus `Param` (`showItemPath(newParam: string)` for `/items/:new`).
  Before, the generated function didn't compile. Positional parameter names
  aren't part of the API, so callers don't change.
- **Newly allowed:** `field_names` maps a field whose raw name isn't a
  TypeScript identifier (`field_names "attr-dash": "attrDash"`), not only names
  with a `?` or an underscore before a digit. The report suggests it:
  `- field :"due-at" → "due-at" (formatted), not an identifier: add it to
  field_names in the resource's typescript block, e.g. "due-at": "dueAt"`.
- **No longer reported:**
  - a name you set that has an underscore before a digit
    (`argument_names [act: [line_1: "line_1"]]`, `metadata_field_names
    [field_1: "field_1"]`): it is a valid identifier, used as written;
  - names in anything the manifest never reaches, since nothing is generated
    for them: fields of resources in no `typescript_rpc` block and typed
    controllers not listed in `typed_controllers:`. The "not listed" warnings
    still point at unlisted resources and controllers.

The `field_names` checks that run when the resource compiles ("Invalid
field_names configuration found": a key that isn't a field or doesn't need a
mapping, a value that isn't a string) are unchanged, except that a key that
isn't an identifier now needs a mapping (see "Newly allowed").

See [Troubleshooting](../reference/troubleshooting.md#error-invalid-generated-names-found),
[Declaring Fields in the Manifest](../advanced/custom-types.md#declaring-fields-in-the-manifest)
and [Field Name Mapping](../advanced/field-name-mapping.md).

### Metadata name collisions are reported by ash_rpc

A read action's metadata field whose client name equals a public field's now
fails with "Client name collision in metadata of entrypoint"
(`AshRpc.Manifest.NameCollisionError`) instead of "Metadata field conflicts
with resource field". Update anything that matches the old message. Metadata of
create, update and destroy actions is returned under its own `metadata` key
and is no longer checked. Two inputs of an action with the same client name
fail the same way ("Client name collision in action :create on MyApp.Todo:
…") instead of with "Duplicate input field names found in RPC
configuration.". See [Troubleshooting](../reference/troubleshooting.md).

### Load restrictions are checked under every field

An `allowed_loads` / `denied_loads` entry with entries under an aggregate or
a calculation that holds no resource, embedded resource or union
(`denied_loads: [comment_count: [:x]]`) now fails manifest compilation with
"contains invalid load paths"; before, the nested entries were ignored. Remove
them. Entries under a union name its members
(`denied_loads: [content: [text: [:display_text]]]`), and entries under an
aggregate that returns an embedded resource are checked against that
resource. A restricted union is typed in the union's own shape, with only the
restricted members replaced; code that named the old `__members` shape of a
restricted schema reads the union's members directly. See
[RPC Action Options](../features/rpc-action-options.md).

## Requests and errors

The generated clients already send the requests below. Hand-written requests,
code that switches on `error.type` and actions that return untyped data may
need changes.

### Request keys are exact client names

Every request key must be the client name the `output_field_formatter`
produces, matched exactly: params, `input` and nested map keys, field, sort and
filter names, and the top-level keys `action`, `input` and `identity` and the
filter connectives `and`, `or` and `not`. A key in another casing is
`unknown_input` (or `unknown_field` for field, sort and filter names).

Under `:camel_case` and `:snake_case` the top-level keys read the same as
before. Under `:pascal_case` or a custom formatter, the generated clients now
send `{ Action: "create_todo", Input: {...} }`, and hand-written clients must do
the same. See
[Automatic Field Formatting](../advanced/field-name-mapping.md#automatic-field-formatting).

Embedded resources that don't use the `AshTypescript.Resource` extension now
have client names too, from the `output_field_formatter`. Their nested input
keys must be those names; before, they were passed through as sent. See
[Client Names](../advanced/embedded-resources.md#client-names).

### Missing required inputs are `required`

A missing required attribute or argument was `invalid_attribute` with the
message `"is required"`. Both `run_action` and `validate_action` now report
`required`. Before:

```json
{ "type": "invalid_attribute", "message": "is required", "fields": ["title"] }
```

After:

```json
{ "type": "required", "message": "attribute %{field} is required", "vars": { "field": "title" }, "fields": ["title"] }
```

Missing arguments read `"argument %{field} is required"`. A value that fails to
cast to an argument's type is `invalid_argument`. If your client switches on
`error.type`, handle `"required"`. See
[Validation Functions](../guides/form-validation.md#validation-functions).

### Unknown metadata fields, sort and filter names are errors

| Request | Before | After |
|---------|--------|-------|
| A `metadataFields` entry the action doesn't expose | dropped silently | `unknown_metadata_fields` |
| A sort or filter field name that isn't a client name | `unknown_error` | `unknown_field` |
| An unknown filter operator | `unknown_error` | `unknown_filter_operator` |

See [Common Error Types](../guides/error-handling.md#common-error-types).

### Identity keys, `unknown_field` messages and hints

- An `identity` must hold exactly one identity's keys: an extra key next to a
  valid identity's keys is `invalid_identity`.
- `unknown_field`'s message is `Unknown field %{field}`, without the resource,
  and `vars.resource` is gone.
- Errors a generated client never produces (`invalid_input_format`,
  `duplicate_field`, `empty_fields_array`, `invalid_pagination`, ...) no longer
  carry `details.hint`. Errors a stale generated client can cause (unknown
  fields, inputs or actions) keep it.

### Untyped data is sent as the action produced it

A value of an unconstrained `:map`, `{:array, :map}` or `:term` (a return,
attribute, typed-map field or union member) is sent exactly as the action
produced it and encoded by Jason. Nothing converts it any more:

- keyword lists, tuples, `Duration`s, resource structs, `Ash.TypedStruct`s and
  other structs inside it are no longer turned into maps or strings;
- a `ForbiddenField` or `NotLoaded` inside it is no longer turned into `null`
  (a forbidden or unloaded untyped attribute as a whole is still redacted or
  skipped);
- an `Ash.Union` encodes as its value instead of `{member: value}`.

A value Jason can't encode raises when the response is encoded: the RPC
controller answers 500, and an RPC channel crashes. The error message inspects
the value, so private attributes not marked `sensitive?: true` show up in
server logs. Callers of `AshRpc.run_action/4` that encode the result
themselves get the raw structs. Convert the data in the action, or declare its
type (the resource, an `Ash.TypedStruct`, a typed map). See
[Untyped Map Type Configuration](../advanced/custom-types.md#untyped-map-type-configuration).

### The `typed_query_action` parameter is removed

A wire request could name a typed query with `typed_query_action` instead of
`action`. Typed queries now run only server-side, through
`AshTypescript.run_typed_query(name, params, conn)`. A request that carries only
`typed_query_action` fails with `missing_required_parameter` for `action`. The
generated client never sent it.

### A `tenant` parameter overrides the channel's tenant

Channel requests ignored a `tenant` parameter and always used
`socket.assigns[:ash_tenant]`. A `tenant` parameter now overrides the
transport's tenant on channels as it does on HTTP. If your channel relies on
the socket's tenant being the only one a client can use, enforce that in your
resources' policies or multitenancy configuration. See
[Channel-based RPC](../features/multitenancy.md#channel-based-rpc).

### The domain error handler sees execution errors

A domain's `error_handler` and `show_raised_errors?` were only applied to
validation errors; errors raised while executing the action in `run_action`
skipped them. They now apply to the Ash errors and exceptions of both, so a
handler may see types it never saw before (`forbidden`, `not_found`, ...).
Check that your handler handles them. See
[Custom Error Handlers](../guides/error-handling.md#custom-error-handlers).

### Validation no longer uses AshPhoenix

`validate_action` builds the action's query, changeset or action input with Ash
directly, so its error types match `run_action`. ash_typescript depends on
`phoenix` instead of `ash_phoenix`: if your app used AshPhoenix only because
ash_typescript pulled it in (for example for
`AshPhoenix.Plug.CheckCodegenStatus`), add `ash_phoenix` to your own deps.

- Update and destroy actions load their record with the RPC action's
  `read_action`, so records that action hides are `not_found`.
- Atomic validations on update and destroy actions only run when the action
  executes, so a validation can pass where the real call then fails. Handle
  errors from the real call too.

See [Validation Functions](../guides/form-validation.md#validation-functions).

## Generated client

### A page with only `limit` follows `default_page_type`

On a read action that supports both offset and keyset pagination, a page with
only `limit` (`page: { limit: 20 }`) was always typed as a keyset page, while
Ash returns an offset page unless `config :ash, default_page_type: :keyset` is
set. Codegen now reads `default_page_type` when it runs (`:offset` when unset)
and types such a page accordingly. Actions with one pagination mode are
unaffected.

- If your app doesn't set `default_page_type`, code that reads `nextPage` or
  `previousPage` after a `{ limit }` page no longer type-checks: it was
  reading fields the server never sent. Read the offset page's fields, pass
  `after` / `before` to page by keyset, or set
  `config :ash, default_page_type: :keyset`.
- Set `default_page_type` in `config/config.exs`, not only in
  `config/runtime.exs`, so codegen and the server agree.

See [Keyset (Cursor-based) Pagination](../guides/querying-data.md#keyset-cursor-based-pagination).

### `beforeChannelPush` sets the push timeout and handlers

The config a `beforeChannelPush` hook returns used to reach only
`afterChannelResponse`. The generated channel functions now push with its
`timeout` and send the response to its `resultHandler`, `errorHandler` and
`timeoutHandler`. The payload is still built from the caller's config.

A hook that returns a config without the caller's handlers now drops them.
Return `{ ...config, … }`:

```typescript
export async function beforeChannelPush(
  actionName: string,
  config: ActionChannelConfig
): Promise<ActionChannelConfig> {
  return { ...config, timeout: config.timeout ?? 10000 };
}
```

See [What beforeChannelPush Can Change](../features/lifecycle-hooks.md#what-beforechannelpush-can-change).

## Typed controllers

### Request keys

A typed controller accepted an argument under its generated client name or a
key parsed with `input_field_formatter`, and left unknown nested keys to Ash.
Keys are now resolved per source and matched exactly:

- query and body keys must be the argument's generated client name (`userId`
  under `:camel_case`); other spellings are dropped;
- router path params resolve by their segment name (`:user_id`);
- an argument reached by more than one key or source is `ambiguous_param`;
- nested keys must be the client names of the argument's type, and any other
  key is `unknown_input`;
- errors name the argument by its client name (`fields: ["userId"]`), and all
  of them come back in one 422.

Generated route helpers already send these names. See
[Request Handling](../guides/typed-controllers.md#request-handling).

### Arguments and results are plain data

Route arguments and `returns` are checked when the manifest module compiles.
Resources, embedded resources (including `:struct` with `instance_of` a
resource), unions and types that contain themselves are rejected at any depth,
including inside NewTypes and declared custom types. Before, an argument could
be an embedded resource, a union or another resource. Declare the fields the
client sends as a typed map or an `Ash.TypedStruct`, and take resource input
through an RPC action:

```elixir
# Before
post :create_task do
  argument :metadata, MyApp.TaskMetadata, allow_nil?: false
end

# After
post :create_task do
  argument :metadata, :map,
    allow_nil?: false,
    constraints: [fields: [notes: [type: :string], priority: [type: :integer]]]
end
```

The generated input type and schemas then inline the map instead of
referencing `TaskMetadataInputSchema` / `TaskMetadataZodSchema`. See
[Compile-Time Validation](../guides/typed-controllers.md#compile-time-validation).

### Results send declared fields only

Each typed map and struct in a route result is sent with its declared fields
only, under their client names. A handler that returned extra keys in a typed
map loses them (its generated TypeScript type never had them). See
[Response Types](../guides/typed-controllers.md#response-types).

### Reserved function names are rejected

A route whose function name is a JavaScript reserved word (`:delete`, `:new`,
`:import`, `:default`, …) fails the manifest compile, whatever its method, with
"Invalid generated names found." and the line `- function "delete", a JavaScript
reserved word: rename the route, for example :delete_item` (see
[Generated names are checked when the manifest compiles](#generated-names-are-checked-when-the-manifest-compiles)).
Before, a route with a fetch function generated code TypeScript rejects, and a
path-only route generated `deletePath`. Rename it (`delete :delete_item`); the
client then calls `deleteItem` / `deleteItemPath`. Names that only contain a
reserved word (`:import_users`) are unaffected.

The same applies to an `rpc_action` (see
[RPC Action Options](../features/rpc-action-options.md)) and to a
`typed_query` whose fields const would be a reserved word: rename it or set
another `ts_fields_const_name` (see
[Typed Queries](../guides/typed-queries.md#configuration-options)). A
`ts_fields_const_name`, `ts_result_type_name`, `zod_schema_name` or
`valibot_schema_name` you set can't be a reserved word either, and a
`ts_result_type_name` can't be a predefined TypeScript type name: the line names
the option (`- zod schema "class" (zod_schema_name), a JavaScript reserved word:
change zod_schema_name`).

### Structured arguments can't go in the URL

Codegen fails for a route that would send a map, struct, union or resource
argument in its URL: a path parameter, or any argument of a GET route, which
goes in the query string. The generated helper would have written it as
`[object Object]`. Arrays of scalars stay allowed in the query string. Use a
scalar type, or make the route a POST, PATCH, PUT or DELETE so the argument
goes in the JSON body.

### A types file for routes-only projects

A project with typed controllers or typed channels and no `output_file` now
gets the shared types file (`types_output_file`, by default
`assets/js/ash_types.ts`) when the routes or channels file uses a shared name.
Before, those files re-exported a types file that was never generated. See
[Multi-File Output](../reference/configuration.md#multi-file-output).

Its Zod and Valibot files no longer contain resource schemas, nor the named
schemas of custom types that contain a resource: nothing in such a project
uses them, and some of them didn't compile. Set `output_file` if you import
them directly.

## Typed channels

### Publications need a typed-map `returns`

Every publication a typed channel declares needs a `returns` that is a typed
map, checked when the manifest module compiles. Before, a missing `returns`
was a warning and an `unknown` payload type, and only payload types that
aren't JSON objects (a scalar, an array) were rejected, when the channel
compiled. Now these are rejected when the manifest module compiles: no
`returns`, a scalar, an enum, an array, `:term`, a `:map` without `fields`, a
custom type not declared as a `map`, and a resource, embedded resource, union
or self-containing type at any depth.
Declare a typed map and build it from the record:

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

A scalar payload becomes a field of a map: `expr(title)` becomes
`expr(%{title: title})` in an `:auto` calculation, and the client reads
`payload.title`. For a union, use a typed map with a field per variant (all
`allow_nil?: true`). See
[Payload Type Resolution](../guides/typed-channels.md#payload-type-resolution).

### Payloads send declared fields only

Each typed map and struct in a payload is sent with its declared fields only,
under their client names; extra keys are dropped. See
[Payload Formatting](../guides/typed-channels.md#payload-formatting).

## Custom types

### `typescript_type_name/0` is now `typescript_type/0`

```elixir
# Before
def typescript_type_name, do: "`#${string}`"

# After
def typescript_type, do: "`#${string}`"
```

Compiling the manifest fails while a type module it reaches still exports
`typescript_type_name/0`: "MyApp.HexColor exports `typescript_type_name/0`,
which is now `typescript_type/0`: rename it." A type whose TypeScript comes
from its fields (a map-like type with declared fields, or an
`Ash.Type.NewType` with fields or over a union) is told to remove it
instead: "MyApp.Palette exports `typescript_type_name/0`: remove it; its
TypeScript is generated from its fields or members." A map-like type that still has it and
declares no fields reports the undeclared custom type error first (see the next
section). The callback that names an alias, new in this release, is
`typescript_type_alias/0`.

### `typescript_type/0` on NewTypes with fields is rejected

An `Ash.Type.NewType` with fields (a typed map, keyword or tuple, an
`Ash.TypedStruct`, a struct with `fields`) or over a union that exports
`typescript_type/0` fails manifest compilation, aliased or not:
"MyApp.Address exports `typescript_type/0`: remove it; its TypeScript is
generated from its fields or members." Before, only an aliased one failed; an unaliased
one was typed with the callback's string in `XResourceSchema` but inline in
`XAttributesOnlySchema`, so its sub-field selection wasn't typed.

```elixir
# Before
defmodule MyApp.Address do
  use Ash.TypedStruct
  def typescript_type, do: "MyAddress"

  typed_struct do
    field :street, :string
  end
end

# After: remove the callback. To export a name, opt into an alias
defmodule MyApp.Address do
  use Ash.TypedStruct
  def typescript_type_alias, do: "MyAddress"

  typed_struct do
    field :street, :string
  end
end
```

Clients select its sub-fields (`{ address: ["street"] }`). See
[NewTypes With Fields](../advanced/custom-types.md#newtypes-with-fields).

### Map-like custom types declare fields

A custom type whose values are maps or structs (`storage_type :map`, or
composite) named a hand-written TypeScript type, was selected whole, and sent
every key of its values. It now behaves like a typed map: it declares its
fields (compiling the manifest fails until it does), clients select its
sub-fields, only declared keys are sent and accepted, and its TypeScript type,
input type and schemas are generated from the fields. It can't declare a
TypeScript type itself.

For a type you own, replace `typescript_type_name/0` with
`typescript_fields/0`:

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

For a type you don't own, declare a `map` entry in `custom_types` instead:

```elixir
custom_types do
  map SomeLib.ColorPalette do
    field :primary, :string, allow_nil?: false
    field :secondary, :string, allow_nil?: false
    field :accent, :string
  end
end
```

A composite type's `composite_types/1` entries are already its fields.

Then select its sub-fields in the client. Selecting it bare is a TypeScript
error and a `requires_field_selection` error on the server, and a generic
action that returns one needs `fields`:

```typescript
// Before
const todo = await getTodo({ input: { id }, fields: ["id", "colorPalette"] });

// After
const todo = await getTodo({
  input: { id },
  fields: ["id", { colorPalette: ["primary", "secondary", "accent"] }],
});
```

The generated code no longer references the hand-written
`CustomTypes.ColorPalette` imported through `import_into_generated`. Delete it
and import the generated alias instead, or keep it for your own code. For
member types more precise than the generated ones, see
[Precise Member Types](../advanced/custom-types.md#precise-member-types). See
[Map-Like Custom Types](../advanced/custom-types.md#map-like-custom-types).

### Declared custom types are exported

Every map-like custom type with declared fields is exported from the types
file as an alias (plus `<Name>Input` when its input shape differs), and gets a
named zod/valibot schema. The alias is its `map` entry's `ts_alias`, else its
`typescript_type_alias/0`, else the joined module name (`MyApp.ColorPalette`
becomes `MyAppColorPalette`). See
[Naming the Type](../advanced/custom-types.md#naming-the-type) and
[Generated TypeScript](../advanced/custom-types.md#generated-typescript).

- Replace hand-written aliases for these types with imports of the generated
  ones.
- An alias of your own that your code imports next to the generated names (a
  `Money` of yours, say) needs one of them renamed: set `ts_alias "…"` on the
  type's `map` entry, or `typescript_type_alias/0` on the type. A collision
  with a generated name warns when the manifest compiles and fails codegen
  (see [Name Collisions](../advanced/custom-types.md#name-collisions)).
- Filter values, identity and `getBy` values and action metadata of typed maps
  no longer carry `__type` / `__primitiveFields`. Code that read those keys from
  a metadata type no longer compiles.

### Structured filter values take the input shape

Filter values on typed maps and structs, keywords, tuples and unions take the
type's input shape and client keys, which the server maps back to attribute
names and casts as the same action input would be stored. Before, the keys
were passed to Ash as sent, so client names failed or were silently dropped,
and `eq` and `has` on a union, keyword or tuple matched nothing. An unknown key
is now `unknown_input`, and a value the type rejects is `invalid_filter_value`.
Ordering operators (`lessThan`, `greaterThan`, …) are gone from these values
unless the type is a declared custom type, and the server rejects them as
`unknown_filter_operator`. A value that is or contains a record (an embedded
resource, an array of them, or a calculation returning a record) only offers
`isNil`, and union filter values leave out members that are embedded
resources: a record sent over the wire gets its own generated id and defaults,
so it never equals a stored one.
See
[Filtering on Structured Values](../guides/querying-data.md#filtering-on-structured-values).

### Money, ULID, Ltree and AshUUID

These are built-in declarations now. See
[Built-In Types](../advanced/custom-types.md#built-in-types).

- `AshMoney.Types.Money` is a map of `currency` and `amount`. Select
  `{ price: ["currency", "amount"] }` instead of `"price"`. Responses no longer
  contain `format_options`. The `Money` alias is now
  `{currency: string, amount: Decimal}` (was `{ amount: string; currency: string }`);
  `Decimal` is `string`, so values stay assignable both ways.
- The `ULID`, `AshPostgresLtreeArray` and `AshPostgresLtreeFlexible` aliases are
  now exported only when a field uses them.
- `AshUUID.UUID` is not built in. Replace its `type_mapping_overrides` entry
  with `scalar AshUUID.UUID, :string`, not `:uuid`.
- A `custom_types` entry for one of these modules replaces the built-in.

## For library and extension authors

- Internal runtime modules (pipeline, field processing, formatters, error
  builder) moved from `AshTypescript.Rpc.*` to `AshRpc.*` (for example
  `AshRpc.Pipeline`, `AshRpc.RequestedFieldsProcessor`, `AshRpc.ErrorBuilder`),
  and `AshTypescript.ErrorFormatter` is now `AshRpc.ErrorFormatter`. They take
  an explicit `AshRpc.Runtime` (`AshRpc.Runtime.new(AshTypescript.RpcProfile)`)
  instead of an OTP app name or global config. `AshTypescript.FieldFormatter`
  remains for codegen.
- `AshTypescript.Rpc.ValidationErrorSchemas` is removed.
- An `AshTypescript.Codegen.SchemaFormatter` implementation drops
  `mapping_overrides/0`, `third_party_types/0`, `ltree_array/0`,
  `ltree_union/0`, `null_schema/0`, `aggregate_types/0` and
  `atom_primitives/0`, and gains `library/0` (`:zod` or `:valibot`),
  `wrap_lazy/1` (a deferred reference: `z.lazy(() => schema)`,
  `v.lazy(() => schema)`) and `schema_type/1` (the type of a schema for a
  TypeScript type: `z.ZodType<T>`, `v.GenericSchema<T>`).
- `AshTypescript.TypedChannel.PayloadFormatter` takes the channel module:
  `format_payload(channel_module, resource, event, payload)` and
  `push_formatted(socket, channel_module, resource, event, payload)`. See
  [Payload Formatting](../guides/typed-channels.md#payload-formatting).
- Other removed and changed public functions are listed in the
  [changelog](../../CHANGELOG.md); the helpers below are the ones apps and
  extensions most likely call.

### Removed helpers

| Removed | Replacement |
|---|---|
| `AshTypescript.Rpc.Info.get_mapped_metadata_field_name/2` | `Keyword.get(rpc_action.metadata_field_names, field, field)` (the rpc_action's `metadata_field_names`) |
| `AshTypescript.Resource.Info.get_mapped_field_name/2`, `get_mapped_argument_name/3` | `AshTypescript.Resource.Info.typescript_field_names!/1` / `typescript_argument_names!/1` (keyword lists of the explicit `field_names` / `argument_names` entries) |
| `AshTypescript.TypeSystem.Introspection.get_typescript_field_names_map/1` | `Map.new(module.typescript_field_names())` when the type exports it |
| `AshTypescript.Manifest.Custom.field_name_mappings/1`, `mapped_field_name/2`, `original_field_name/2`, `mapped_argument_name/3`, `original_argument_name/3`, `type_field_name_mappings/1`, `reverse_type_field_name_mappings/1`, `type_field_name_mappings_pair/1` | the `AshRpc.Manifest.Custom` readers they delegated to: `field_name_overrides/1`, `field_name_override/2`, `original_field_name/2`, `argument_name_override/3`, `original_argument_name/3`, `type_field_name_overrides/1`, `type_field_name_overrides_pair/1` |
| `AshTypescript.Manifest.Custom.relationship_read_action/1`, `action_input_field_types/1` | `AshRpc.Manifest.Custom.relationship_read_action/1`, `action_input_field_types/1` |
| `AshTypescript.Manifest.Custom.ash_typescript/1`, `resource_config/1` | none |
| `AshTypescript.Manifest.Custom.metadata_field_mappings/1`, `reverse_metadata_field_mappings/1`, `exposed_metadata_fields/1`, `load_restrictions/1`, `filtering_enabled?/1`, `sorting_enabled?/1` | the fields of the wire `AshRpc.Entrypoint`, from `AshRpc.Manifest.entrypoint_lookup/1` |
| `SchemaFormatter` callbacks `null_schema/0`, `aggregate_types/0`, `atom_primitives/0` | none (never called) |
| `AshTypescript.Codegen.generate_all_schemas_for_resource/2,3`, `generate_input_schema/1` (and their `ResourceSchemas` twins), `SchemaCore.generate_schema_for_resource/2,3`, `ZodSchemaGenerator.generate_zod_schemas_for_resources/1`, `generate_zod_schema_for_resource/1`, `ValibotSchemaGenerator.generate_valibot_schema_for_resource/1` | `mix ash_typescript.codegen`, or `AshTypescript.Codegen.Orchestrator` |
| `AshTypescript.Rpc.Codegen.Helpers.ActionIntrospection.get_action!/2` | `Ash.Info.Manifest.get_action(Ash.Info.Manifest.action_lookup(manifest), resource, action)` (`nil` on a miss instead of raising) |
| `ActionIntrospection.format_input_name/4,5`, `accepted_attribute?/3` | none (ash_rpc reports input name collisions) |
| `AshTypescript.Helpers.camel_to_snake_case/1`, `formatted_args_field/0` | none |
| `AshTypescript.Rpc.output_field_formatter/0` | `AshTypescript.output_field_formatter/0` |
| `AshTypescript.Rpc.Codegen.RpcConfigCollector.entrypoint_for/2` | the wire `AshRpc.Entrypoint`, from `AshRpc.Manifest.entrypoint_lookup/1` |
| `AshTypescript.Rpc.Codegen.TypeGenerators.MetadataTypes.get_exposed_metadata_fields/2` | `AshRpc.Introspection.get_exposed_metadata_fields/2` |

Changed codegen functions:

| Before | After |
|---|---|
| `RestrictedSchema.get_schema_and_reference/4` | `get_schema_and_reference/3`, the schema name from the rpc_action's name |
| `MetadataTypes.generate_action_metadata_type(resource, action, rpc_action, pascal_name)` | `generate_action_metadata_type(action, rpc_action, rpc_action_name)` |
| `MetadataTypes.exposed_metadata_fields(resource, rpc_action)` | `exposed_metadata_fields(rpc_action)` |
| `PaginationTypes.generate_pagination_result_type/5`, `generate_conditional_pagination_result_type/5` with the PascalCase name | the same, with the rpc_action's name |
| `TypescriptStatic.generate_imports(opts)` (`:skip_zod`, `:skip_valibot`, `:output_file`) | `generate_imports(output_file)` |
| `Rpc.Codegen.generate_namespace_reexport_content/3,4` | `generate_namespace_reexport_content/5` (the zod and valibot file paths as `nil` when there are none) |
| `Manifest.Decorator.decorate/1`, `HttpRenderer` / `ChannelRenderer.render_execution_function/4`, `FunctionCore.build_execution_function_shape/4`, `TypedController.Codegen.collect_route_zod_schemas/0`, `collect_route_valibot_schemas/0`, `get_routes_by_namespace/0`, `RouteRenderer.render_no_zod/1` | the arity that takes every argument (the options as `[]`) |
