<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>

SPDX-License-Identifier: MIT
-->

# AshTypescript - AI Assistant Guide

## Project Overview

**AshTypescript** generates TypeScript types and RPC clients from Ash resources, providing end-to-end type safety between Elixir backends and TypeScript frontends.

**Key Features**: Type generation, RPC client generation, Phoenix channel RPC actions, typed channel event subscriptions, typed controller route helpers, action metadata support, nested calculations, multitenancy, embedded resources, union types, field/argument/metadata name mapping, load restrictions, configurable RPC warnings, JSON manifest for third-party integrations

## 🚨 Critical Development Rules

### Rule 1: Always Use Test Environment
| ❌ Wrong | ✅ Correct | Purpose |
|----------|------------|---------|
| `mix ash_typescript.codegen` | `mix test.codegen` | Generate types |
| One-off shell debugging | Write proper tests | Debug issues |

**Why**: Test resources (`AshTypescript.Test.*`) and the test manifest module only compile/configure in `:test`. Running codegen in dev raises ``No `:manifest` module configured``.

### Rule 2: Documentation-First Workflow
For any complex task (3+ steps):
1. **Check documentation index below** to find relevant documentation
2. **Read recommended docs first** to understand patterns
3. **Then implement** following established patterns

**Skip documentation → broken implementations, wasted time**

## Essential Workflows

### Type Generation Workflow
```bash
mix test.codegen                      # Generate TypeScript types
cd test/ts && npm run compileGenerated # Validate compilation
mix test                              # Run Elixir tests
```

### Domain Configuration
```elixir
defmodule MyApp.Domain do
  use Ash.Domain, extensions: [AshTypescript.Rpc]

  typescript_rpc do
    resource MyApp.Todo do
      rpc_action :list_todos, :read
      rpc_action :list_todos_no_filter, :read, enable_filter?: false  # Disable client filtering
      rpc_action :list_todos_no_sort, :read, enable_sort?: false      # Disable client sorting
      # Load restrictions - control which relationships/calculations clients can load
      rpc_action :list_todos_limited, :read, allowed_loads: [:user]           # Whitelist
      rpc_action :list_todos_no_user, :read, denied_loads: [:user]            # Blacklist
      rpc_action :list_todos_nested, :read, allowed_loads: [comments: [:author]]  # Nested
    end
  end
end
```

### Manifest Module (Required)

Every AshTypescript project **must** declare a manifest module and register it in config. `mix test.codegen`/`mix ash_typescript.codegen` and the runtime RPC pipeline both read all action/resource/type shape from this manifest (a decorated `Ash.Info.Manifest`). Codegen raises if `:manifest` is unset.

```elixir
# config/config.exs (config/test.exs for this repo's test suite)
config :ash_typescript, manifest: MyApp.AshTypescriptManifest

# lib/my_app/ash_typescript_manifest.ex
defmodule MyApp.AshTypescriptManifest do
  use AshTypescript.Manifest,
    otp_app: :my_app,
    typed_controllers: [MyApp.Session],   # default [], the only source
    typed_channels: [MyApp.OrgChannel]    # default [], the only source

  # Custom types the app doesn't own (replaces the removed *_mapping_overrides config)
  custom_types do
    scalar SomeLib.ObjectId, :string, zod: "CustomZodSchemas.objectId"
    map SomeLib.ColorPalette do
      field :primary, :string, allow_nil?: false
    end
  end
end
```

Map-like custom types (`storage_type :map` or composite) are named types with declared fields (`custom_types` `map` > `typescript_fields/0` > built-in Money > `composite_types/1`, see `AshTypescript.CustomTypes`), selected by sub-field and typed from their fields; undeclared ones fail manifest compilation. Each is exported as an alias (`Money`, plus `ThemeInput` when its input shape differs) referenced at plain positions, and gets a named zod/valibot schema (the alias plus the schema suffix, `MoneyZodSchema`). The alias is the `map` entry's `ts_alias`, else the type's `typescript_type_alias/0`, else the joined module name (`SomeLib.Coordinates` → `SomeLibCoordinates`); the built-in Money is `Money`. Details: [type-system.md](agent-docs/features/type-system.md).

The manifest also stores typed controller routes (`%AshTypescript.Manifest.Route{}`, keyed `{source_module, name}`) and typed channel publications (`%AshTypescript.Manifest.Publication{}`, keyed `{channel_module, resource, event}`) for the modules in `typed_controllers:` / `typed_channels:`, under `custom.ash_typescript.routes` / `.publications` (read with `AshTypescript.Manifest.Custom.route/3`, `routes/1`, `publication/4`, `publications/1`). Codegen and the runtime take their typed module sets from there; `config :ash_typescript, :typed_controllers` / `:typed_channels` are no longer read, and setting either triggers a compile-time warning. The manifest has a compile-time edge on each listed module, so typed controllers and channels must never read the manifest at compile time. Tests build manifests with other lists via `AshTypescript.Test.InlineManifest.build!/1`, never `put_env`.

The module walks `Ash.Info.domains(otp_app)` by default. For scoped/inline manifests (e.g. building from a freshly-defined domain in a test) pass `domains: [MyTest.InlineDomain]`. `handle_opts/1` injects static compile-time dependencies on the configured domains, so editing a resource recompiles the manifest — incremental `mix test.codegen` is never stale. Access precomputed lookups via `AshTypescript.action_lookup/0`, `resource_lookup/0`, `type_lookup/0`, `typed_query_lookup/0`; ash_typescript-owned decoration lives under `custom.ash_typescript` and is read through `AshTypescript.Manifest.Custom`. `AshTypescript.RpcMappingSource` supplies the runtime's `custom.ash_rpc` decoration (see [rpc-integration.md](agent-docs/features/rpc-integration.md), Decoration). Codegen reads every client name (resource fields, calculation arguments, action inputs, type fields, union members, metadata) from that same `custom.ash_rpc` decoration through `AshTypescript.Codegen.ClientNames`, so generated names always equal the names the runtime accepts; see [field-argument-name-mapping.md](agent-docs/features/field-argument-name-mapping.md#where-codegen-gets-names). `output_field_formatter` and global `not_found_error?` are read when the manifest compiles (tracked via `Application.compile_env`) — runtime `put_env` has no effect. There is no input formatter: request keys must be the output formatter's client names exactly. Tests vary them with `AshTypescript.Manifest.redecorate(manifest, output_formatter: …)` (never `AshRpc.Manifest.redecorate/2`, which leaves routes and channel publications in the old formatter; `test/ash_typescript/redecorate_guard_test.exs` enforces this) + the `manifest:` option, or `AshTypescript.with_manifest/2` for codegen/typed controllers (`CodegenTestHelper` accepts `manifest:`).

### Typed Controller Configuration

Three syntaxes are supported for defining routes:

```elixir
defmodule MyApp.Session do
  use AshTypescript.TypedController

  typed_controller do
    module_name MyAppWeb.SessionController

    # Verb shortcut (preferred) — method is the entity name
    get :auth do
      run fn conn, _params -> render_inertia(conn, "Auth") end
    end

    # Positional method arg
    route :login, :post do
      run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
      argument :code, :string, allow_nil?: false
      # Optional: rename the generated schemas to dodge RPC action collisions
      zod_schema_name "loginRouteZodSchema"
      valibot_schema_name "loginRouteValibotSchema"
    end

    # Declared JSON response → `{Route}Result` TS type + typed fetch function (GET too).
    # Plain data only (no resources/unions/recursion, at any depth; checked at manifest
    # compile); `json/2` formats per output_field_formatter
    get :current_user do
      returns :map
      constraints fields: [user_id: [type: :uuid, allow_nil?: false]]
      run fn conn, _params -> AshTypescript.TypedController.json(conn, %{user_id: "..."}) end
    end

    # Method defaults to :get when omitted. Arguments accept any Ash type form,
    # arrays included; GET args become query params (`?tags[]=a&tags[]=b`)
    route :home do
      run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "Home") end
      argument :tags, {:array, :string}, constraints: [items: [min_length: 2]]
    end
  end
end
```

### Runtime (ash_rpc)

The runtime lives in the separate `ash_rpc` package (`AshRpc.*` modules). Look up its API with `mix usage_rules.docs AshRpc.<Module>` (or hexdocs) rather than reading its source. ash_typescript supplies `AshTypescript.RpcMappingSource` and `AshTypescript.RpcProfile`, and decorates the manifest twice (`custom.ash_rpc`, `custom.ash_typescript`). How the two fit together: [rpc-integration.md](agent-docs/features/rpc-integration.md).

```elixir
# Controller (generated by the installer) — sends the JSON itself, always 200
def run(conn, _params), do: AshRpc.Plug.run(conn, AshTypescript.RpcProfile)
def validate(conn, _params), do: AshRpc.Plug.validate(conn, AshTypescript.RpcProfile)

# Or get the map: AshRpc.run_action/4, AshRpc.validate_action/4 (opts: manifest:, entrypoint:)
AshRpc.run_action(AshTypescript.RpcProfile, conn_or_socket_or_context, params)

# Typed queries (server-side rendering); params is required (:input/:page/:filter/:sort)
AshTypescript.run_typed_query(:dashboard_todo, %{}, conn)
```

All entry points return client-formatted maps (`%{"success" => true, "data" => …}` / `%{"success" => false, "errors" => […]}`), never tuples.

### TypeScript Usage
```typescript
import { listTodos, buildCSRFHeaders } from './ash_rpc';

const todos = await listTodos({
  fields: ["id", "title", { user: ["name"] }],
  headers: buildCSRFHeaders()
});
```

### Phoenix Channel-based RPC Actions

**Server channel**: `use AshRpc.Channel` injects `handle_in("run" | "validate" | catch-all)`. For extra events, skip the macro and call `AshRpc.Channel.run/3` / `validate/3` from your own `handle_in/3`.

> **Runtime:** actor, tenant and context come from `socket.assigns[:ash_actor | :ash_tenant | :ash_context]`, and a `tenant` param overrides the tenant.

```elixir
defmodule MyAppWeb.AshTypescriptRpcChannel do
  use Phoenix.Channel
  use AshRpc.Channel, profile: AshTypescript.RpcProfile

  @impl true
  def join("ash_typescript_rpc:" <> _id, _payload, socket), do: {:ok, socket}
end
```

**Generated Channel Functions**: AshTypescript generates channel functions with `Channel` suffix:
```typescript
import { Channel } from "phoenix";
import { listTodos, listTodosChannel } from './ash_rpc';

// HTTP-based (always available)
const httpResult = await listTodos({
  fields: ["id", "title"],
  headers: buildCSRFHeaders()
});

// Channel-based (when enabled)
listTodosChannel({
  channel: myChannel,
  fields: ["id", "title"],
  resultHandler: (result) => {
    if (result.success) {
      console.log("Todos:", result.data);
    } else {
      console.error("Error:", result.errors);
    }
  },
  errorHandler: (error) => console.error("Channel error:", error),
  timeoutHandler: () => console.error("Timeout")
});
```

### Typed Channel Event Subscriptions

For typed one-way push events from Ash PubSub publications.

**Recommended**: Use `transform :some_calc` to reference a resource calculation.
Ash auto-derives the `returns` type when the calculation uses `:auto`, so
AshTypescript gets the type information it needs without manual `returns` declarations.
Every declared publication needs a `returns` that is a typed map (an `:auto` map
expression, or `returns: :map` with `fields`), checked when the manifest compiles.

```elixir
# Resource with calculation transforms (recommended)
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

# Channel definition — must also be a Phoenix channel (compile warning otherwise).
# Declared events are auto-intercepted and payloads formatted with the
# output_field_formatter before push, so the wire matches the generated types.
defmodule MyAppWeb.OrgChannel do
  use Phoenix.Channel
  use AshTypescript.TypedChannel

  typed_channel do
    topic "org:*"

    resource MyApp.Post do
      publish :post_created
      publish :post_updated
    end
  end

  @impl true
  def join("org:" <> _org_id, _payload, socket), do: {:ok, socket}
end
```

You can also use explicit `returns` with an anonymous function transform, but
this requires manually keeping the type and transform in sync:

```elixir
publish :create, [:id],
  event: "post_created",
  public?: true,
  returns: :map,
  constraints: [fields: [id: [type: :uuid], title: [type: :string]]],
  transform: fn notification -> %{id: notification.data.id, title: notification.data.title} end
```

```typescript
import { createOrgChannel, onOrgChannelMessages, unsubscribeOrgChannel } from './ash_typed_channels';

const channel = createOrgChannel(socket, orgId);
const refs = onOrgChannelMessages(channel, {
  post_created: (payload) => console.log("New post:", payload),
  post_updated: (payload) => console.log("Updated:", payload),
});
// Cleanup: unsubscribeOrgChannel(channel, refs);
```

## Runtime Introspection (Tidewave MCP)

**Use these tools instead of shell commands for Elixir evaluation:**

| Tool | Purpose |
|------|---------|
| `mcp__tidewave__project_eval` | **Primary tool** - evaluate Elixir in project context |
| `mcp__tidewave__get_docs` | Get module/function documentation |
| `mcp__tidewave__get_source_location` | Find source locations |

**Debug Examples:**
```elixir
# Check what an rpc_action resolved to
mcp__tidewave__project_eval("""
runtime = AshRpc.Runtime.from_manifest(AshTypescript.manifest())
runtime.entrypoints["list_todos"]
# => %AshRpc.Entrypoint{name: "list_todos", enable_filter?: true, load_restrictions: :none, ...}
""")
```

## Codebase Navigation

### Key File Locations

| Purpose | Location |
|---------|----------|
| **Runtime modules (`AshRpc.*`)** | `ash_rpc` package: `mix usage_rules.docs AshRpc.<Module>` |
| **Core type generation (entry point)** | `lib/ash_typescript/codegen.ex` (delegator) |
| **Type system introspection** | `lib/ash_typescript/type_system/introspection.ex` |
| **RPC resource discovery & warnings** | `lib/ash_typescript/codegen/type_discovery.ex` |
| **Reachability analysis** | `Ash.Info.Manifest.Generator.Reachability` (ash core) |
| **Manifest module (Spark DSL, required per-app)** | `lib/ash_typescript/manifest.ex` |
| **Manifest Custom decoration accessors** | `lib/ash_typescript/manifest/custom.ex` |
| **Manifest decorator & transformers** | `lib/ash_typescript/manifest/decorator.ex`, `lib/ash_typescript/manifest/transformers/` |
| **Manifest verifiers (RPC-extension scope)** | `lib/ash_typescript/manifest/verifiers/` |
| **Action introspection helper (codegen)** | `lib/ash_typescript/rpc/codegen/helpers/action_introspection.ex` |
| **ash_typescript RPC profile** | `lib/ash_typescript/rpc_profile.ex` (`AshTypescript.RpcProfile`) |
| **ash_typescript mapping source** | `lib/ash_typescript/rpc_mapping_source.ex` (`AshTypescript.RpcMappingSource`) |
| **AshAuthentication error impls** | `lib/ash_typescript/rpc/ash_authentication_errors.ex` |
| **Codegen client names (every emitted resource/type/action name)** | `lib/ash_typescript/codegen/client_names.ex` (reads `custom.ash_rpc`; guarded by `test/ash_typescript/codegen_name_source_guard_test.exs`) |
| **Formatter-only names (static vocabulary, TS identifiers)** | `lib/ash_typescript/field_formatter.ex` |
| **Type aliases generation** | `lib/ash_typescript/codegen/type_aliases.ex` |
| **Declared custom type aliases (`Money`, `ThemeInput`)** | `lib/ash_typescript/codegen/custom_type_aliases.ex` (names read through `AshTypescript.Manifest.Custom.type_alias_names/1`; `reaches_resource?/1`, `check_recursive_types!/0`) |
| **Custom type alias collision verifier** | `lib/ash_typescript/manifest/verifiers/verify_custom_type_names.ex` |
| **Type nodes the manifest reaches (compile-time checks, renamed-callback check)** | `lib/ash_typescript/manifest/type_uses.ex` (`TypeUses.nodes/1`; used by `CustomTypes.check_renamed_callbacks/1`, `check_alias_names/2`, `compile_dependencies/3` and `VerifyCustomTypeNames`) |
| **Scalar aliases (`CustomIdentifier`, `ULID`, Ltree's variants)** | `lib/ash_typescript/codegen/scalar_aliases.ex` (`ScalarAliases.name/2`, rendered by `TypeMapper` at every use; `aliases/1` walks `TypeAliases.roots/4` for the primitive alias block, one alias per name, two bodies under one name is a codegen error) |
| **TypeScript type mapping** | `lib/ash_typescript/codegen/type_mapper.ex` |
| **Resource schema generation** | `lib/ash_typescript/codegen/resource_schemas.ex` |
| **Filter types generation** | `lib/ash_typescript/codegen/filter_types.ex` |
| **Sort types generation** | `lib/ash_typescript/codegen/sort_types.ex` |
| **Zod schema generation** | `lib/ash_typescript/codegen/zod_schema_generator.ex` |
| **Valibot schema generation** | `lib/ash_typescript/codegen/valibot_schema_generator.ex` |
| **Utility types generation** | `lib/ash_typescript/codegen/utility_types.ex` |
| **Import path resolution** | `lib/ash_typescript/codegen/import_resolver.ex` |
| **Shared types generator** | `lib/ash_typescript/codegen/shared_types_generator.ex` |
| **Shared schema generator** | `lib/ash_typescript/codegen/shared_schema_generator.ex` |
| **Schema formatter behaviour** | `lib/ash_typescript/codegen/schema_formatter.ex` |
| **Schema core (shared logic)** | `lib/ash_typescript/codegen/schema_core.ex` |
| **Multi-file orchestrator** | `lib/ash_typescript/codegen/orchestrator.ex` |
| **RPC client generation** | `lib/ash_typescript/rpc/codegen.ex` |
| **TypeScript static code (RPC)** | `lib/ash_typescript/rpc/codegen/typescript_static.ex` |
| **JSDoc comment generation** | `lib/ash_typescript/rpc/codegen/function_generators/jsdoc_generator.ex` |
| **Manifest generation (Markdown)** | `lib/ash_typescript/rpc/codegen/manifest_generator.ex` |
| **Manifest generation (JSON)** | `lib/ash_typescript/rpc/codegen/json_manifest_generator.ex` |
| **Namespace resolution** | `lib/ash_typescript/rpc/codegen/rpc_config_collector.ex` |
| **Resource verifiers (name/type scope)** | `lib/ash_typescript/resource/verifiers/` |
| **Typed controller DSL** | `lib/ash_typescript/typed_controller/dsl.ex` |
| **Typed controller transformers** | `lib/ash_typescript/typed_controller/transformers/` |
| **Typed controller main** | `lib/ash_typescript/typed_controller.ex` |
| **Controller request handler** | `lib/ash_typescript/typed_controller/request_handler.ex` |
| **Controller codegen** | `lib/ash_typescript/typed_controller/codegen.ex` |
| **Controller config discovery** | `lib/ash_typescript/typed_controller/codegen/route_config_collector.ex` |
| **Router introspection** | `lib/ash_typescript/typed_controller/codegen/router_introspector.ex` |
| **Route renderer** | `lib/ash_typescript/typed_controller/codegen/route_renderer.ex` |
| **TypeScript static code (controller)** | `lib/ash_typescript/typed_controller/codegen/typescript_static.ex` |
| **Controller verifier** | `lib/ash_typescript/typed_controller/verifiers/verify_typed_controller.ex` |
| **Typed channel DSL** | `lib/ash_typescript/typed_channel/dsl.ex` |
| **Typed channel main** | `lib/ash_typescript/typed_channel.ex` |
| **Typed channel codegen** | `lib/ash_typescript/typed_channel/codegen.ex` |
| **Typed channel verifier** | `lib/ash_typescript/typed_channel/verifiers/verify_typed_channel.ex` |
| **Channel payload type mapper** | `lib/ash_typescript/codegen/type_mapper.ex` (`map_channel_payload_type/1`) |
| **Test domain** | `test/support/domain.ex` |
| **Primary test resource** | `test/support/resources/todo.ex` |
| **TypeScript validation** | `test/ts/shouldPass/` & `test/ts/shouldFail/` |
| **TypeScript call extractor** | `test/support/ts_action_call_extractor.ex` |
| **Codegen test helper** | `test/support/codegen_test_helper.ex` |
| **Typed controller tests** | `test/ash_typescript/typed_controller/` |
| **Typed channel tests** | `test/ash_typescript/typed_channel/` |
| **Test typed controller** | `test/support/resources/session.ex` |
| **Test router** | `test/support/routes_test_router.ex` |
| **Generated route helpers** | `test/ts/generated_routes.ts` |

## Command Reference

### Core Commands
```bash
mix test.codegen                      # Generate TypeScript (main command)
mix test.codegen --dry-run           # Preview output
mix test                             # Run all tests (do NOT prefix with MIX_ENV=test)
mix test test/ash_typescript/rpc/    # Test RPC functionality
```

### TypeScript Validation (from test/ts/)
```bash
npm run compileGenerated             # Test generated types compile
npm run compileGeneratedRoutes       # Test generated route helpers compile
npm run compileGeneratedTypedChannels # Test generated typed channels compile
npm run compileShouldPass            # Test valid patterns (type-level)
npm run compileShouldFail            # Test invalid patterns fail (type-level)
npm run testZod                      # Run generated Zod schemas against real data
npm run testValibot                  # Run generated Valibot schemas against real data
```

`testZod` / `testValibot` compile and **execute** the generated validation
schemas against fixture inputs — they are the only path that exercises schema
runtime behavior (e.g. catches a bug like an empty `z.object({})` for a type
that should validate `{ amount, currency }`). Always run them after touching
`custom_types` entries, built-ins, constraint generation, or any other validation codegen.

### Quality Checks
```bash
mix format                           # Code formatting
mix credo --strict                   # Linting
```

## Documentation Index

### Core Files

| File | Purpose |
|------|----------|
| [troubleshooting.md](agent-docs/troubleshooting.md) | Development troubleshooting |
| [testing-and-validation.md](agent-docs/testing-and-validation.md) | Test organization and validation procedures |
| [architecture-decisions.md](agent-docs/architecture-decisions.md) | Architecture decisions and context |

### Implementation Documentation Guide

**Consult these when modifying core systems:**

| Working On | See Documentation | Test Files |
|------------|-------------------|------------|
| **Type generation or custom types** | [features/type-system.md](agent-docs/features/type-system.md) | `test/ash_typescript/typescript_codegen_test.exs`, `test/ash_typescript/custom_types/`, `test/ash_typescript/custom_types_test.exs`, `test/ash_typescript/scalar_custom_types_test.exs`, `test/ash_typescript/codegen/custom_type_codegen_test.exs`, `test/ash_typescript/codegen/named_custom_types_test.exs`, `test/ash_typescript/manifest/custom_type_*_test.exs` (incl. `custom_type_names_test.exs`, `custom_type_name_collisions_test.exs`), `test/ash_typescript/manifest/custom_types_dsl_test.exs`, `test/ash_typescript/manifest/verify_mappable_types_test.exs`, `test/ash_typescript/manifest/legacy_type_config_warning_test.exs`, `test/ash_typescript/rpc/custom_type_fields_rpc_test.exs`, `test/ash_typescript/custom_type_output_test.exs` |
| **Field/argument name mapping** | [features/field-argument-name-mapping.md](agent-docs/features/field-argument-name-mapping.md) | `test/ash_typescript/rpc/rpc_field_argument_mapping_test.exs` |
| **Action metadata** | [features/action-metadata.md](agent-docs/features/action-metadata.md) | `test/ash_typescript/rpc/rpc_metadata_test.exs`, `test/ash_typescript/rpc/verify_metadata_field_names_test.exs` |
| **RPC integration (RpcProfile, RpcMappingSource, rpc_action options)** | [features/rpc-integration.md](agent-docs/features/rpc-integration.md) | `test/ash_typescript/rpc_mapping_source_test.exs`, `test/ash_typescript/rpc_profile_test.exs`, `test/ash_typescript/rpc/entrypoint_resolution_test.exs` |
| **Load restrictions** | [features/rpc-integration.md](agent-docs/features/rpc-integration.md) (Load Restrictions) | `test/ash_typescript/rpc/load_restrictions_test.exs`, `test/ash_typescript/rpc/restricted_schema_codegen_test.exs` |
| **Validation schemas (Zod & Valibot)** | [features/validation-schemas.md](agent-docs/features/validation-schemas.md) | `test/ash_typescript/rpc/zod_constraints_test.exs`, `test/ash_typescript/rpc/valibot_constraints_test.exs`, `test/ash_typescript/rpc/custom_type_schema_test.exs`, `test/ash_typescript/rpc/named_custom_type_schemas_test.exs` |
| **Embedded resources** | [features/embedded-resources.md](agent-docs/features/embedded-resources.md) | `test/support/resources/embedded/` |
| **Union types** | [features/union-systems-core.md](agent-docs/features/union-systems-core.md) | `test/ash_typescript/rpc/rpc_run_action_union_*_test.exs`, `test/ash_typescript/union_types_test.exs` |
| **Namespaces, JSDoc, Manifest, JSON Manifest** | [features/developer-experience.md](agent-docs/features/developer-experience.md) | `test/ash_typescript/rpc/namespace_test.exs`, `test/ash_typescript/rpc/json_manifest_generator_test.exs` |
| **Typed controllers & route helpers** | [features/typed-controller.md](agent-docs/features/typed-controller.md) | `test/ash_typescript/typed_controller/`, `test/ash_typescript/manifest/routes_test.exs` |
| **Typed channel event subscriptions** | [features/typed-channel.md](agent-docs/features/typed-channel.md) | `test/ash_typescript/typed_channel/`, `test/ash_typescript/manifest/publications_test.exs` |
| **Development patterns** | [development-workflows.md](agent-docs/development-workflows.md) | N/A |

## Key Architecture Concepts

### Runtime Integration
The manifest is decorated twice: `AshTypescript.RpcMappingSource` supplies the runtime's `custom.ash_rpc` decoration, and ash_typescript writes `custom.ash_typescript` for codegen (type names, rpc/typed-query config, routes, publications). Client names are not duplicated there: codegen reads them from `custom.ash_rpc` through `AshTypescript.Codegen.ClientNames`, and a missing name or an undecorated node raises `ArgumentError` (no formatter fallback). Only `RpcMappingSource` and the compile-time verifiers read the `field_names` / `argument_names` DSL and `typescript_field_names/0`. Each `rpc_action` becomes one `AshRpc.Entrypoint`, which carries its DSL options (`enable_filter?`, `load_restrictions`, `get_by`, …) to the runtime. `AshTypescript.RpcProfile` supplies the per-domain `error_handler` / `show_raised_errors?` from each domain's `typescript_rpc` block. Do not reintroduce `Ash.Resource.Info.action/2` or global `AshTypescript.*_lookup/0` reads into ash_rpc; codegen keeps using `ActionIntrospection` and `AshTypescript.action_lookup/0`. Details: [rpc-integration.md](agent-docs/features/rpc-integration.md).

### Key Modules
- **AshTypescript.RpcProfile** / **AshTypescript.RpcMappingSource** - ash_typescript's `AshRpc.Profile` / `AshRpc.MappingSource`

### Multi-File Codegen Architecture
- **Orchestrator** (`codegen/orchestrator.ex`): Coordinates all file generation — types, Zod, Valibot, RPC, routes, typed channels, namespace re-exports
- **SchemaCore** (`codegen/schema_core.ex`): Shared validation schema logic (topological sort, type mapping, field introspection) used by both Zod and Valibot via `SchemaFormatter` behaviour
- **ImportResolver** (`codegen/import_resolver.ex`): Shared utility for import path resolution and namespace re-export generation (used by both RPC and controller codegen)
- **CodegenTestHelper** (`test/support/codegen_test_helper.ex`): Test wrapper for orchestrator — use `generate_all_content/0` for string assertions, `generate_files/0` for file-level assertions

### Type System Architecture
- **Type Introspection**: Centralized in `type_system/introspection.ex`
- **Codegen Organization**: type_discovery (RPC config & warnings), type_aliases, type_mapper, resource_schemas, filter_types, sort_types; reachability lives in `Ash.Info.Manifest.Generator.Reachability` (ash core)

### Type Inference Architecture
- **Unified Schema**: Single ResourceSchema with `__type` metadata
- **Schema Keys**: Direct classification via key lookup
- **Utility Types**: `UnionToIntersection`, `InferFieldValue`, `InferResult`, `SortString`
- **Sort Types**: Per-resource `{Resource}SortField` union types and `{resource}SortFields` const arrays generated by `sort_types.ex`. RPC functions use `SortString<TodoSortField>` to provide type-safe sort parameters with `+`/`-`/`++`/`--` prefix support.

### Core Patterns
- **Field Selection**: Unified format supporting nested relationships and calculations
- **Embedded Resources**: Full relationship-like architecture with calculation support
- **Union Field Selection**: Selective member fetching with `{ content: ["field1", { nested: ["field2"] }] }`
- **Nested Relationship Query Options**: has_many/many_to_many loads accept an envelope `{ comments: { page, filter, sort, limit, offset, fields } }` — capability-gated in TS, validated at runtime, `page` yields the top-level page shape
- **Union Input Format**: REQUIRED wrapped format `{member_name: value}` for all union inputs
- **Headers Support**: All RPC functions accept optional headers for custom authentication
- **Strict Exposure**: Selecting fields through a relationship to a resource without the `AshTypescript.Resource` extension is `unknown_field`, so codegen doesn't emit such relationships (resource and restricted schemas, filter types, JSON manifest). Unexposed resources (struct-argument targets, and embedded resources without the extension) have formatter-only names and get no filter/sort types; unexposed non-embedded ones also get no `ResourceSchema` / `AttributesOnlySchema`, only their input schema
- **Tenant Param**: A `tenant` request param overrides the transport tenant (conn or `socket.assigns[:ash_tenant]`) on both HTTP and channels

## Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| "No `:manifest` module configured" | `manifest:` config missing | Add `config :ash_typescript, manifest: MyApp.AshTypescriptManifest` and define the module with `use AshTypescript.Manifest, otp_app: :my_app` |
| `UndefinedFunctionError` on `AshTypescript.Test.*` | Test resources not compiled (dev env) | Run via `mix test` / `mix test.codegen`, which set `MIX_ENV=test` via `preferred_envs` |
| "Invalid field names found" | Field/arg with `_1` or `?` | Use `field_names` or `argument_names` DSL options |
| "Invalid field names found in map/keyword/tuple type constraints" | Map constraint fields invalid | Create `Ash.Type.NewType` with `typescript_field_names/0` callback |
| "Unsupported types found — AshTypescript cannot map them" | Reachable type module has no TS mapping | Implement `typescript_type/0` on the type, or add a `scalar Mod, :string` entry to the manifest module's `custom_types` section |
| "undeclared custom type" / "Undeclared map-like custom types found" | A `storage_type :map` or composite custom type has no declared fields | Declare them: `typescript_fields/0`, a `custom_types` `map` entry, or `composite?/1` + `composite_types/1` (an inline manifest over the test app needs `InlineManifest.build!/1`'s default `body:`) |
| "Map-like custom types that declare a TypeScript type" | A map-like or field-declaring custom type exports `typescript_type/0` or has a `scalar` entry | Remove it; the TS type is generated from the fields |
| "Types with colliding TypeScript names found" | Two aliased types (map-like, or scalars with a string name) share an alias, or an alias equals a map-like alias plus `Input`, a resource-derived name (`XResourceSchema`, `XFilterInput`, …) or one of the 43 fixed names (primitive aliases, utility types) | `ts_alias "…"` on one type's `map` / `scalar` entry, or `typescript_type_alias/0` on the type when no entry sets `ts_alias` |
| "Duplicate exported type names in …" / "… imports types from … that it also declares" / "… imports names that it also imports from … or declares" / "… is an `import_name` in the … config" (codegen) | A custom type's alias equals a channel payload type, a name the RPC/routes/channels file declares (`ListTodosInput`), a name a generated file imports itself (`Channel` from phoenix, `z`, `v`), or an `import_name`; or its schema (alias plus suffix) equals such a name or a `*_import_into_generated` `import_name` | Rename the alias (which names the schemas): `ts_alias "…"` on its `map` entry, or `typescript_type_alias/0` on a type without one; or change the `import_name` |
| "Duplicate Zod schema names detected" naming a custom type | Its named schema (alias plus suffix) equals another schema (an alias `User` next to the resource `User`'s `UserZodSchema`) | Rename the alias: `ts_alias "…"` on its `map` entry, or `typescript_type_alias/0` |
| "The ts_alias … of Mod is not a TypeScript identifier" / "is a TypeScript reserved word" / "The typescript_type_alias/0 result … of Mod …" / "The typescript_type_alias/0 of Mod must return a string" | A `map` entry's `ts_alias` or a type's `typescript_type_alias/0` isn't an identifier, is a type keyword or JS reserved word, or (callback) isn't a string | Use an identifier that isn't reserved (`ts_alias` takes a string only) |
| "These aliased types contain themselves, directly or through other named types" (codegen) | A recursive aliased type (declared custom type or aliased NewType) | Expand the type to a fixed depth |
| "config :ash_typescript, :type_mapping_overrides is no longer read" (or `zod_`/`valibot_mapping_overrides`) | Removed config key still set | Move the entries to the manifest module's `custom_types` section |
| Zod/Valibot schema is `z.any()` for a custom type | Hand-rolled type whose `storage_type/1` has no unambiguous JSON form | Give it a `custom_types` `scalar` entry (base type, or `zod`/`valibot`; without `ts_type` it keeps the type's `typescript_type/0`), or express the type as an `Ash.Type.NewType` with constraints |
| `Cannot find name 'X'` in generated `ash_zod.ts` / `ash_valibot.ts` | A `custom_types` entry's `zod`/`valibot` references an imported symbol with no matching import | Add `zod_import_into_generated` / `valibot_import_into_generated` (`import_into_generated` does **not** apply to schema files) |
| "Invalid metadata field name" | Metadata field with `_1` or `?` | Use `metadata_field_names` DSL option in `rpc_action` |
| "Metadata field conflicts with resource field" | Metadata field shadows resource field | Rename metadata field or use different mapped name |
| TypeScript `unknown` types | Schema key mismatch | Check `__type` metadata generation |
| Field selection fails | Invalid field format | Use unified field format only |
| `unknown_field` through a relationship | Destination resource lacks the `AshTypescript.Resource` extension (strict exposure) | Add the extension to the destination resource |
| `UndefinedFunctionError` on the old `AshTypescript.Rpc` run/validate/typed-query functions | Runtime moved to `AshRpc` | `AshRpc.Plug.run/2` / `AshRpc.run_action(AshTypescript.RpcProfile, …)`, `AshTypescript.run_typed_query(name, params, conn)` — see `documentation/upgrading/ash-rpc.md` |
| `missing_required_parameter` for `action` on a typed-query request | The typed-query wire param was removed | Run typed queries server-side with `AshTypescript.run_typed_query/4` |
| Formatter / `not_found_error?` change in a test has no effect | Read at manifest compile time | `AshTypescript.Manifest.redecorate(manifest, output_formatter: …)` + `manifest:` option, or `AshTypescript.with_manifest/2` |
| "has no custom.ash_rpc decoration" `ArgumentError` | Manifest passed to `AshRpc` wasn't decorated | Use `AshTypescript.manifest/0` (or `redecorate/2` of it), not a raw `Ash.Info.Manifest` |
| Codegen `ArgumentError` "no client name for …" / "is not in the manifest" / "is not decorated" | Codegen asked `AshTypescript.Codegen.ClientNames` for a name the `custom.ash_rpc` decoration doesn't carry | A decoration gap: decorate the node at manifest build time (`RpcMappingSource` / `AshRpc.Manifest.Decorator`); never add a formatter fallback |
| `AshRpc.Manifest.NameCollisionError` at compile time | Two fields/args map to the same client name | Rename or fix `field_names`/`argument_names` mappings |
| `filter_not_supported` / `sort_not_supported` | Client sent `filter`/`sort` to an action with `enable_filter?`/`enable_sort?: false` (`details.reason: "disabled"`), or to a get-style or non-read action (`"unsupported"`) | Remove the param, or enable the option |
| Test reads stale generated.ts | Test uses `File.read!("test/ts/generated.ts")` | Use `AshTypescript.Test.CodegenTestHelper.generate_all_content/0` in `setup_all` |
| Controller 422 error | Missing required argument, failed type cast, or a violated argument constraint (min_length/match/min/max — enforced since 0.18) | Check `allow_nil?`, argument types, and declared `constraints`. Note `""` on a nilable string is normalized to `nil`, and strings are trimmed by default |
| "Invalid constraints for argument `x`" | Typed-controller route argument declares constraints the Ash type rejects | Fix the constraint keys/values to match `Ash.Type.constraints/1` for that type |
| Controller 500 error | Handler doesn't return `%Plug.Conn{}`, or the controller isn't in the manifest module's `typed_controllers:` ("is not in the AshTypescript manifest") | Return `%Plug.Conn{}` from handler; list the controller on the manifest module |
| Typed channel payload pushed unformatted, warning "is not in the manifest" | Channel not in the manifest module's `typed_channels:` | List it on the manifest module and recompile |
| Codegen warning "Found typed controllers or typed channels not listed in the manifest" | A typed controller/channel of the app isn't in the manifest module's `typed_controllers:` / `typed_channels:`, so codegen skips it | List it on the manifest module and recompile, or `warn_on_unlisted_typed_modules: false` |
| Routes not generated | Controller not on the manifest module, or no router | List it in `use AshTypescript.Manifest, typed_controllers: [...]`, set `router:` in config; `routes_output_file:` auto-derives as `ash_routes.ts` |
| Multi-mount ambiguity | Duplicate mounts without `as:` | Add unique `as:` to each scope |
| "load_not_allowed" error | Requested field not in `allowed_loads` | Add field to `allowed_loads` or remove the option |
| "load_denied" error | Requested field in `denied_loads` | Remove field from `denied_loads` list |
| "allowed_loads contains invalid load paths" | `allowed_loads`/`denied_loads` entry isn't a loadable public field | Fix the path; nested keys validated against the relationship destination |
| "show_metadata contains unknown metadata fields" | `show_metadata` names a field the action's `metadata` doesn't define | Only list declared metadata fields |
| Path param without matching argument | Router path has `:param` but no DSL argument | Add `argument :param, :string` to the route definition |
| Invalid names for TypeScript (controller) | Route/argument names with `_1` or `?`, or that aren't valid identifiers (`:"foo-bar"`) | Rename to avoid patterns that produce awkward camelCase |
| "generates the function `delete`, a JavaScript reserved word" | A typed controller route or `rpc_action` named after a JS reserved word (`:delete`, `:new`, `:import`, …; `NameValidation.reserved_word?/1`), whatever the method or mode | Rename it, for example `:delete_item` |
| "Invalid field names found in typed controller route types" | A `fields` constraint (in `returns` or an argument type, at any depth) has a name with `_1` or `?`, or one that isn't a valid identifier — or a type's `typescript_field_names/0` maps a field to such a name | Rename the field (or fix the mapping) — route bodies are sent as-is, so there is no route-level name mapping. Spark only warns at compile time; codegen fails |
| `allow_nil?: true` on always-present path param | Path param always provided by router | Set `allow_nil?: false` on the argument |
| `allow_nil?: false` on sometimes-present path param | Path param only at some mounts | Set `allow_nil?: true` (default) on the argument |
| "AshTypescript.TypedChannel is being used in module X without `use Phoenix.Channel`" | Typed channel module isn't a Phoenix channel, so payload interception can't be injected | Add `use Phoenix.Channel` and a `join/3` to the module |
| "No publication with event X found" | Typed channel event doesn't match any publication | Check `event:` option on the resource's `pub_sub` block |
| "Duplicate event names found in typed_channel" | Same event name across resources in one channel | Use unique event names per channel |
| "Payload type name conflict" | Same event name across different channels maps to different TS types | Rename events or ensure same `returns` type |
| Manifest compile error "publication ... has no `returns`" | Publication missing `returns` (no `transform :calc` or explicit `returns:`) | Use `transform :some_calc` with an `:auto` map calculation (recommended), or add explicit `returns: :map` with `constraints` and a `transform:` function |
| Manifest compile error "publication ... returns X, which is not a typed map" / "returns untyped data" | Channel payloads are typed maps: a scalar, enum, array, opaque custom type, `:term` or unconstrained `:map` is rejected | `returns: :map` (or `:struct`/`:keyword`/`:tuple`, a TypedStruct, a NewType of one) with `fields`; put the value in a field |
| Manifest compile error "... returns / accepts a resource / an embedded resource / a union / a recursive type, at <path>" | Route arguments, route results and channel payloads are plain data (`AshTypescript.Manifest.PlainData`), at any depth, through NewTypes and declared `custom_types` | Declare a typed map built from the record (`%{email: user.email}` with `fields: [email: [type: :string]]`), or a typed map argument (resource input goes through an RPC action); a field per union variant (all `allow_nil?: true`); a fixed depth for recursion |
| "config :ash_typescript, :warn_on_missing_channel_returns is no longer read" | Removed toggle still set | Remove it: a publication without `returns` is a compile error now |
| "not `public?`" error on RPC action | Action has `public? false` | Set `public? true` on the action or remove it from `typescript_rpc` |
| "not `public?`" error on read_action | `read_action` has `public? false` | Set `public? true` on the read action |
| "not `public?`" error on relationship read action | Relationship destination's read action has `public? false` | Set `public? true` on the destination's read action |
| Other runtime error types (`invalid_union_input`, `invalid_query_opts`, …) | Emitted by ash_rpc | [troubleshooting.md](agent-docs/troubleshooting.md) (Runtime errors) |

## RPC Resource Warnings

AshTypescript provides compile-time warnings for potential RPC configuration issues:

### Warning: Resources with Extension but Not in RPC Config
**Message:** `⚠️  Found resources with AshTypescript.Resource extension but not listed in any domain's typescript_rpc block`

**Cause:** Resource has `AshTypescript.Resource` extension but isn't configured in any `typescript_rpc` block

**Solutions:**
- Add resource to a domain's `typescript_rpc` block, OR
- Remove `AshTypescript.Resource` extension if not needed, OR
- Disable warning: `config :ash_typescript, warn_on_missing_rpc_config: false`

### Warning: Non-RPC Resources Referenced by RPC Resources
**Message:** `⚠️  Found non-RPC resources referenced by RPC resources`

**Cause:** RPC resource references another resource (in an attribute, calculation, aggregate, or relationship — directly or transitively) that isn't itself configured as RPC. The warning lists each referencer as `Referenced by: - <Resource> (relationship :name)` where attribution is available.

**Solutions:**
- Add referenced resource to `typescript_rpc` block if it should be accessible, OR
- Leave as-is if resource is intentionally internal-only, OR
- Disable warning: `config :ash_typescript, warn_on_non_rpc_references: false`

### Typed Channel Warnings

One additional compile-time warning covers typed channels (enabled by default):

- `config :ash_typescript, warn_on_non_public_publications: false` — silences warnings about publications that are not `public?`

### Unlisted Typed Module Warning

`mix ash_typescript.codegen` warns about every typed controller (with routes) or typed channel (with publications) in the app's modules (`Application.spec(otp_app, :modules)`) that has nothing in the manifest. Built by `TypeDiscovery.build_unlisted_typed_modules_warning/3`, printed to stderr by the Orchestrator. Silence with `config :ash_typescript, warn_on_unlisted_typed_modules: false`. This repo's own codegen reports the intentionally unlisted fixtures `StaticTopicChannel` and `PublicationFixtures.FeedChannel`.

**Note:** All of these warnings can be independently configured. See [Configuration Reference](documentation/reference/configuration.md#rpc-resource-warnings) for details.

## Typed Controller Configuration

For the controllers listed in the manifest module's `typed_controllers:` option, `mix ash_typescript.codegen` generates typed TypeScript route helpers alongside RPC types.

**Configuration:**
```elixir
# lib/my_app/ash_typescript_manifest.ex
use AshTypescript.Manifest, otp_app: :my_app, typed_controllers: [MyApp.Session]

config :ash_typescript,
  router: MyAppWeb.Router,                    # Phoenix router for path introspection
  routes_output_file: "assets/js/routes.ts",  # Output file for route helpers
  typed_controller_mode: :full,               # :full (default) or :paths_only
  typed_controller_base_path: ""              # Base URL prefix (string or {:runtime_expr, "..."})
```

**Modes:** `:full` generates path helpers + typed fetch functions for mutations. `:paths_only` generates only path helpers.

**Base path:** When set (e.g., `"https://api.example.com"` or `{:runtime_expr, "AppConfig.getBasePath()"}`), all generated route URLs are prefixed with `_basePath`. Uses the same `{:runtime_expr, "..."}` pattern as RPC endpoints.

**Implementation:** `lib/ash_typescript.ex` (`router/0`, `routes_output_file/0`, `typed_controller_mode/0`, `typed_controller_base_path/0`) + `lib/mix/tasks/ash_typescript.codegen.ex` + `lib/ash_typescript/typed_controller/`

## Typed Channel Configuration

For the channels listed in the manifest module's `typed_channels:` option, when `typed_channels_output_file` is configured, `mix ash_typescript.codegen` generates typed TypeScript event subscription helpers alongside RPC types.

**Configuration:**
```elixir
# lib/my_app/ash_typescript_manifest.ex
use AshTypescript.Manifest, otp_app: :my_app, typed_channels: [MyApp.OrgChannel]

config :ash_typescript,
  typed_channels_output_file: "assets/js/ash_typed_channels.ts"  # Output file for channel functions
```

Channel types (branded types, payload aliases, event maps) are appended to `ash_types.ts`. Channel functions (factory, subscription helpers) go into the separate `typed_channels_output_file`.

**Implementation:** `lib/ash_typescript.ex` (`typed_channels_output_file/0`) + `lib/ash_typescript/typed_channel/` + `lib/ash_typescript/codegen/orchestrator.ex`

## JSON Manifest (Machine-Readable)

When `json_manifest_file` is configured, `mix ash_typescript.codegen` generates a machine-readable JSON manifest alongside the TypeScript output. This manifest contains structured metadata about every RPC action (function names, types, pagination, variants) and typed controller routes, enabling third-party packages to build typed wrappers (e.g., TanStack Query integrations) without coupling to ash_typescript internals.

**Configuration:**
```elixir
config :ash_typescript,
  json_manifest_file: "assets/js/ash_rpc_manifest.json",
  json_manifest_filename_format: :relative  # :relative (default) | :absolute | :basename
```

- `json_manifest_filename_format` controls the `filename` field in each `files` entry. `importPath` (no `.ts`, for TypeScript imports) is always relative to the manifest.
- The manifest includes a `"version": "1.0"` field using semver for consumer compatibility detection.
- The manifest is written independently of other file changes — it's always generated if the file doesn't exist or content changed.

**Implementation:** `lib/ash_typescript/rpc.ex` (`json_manifest_file/0`, `json_manifest_filename_format/0`) + `lib/ash_typescript/rpc/codegen/json_manifest_generator.ex` + `lib/mix/tasks/ash_typescript.codegen.ex`

## Always Regenerate Mode

When `config :ash_typescript, always_regenerate: true` is set, `mix ash_typescript.codegen --dev --check` writes files directly instead of raising `Ash.Error.Framework.PendingCodegen`. `AshPhoenix.Plug.CheckCodegenStatus` passes `--dev --check` automatically, so this avoids the stale codegen error page and regenerates files on every development request; plain `--check` (CI) still raises.

**Configuration:** `config :ash_typescript, always_regenerate: true` (default: `false`)
**Implementation:** `lib/ash_typescript.ex` (`always_regenerate?/0`) + `lib/mix/tasks/ash_typescript.codegen.ex`

## Testing Workflow

```bash
mix test.codegen                     # Generate types
cd test/ts && npm run compileGenerated # Validate compilation
npm run compileGeneratedRoutes       # Validate generated route helpers
npm run compileGeneratedTypedChannels # Validate generated typed channels
npm run compileShouldPass            # Test valid patterns (type-level)
npm run compileShouldFail            # Test invalid patterns fail (type-level)
npm run testZod                      # Run generated Zod schemas at runtime
npm run testValibot                  # Run generated Valibot schemas at runtime
mix test                             # Run Elixir tests (do NOT prefix with MIX_ENV=test)
```

## Safety Checklist

- ✅ Always validate TypeScript compilation after changes
- ✅ Test both valid and invalid usage patterns
- ✅ Use test environment for all AshTypescript commands
- ✅ Write proper tests for debugging (no one-off shell commands)
- ✅ Check [architecture-decisions.md](agent-docs/architecture-decisions.md) for context on current patterns

---
**🎯 Primary Goal**: Generate type-safe TypeScript clients from Ash resources with full feature support and optimal developer experience.

<!-- usage-rules-start -->
<!-- ash-start -->
## ash usage
_A declarative, extensible framework for building Elixir applications._

@deps/ash/usage-rules.md
<!-- ash-end -->
<!-- ash:actions-start -->
## ash:actions usage
@deps/ash/usage-rules/actions.md
<!-- ash:actions-end -->
<!-- ash:aggregates-start -->
## ash:aggregates usage
@deps/ash/usage-rules/aggregates.md
<!-- ash:aggregates-end -->
<!-- ash:authorization-start -->
## ash:authorization usage
@deps/ash/usage-rules/authorization.md
<!-- ash:authorization-end -->
<!-- ash:calculations-start -->
## ash:calculations usage
@deps/ash/usage-rules/calculations.md
<!-- ash:calculations-end -->
<!-- ash:code_interfaces-start -->
## ash:code_interfaces usage
@deps/ash/usage-rules/code_interfaces.md
<!-- ash:code_interfaces-end -->
<!-- ash:code_structure-start -->
## ash:code_structure usage
@deps/ash/usage-rules/code_structure.md
<!-- ash:code_structure-end -->
<!-- ash:data_layers-start -->
## ash:data_layers usage
@deps/ash/usage-rules/data_layers.md
<!-- ash:data_layers-end -->
<!-- ash:exist_expressions-start -->
## ash:exist_expressions usage
@deps/ash/usage-rules/exist_expressions.md
<!-- ash:exist_expressions-end -->
<!-- ash:query_filter-start -->
## ash:query_filter usage
@deps/ash/usage-rules/query_filter.md
<!-- ash:query_filter-end -->
<!-- ash:querying_data-start -->
## ash:querying_data usage
@deps/ash/usage-rules/querying_data.md
<!-- ash:querying_data-end -->
<!-- ash:relationships-start -->
## ash:relationships usage
@deps/ash/usage-rules/relationships.md
<!-- ash:relationships-end -->
<!-- ash:signals-start -->
## ash:signals usage
@deps/ash/usage-rules/signals.md
<!-- ash:signals-end -->
<!-- ash:temporal-start -->
## ash:temporal usage
@deps/ash/usage-rules/temporal.md
<!-- ash:temporal-end -->
<!-- ash:testing-start -->
## ash:testing usage
@deps/ash/usage-rules/testing.md
<!-- ash:testing-end -->
<!-- spark-start -->
## spark usage
_Generic tooling for building DSLs_

@deps/spark/usage-rules.md
<!-- spark-end -->
<!-- igniter-start -->
## igniter usage
_A code generation and project patching framework_

@deps/igniter/usage-rules.md
<!-- igniter-end -->
<!-- ex_check-start -->
## ex_check usage
_ex_check_

@deps/ex_check/usage-rules.md
<!-- ex_check-end -->
<!-- usage_rules-start -->
## usage_rules usage
_A config-driven dev tool for Elixir projects to manage AGENTS.md files and agent skills from dependencies_

@deps/usage_rules/usage-rules.md
<!-- usage_rules-end -->
<!-- usage_rules:elixir-start -->
## usage_rules:elixir usage
@deps/usage_rules/usage-rules/elixir.md
<!-- usage_rules:elixir-end -->
<!-- usage-rules-end -->
