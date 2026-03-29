<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Configuration Reference

This document provides a comprehensive reference for all AshTypescript configuration options.

## Application Configuration

Configure AshTypescript in your `config/config.exs` file:

```elixir
# config/config.exs
config :ash_typescript,
  # File generation (multi-file architecture)
  output_file: "assets/js/ash_rpc.ts",
  types_output_file: nil,             # Auto-derives as ash_types.ts in output_file dir
  zod_output_file: nil,               # Auto-derives as ash_zod.ts in output_file dir
  valibot_output_file: nil,           # Auto-derives as ash_valibot.ts in output_file dir

  # RPC endpoints
  run_endpoint: "/rpc/run",
  validate_endpoint: "/rpc/validate",

  # Field formatting
  input_field_formatter: :camel_case,
  output_field_formatter: :camel_case,

  # Multitenancy
  require_tenant_parameters: false,

  # Validation schema generation
  generate_zod_schemas: false,
  zod_import_path: "zod",
  zod_schema_suffix: "ZodSchema",
  generate_valibot_schemas: false,
  valibot_import_path: "valibot",
  valibot_schema_suffix: "ValibotSchema",

  # Validation functions
  generate_validation_functions: false,

  # Phoenix channel-based RPC actions
  generate_phx_channel_rpc_actions: false,
  phoenix_import_path: "phoenix",

  # Custom type imports
  import_into_generated: [],

  # Type mapping overrides
  type_mapping_overrides: [],

  # TypeScript type for untyped maps
  untyped_map_type: "Record<string, any>",

  # RPC resource warnings
  warn_on_missing_rpc_config: true,
  warn_on_non_rpc_references: true,

  # RPC namespace files
  enable_namespace_files: false,      # Generate separate files for namespaced RPC actions
  namespace_output_dir: nil,          # Directory for RPC namespace files (defaults to output_file dir)

  # Typed channel event subscriptions
  typed_channels: [],
  typed_channels_output_file: nil,

  # Typed controllers
  typed_controllers: [],
  router: nil,
  routes_output_file: nil,
  typed_controller_mode: :full,
  typed_controller_path_params_style: :object,
  typed_controller_base_path: "",             # Base URL prefix for all generated route URLs
  enable_controller_namespace_files: false,  # Generate separate files for namespaced routes
  controller_namespace_output_dir: nil,       # Directory for controller namespace files

  # Typed controller lifecycle hooks
  typed_controller_before_request_hook: nil,
  typed_controller_after_request_hook: nil,
  typed_controller_hook_context_type: "Record<string, any>",
  typed_controller_import_into_generated: [],

  # Typed controller error handling
  typed_controller_error_handler: nil,
  typed_controller_show_raised_errors: false,

  # Dev codegen behavior
  always_regenerate: false,

  # Get action behavior
  not_found_error?: true,

  # Developer experience - JSDoc
  add_ash_internals_to_jsdoc: false,
  source_path_prefix: nil,

  # Developer experience - Manifest
  manifest_file: nil,
  add_ash_internals_to_manifest: false
```

## Multi-File Output

AshTypescript generates multiple TypeScript files, each with a specific responsibility:

| File | Config Key | Default | Contents |
|------|-----------|---------|----------|
| RPC functions | `output_file` | `assets/js/ash_rpc.ts` | RPC functions, hook types, helpers |
| Shared types | `types_output_file` | Auto-derived as `ash_types.ts` | Type aliases, resource schemas, filter types, utility types |
| Shared Zod schemas | `zod_output_file` | Auto-derived as `ash_zod.ts` | Zod schemas for all resources (when `generate_zod_schemas: true`) |
| Shared Valibot schemas | `valibot_output_file` | Auto-derived as `ash_valibot.ts` | Valibot schemas for all resources (when `generate_valibot_schemas: true`) |
| Route helpers | `routes_output_file` | `nil` (disabled) | Path helpers, typed fetch functions, controller input types |
| Typed channel functions | `typed_channels_output_file` | `nil` (disabled) | Channel factory, subscription helpers, cleanup functions |
| RPC namespace re-exports | `namespace_output_dir` | Same dir as `output_file` | Per-namespace re-export files (when `enable_namespace_files: true`) |
| Controller namespace re-exports | `controller_namespace_output_dir` | Same dir as `routes_output_file` | Per-namespace re-export files (when `enable_controller_namespace_files: true`) |

`types_output_file`, `zod_output_file`, and `valibot_output_file` auto-derive from the `output_file` directory — set `output_file` and the others follow. Override individually if needed.

## Quick Reference

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `output_file` | `string` | `"assets/js/ash_rpc.ts"` | Path where generated TypeScript code will be written |
| `types_output_file` | `string \| nil` | `nil` | Path for shared types file (auto-derives from `output_file` dir as `ash_types.ts`) |
| `zod_output_file` | `string \| nil` | `nil` | Path for shared Zod schemas file (auto-derives from `output_file` dir as `ash_zod.ts`) |
| `valibot_output_file` | `string \| nil` | `nil` | Path for shared Valibot schemas file (auto-derives from `output_file` dir as `ash_valibot.ts`) |
| `run_endpoint` | `string \| {:runtime_expr, string}` | `"/rpc/run"` | Endpoint for executing RPC actions |
| `validate_endpoint` | `string \| {:runtime_expr, string}` | `"/rpc/validate"` | Endpoint for validating RPC requests |
| `input_field_formatter` | `:camel_case \| :snake_case` | `:camel_case` | How to format field names in request inputs |
| `output_field_formatter` | `:camel_case \| :snake_case` | `:camel_case` | How to format field names in response outputs |
| `require_tenant_parameters` | `boolean` | `false` | Whether to require tenant parameters in RPC calls |
| `generate_zod_schemas` | `boolean` | `false` | Whether to generate Zod validation schemas |
| `zod_import_path` | `string` | `"zod"` | Import path for Zod library |
| `zod_schema_suffix` | `string` | `"ZodSchema"` | Suffix for generated Zod schema names |
| `generate_valibot_schemas` | `boolean` | `false` | Whether to generate Valibot validation schemas |
| `valibot_import_path` | `string` | `"valibot"` | Import path for Valibot library |
| `valibot_schema_suffix` | `string` | `"ValibotSchema"` | Suffix for generated Valibot schema names |
| `generate_validation_functions` | `boolean` | `false` | Whether to generate form validation functions |
| `generate_phx_channel_rpc_actions` | `boolean` | `false` | Whether to generate Phoenix channel-based RPC functions |
| `phoenix_import_path` | `string` | `"phoenix"` | Import path for Phoenix library |
| `import_into_generated` | `list` | `[]` | List of custom modules to import |
| `type_mapping_overrides` | `list` | `[]` | Override TypeScript types for Ash types |
| `untyped_map_type` | `string` | `"Record<string, any>"` | TypeScript type for untyped maps |
| `warn_on_missing_rpc_config` | `boolean` | `true` | Warn about resources with extension not in RPC config |
| `warn_on_non_rpc_references` | `boolean` | `true` | Warn about non-RPC resources referenced by RPC resources |
| `enable_namespace_files` | `boolean` | `false` | Generate separate files for namespaced RPC actions |
| `namespace_output_dir` | `string \| nil` | `nil` | Directory for RPC namespace files (defaults to `output_file` dir) |
| `typed_channels` | `list(module)` | `[]` | TypedChannel modules to generate event subscription helpers for |
| `typed_channels_output_file` | `string \| nil` | `nil` | Output file for typed channel functions (when `nil`, generation is skipped) |
| `typed_controllers` | `list(module)` | `[]` | TypedController modules to generate route helpers for |
| `router` | `module \| nil` | `nil` | Phoenix router module for path introspection |
| `routes_output_file` | `string \| nil` | `nil` | Output file path for generated route helpers |
| `typed_controller_mode` | `:full \| :paths_only` | `:full` | Generation mode: `:full` generates path helpers + fetch functions, `:paths_only` generates only path helpers |
| `typed_controller_path_params_style` | `:object \| :args` | `:object` | Path parameter style in generated functions |
| `typed_controller_base_path` | `string \| {:runtime_expr, string}` | `""` | Base URL prefix for all generated route URLs |
| `enable_controller_namespace_files` | `boolean` | `false` | Generate separate files for namespaced controller routes |
| `controller_namespace_output_dir` | `string \| nil` | `nil` | Directory for controller namespace files (defaults to `routes_output_file` dir) |
| `typed_controller_before_request_hook` | `string \| nil` | `nil` | Function called before typed controller requests |
| `typed_controller_after_request_hook` | `string \| nil` | `nil` | Function called after typed controller requests |
| `typed_controller_hook_context_type` | `string` | `"Record<string, any>"` | TypeScript type for typed controller hook context |
| `typed_controller_import_into_generated` | `list(map)` | `[]` | Custom imports for generated routes file |
| `typed_controller_error_handler` | `mfa \| module \| nil` | `nil` | Custom error transformation handler |
| `typed_controller_show_raised_errors` | `boolean` | `false` | Show exception messages in 500 responses |
| `always_regenerate` | `boolean` | `false` | Skip diff check and always write generated files |
| `not_found_error?` | `boolean` | `true` | Global default: `true` returns error on not found, `false` returns null |
| `add_ash_internals_to_jsdoc` | `boolean` | `false` | Show Ash resource/action details in JSDoc |
| `source_path_prefix` | `string \| nil` | `nil` | Prefix for source file paths (monorepos) |
| `manifest_file` | `string \| nil` | `nil` | Path to generate Markdown manifest |
| `add_ash_internals_to_manifest` | `boolean` | `false` | Show Ash details in manifest |

## Lifecycle Hook Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `rpc_action_before_request_hook` | `string \| nil` | `nil` | Function called before RPC action requests |
| `rpc_action_after_request_hook` | `string \| nil` | `nil` | Function called after RPC action requests |
| `rpc_validation_before_request_hook` | `string \| nil` | `nil` | Function called before validation requests |
| `rpc_validation_after_request_hook` | `string \| nil` | `nil` | Function called after validation requests |
| `rpc_action_hook_context_type` | `string` | `"Record<string, any>"` | TypeScript type for action hook context |
| `rpc_validation_hook_context_type` | `string` | `"Record<string, any>"` | TypeScript type for validation hook context |
| `rpc_action_before_channel_push_hook` | `string \| nil` | `nil` | Function called before channel push for actions |
| `rpc_action_after_channel_response_hook` | `string \| nil` | `nil` | Function called after channel response for actions |
| `rpc_validation_before_channel_push_hook` | `string \| nil` | `nil` | Function called before channel push for validations |
| `rpc_validation_after_channel_response_hook` | `string \| nil` | `nil` | Function called after channel response for validations |
| `rpc_action_channel_hook_context_type` | `string` | `"Record<string, any>"` | TypeScript type for channel action hook context |
| `rpc_validation_channel_hook_context_type` | `string` | `"Record<string, any>"` | TypeScript type for channel validation hook context |
| `typed_controller_before_request_hook` | `string \| nil` | `nil` | Function called before typed controller requests |
| `typed_controller_after_request_hook` | `string \| nil` | `nil` | Function called after typed controller requests |
| `typed_controller_hook_context_type` | `string` | `"Record<string, any>"` | TypeScript type for typed controller hook context |

See [Lifecycle Hooks](../features/lifecycle-hooks.md) and [Typed Controllers](../guides/typed-controllers.md#lifecycle-hooks) for complete documentation.

## Domain Configuration

Configure RPC actions and typed queries in your domain modules:

```elixir
defmodule MyApp.Domain do
  use Ash.Domain, extensions: [AshTypescript.Rpc]

  typescript_rpc do
    resource MyApp.Todo do
      # Standard CRUD actions
      rpc_action :list_todos, :read
      rpc_action :get_todo, :get
      rpc_action :create_todo, :create
      rpc_action :update_todo, :update
      rpc_action :destroy_todo, :destroy

      # RPC action options
      rpc_action :list_limited, :read, allowed_loads: [:user]
      rpc_action :list_no_filter, :read, enable_filter?: false
      rpc_action :list_no_sort, :read, enable_sort?: false

      # Typed queries for SSR
      typed_query :dashboard_todos, :read do
        ts_result_type_name "DashboardTodo"
        ts_fields_const_name "dashboardTodoFields"
        fields [:id, :title, :priority, %{user: [:name]}]
      end
    end
  end
end
```

## RPC Action Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `allowed_loads` | `list(atom \| keyword)` | `nil` | Whitelist of loadable fields |
| `denied_loads` | `list(atom \| keyword)` | `nil` | Blacklist of loadable fields |
| `enable_filter?` | `boolean` | `true` | Enable client-side filtering |
| `enable_sort?` | `boolean` | `true` | Enable client-side sorting |
| `get?` | `boolean` | `false` | Return single record |
| `get_by` | `list(atom)` | `nil` | Fields for single-record lookup |
| `not_found_error?` | `boolean` | `nil` | Override global not_found_error? |
| `identities` | `list(atom)` | `[:_primary_key]` | Allowed identity lookups |
| `show_metadata` | `list(atom) \| false \| nil` | `nil` | Metadata fields to expose |
| `metadata_field_names` | `keyword` | `nil` | Metadata field name mappings |

See [RPC Action Options](../features/rpc-action-options.md) for complete documentation.

## Dynamic RPC Endpoints

For separate frontend projects, use runtime expressions:

```elixir
config :ash_typescript,
  # Environment variables
  run_endpoint: {:runtime_expr, "process.env.RPC_RUN_ENDPOINT || '/rpc/run'"},

  # Vite environment variables
  # run_endpoint: {:runtime_expr, "import.meta.env.VITE_RPC_RUN_ENDPOINT || '/rpc/run'"},

  # Custom functions
  # run_endpoint: {:runtime_expr, "MyAppConfig.getRunEndpoint()"}
```

## RPC Resource Warnings

AshTypescript provides compile-time warnings for configuration issues:

### Missing RPC Configuration Warning

Appears when resources have `AshTypescript.Resource` extension but are not in any `typescript_rpc` block.

### Non-RPC References Warning

Appears when RPC resources reference other resources that are not configured as RPC resources.

**To disable warnings:**

```elixir
config :ash_typescript,
  warn_on_missing_rpc_config: false,
  warn_on_non_rpc_references: false
```

## Always Regenerate Mode

By default, `mix ash_typescript.codegen --check` compares the generated output against existing files and raises `Ash.Error.Framework.PendingCodegen` if they differ. This is useful for CI but in development—especially when using `AshPhoenix.Plug.CheckCodegenStatus`—you may want to skip the diff check and always write the generated files.

```elixir
# config/dev.exs
config :ash_typescript, always_regenerate: true
```

When enabled, `--check` mode will write files directly instead of comparing, so the `PendingCodegen` error page is never shown during development.

## Typed Channel Configuration

Configure typed channels to generate TypeScript event subscription helpers from Ash PubSub publications. Both `typed_channels` and `typed_channels_output_file` must be configured for generation to run.

```elixir
config :ash_typescript,
  typed_channels: [MyApp.OrgChannel, MyApp.ActivityChannel],
  typed_channels_output_file: "assets/js/ash_typed_channels.ts"
```

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `typed_channels` | `list(module)` | `[]` | Modules using `AshTypescript.TypedChannel` |
| `typed_channels_output_file` | `string \| nil` | `nil` | Output file for channel functions (when `nil`, generation is skipped) |

Channel types (branded types, payload aliases, event maps) are appended to the shared types file (`ash_types.ts`). Channel functions (factory, subscription helpers) go into `typed_channels_output_file` and import their types from `ash_types.ts`.

See [Typed Channels](../features/typed-channels.md) for complete documentation.

## Typed Controller Configuration

Configure typed controllers to generate TypeScript path helpers and typed fetch functions for Phoenix controller routes. All three settings (`typed_controllers`, `router`, `routes_output_file`) must be configured for route generation to run.

```elixir
config :ash_typescript,
  # List of TypedController modules
  typed_controllers: [MyApp.Session],

  # Phoenix router for path introspection
  router: MyAppWeb.Router,

  # Output file for generated route helpers
  routes_output_file: "assets/js/routes.ts",

  # Generation mode (optional)
  typed_controller_mode: :full,              # :full (default) or :paths_only
  typed_controller_path_params_style: :object, # :object (default) or :args
  typed_controller_base_path: "",            # Base URL prefix (string or {:runtime_expr, "..."})

  # Namespace files (optional)
  enable_controller_namespace_files: false,  # Generate separate files per namespace
  controller_namespace_output_dir: nil,      # Directory for namespace files (defaults to routes_output_file dir)

  # Lifecycle hooks (optional)
  typed_controller_before_request_hook: "RouteHooks.beforeRequest",
  typed_controller_after_request_hook: "RouteHooks.afterRequest",
  typed_controller_hook_context_type: "RouteHooks.RouteHookContext",
  typed_controller_import_into_generated: [
    %{import_name: "RouteHooks", file: "./routeHooks"}
  ],

  # Error handling (optional)
  typed_controller_error_handler: {MyApp.ErrorHandler, :handle, []},
  typed_controller_show_raised_errors: false  # true only in dev
```

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `typed_controllers` | `list(module)` | `[]` | Modules using `AshTypescript.TypedController` |
| `router` | `module` | `nil` | Phoenix router for path introspection |
| `routes_output_file` | `string` | `nil` | Output file path (when `nil`, generation is skipped) |
| `typed_controller_mode` | `:full \| :paths_only` | `:full` | `:full` generates path helpers + fetch functions; `:paths_only` generates only path helpers |
| `typed_controller_path_params_style` | `:object \| :args` | `:object` | Path parameter style in generated TypeScript |
| `typed_controller_base_path` | `string \| {:runtime_expr, string}` | `""` | Base URL prefix for all generated route URLs |
| `enable_controller_namespace_files` | `boolean` | `false` | Generate separate files for namespaced routes |
| `controller_namespace_output_dir` | `string \| nil` | `nil` | Directory for namespace files (defaults to `routes_output_file` dir) |
| `typed_controller_before_request_hook` | `string \| nil` | `nil` | Function called before typed controller requests |
| `typed_controller_after_request_hook` | `string \| nil` | `nil` | Function called after typed controller requests |
| `typed_controller_hook_context_type` | `string` | `"Record<string, any>"` | TypeScript type for hook context |
| `typed_controller_import_into_generated` | `list(map)` | `[]` | Custom imports (`%{import_name: "Name", file: "./path"}`) |
| `typed_controller_error_handler` | `mfa \| module \| nil` | `nil` | Custom error transformation handler |
| `typed_controller_show_raised_errors` | `boolean` | `false` | Show exception messages in 500 responses |

See [Typed Controllers](../guides/typed-controllers.md) for complete documentation.

## Detailed Documentation

For in-depth configuration guides, see:

- [Custom Types](../advanced/custom-types.md) - Custom Ash types with TypeScript integration
- [Field Name Mapping](../advanced/field-name-mapping.md) - Mapping invalid field names
- [Developer Experience](../features/developer-experience.md) - Namespaces, JSDoc, and manifest generation
- [Lifecycle Hooks](../features/lifecycle-hooks.md) - HTTP and channel lifecycle hooks
- [Phoenix Channels](../features/phoenix-channels.md) - Channel-based RPC configuration
- [Typed Channels](../features/typed-channels.md) - Typed event subscriptions from PubSub
- [Multitenancy](../features/multitenancy.md) - Tenant parameter configuration
- [Form Validation](../guides/form-validation.md) - Zod and Valibot schema configuration
- [Typed Controllers](../guides/typed-controllers.md) - Controller route helpers

## See Also

- [Installation](../getting-started/installation.md) - Initial setup
- [Mix Tasks Reference](mix-tasks.md) - Code generation commands
- [Troubleshooting Reference](troubleshooting.md) - Common problems and solutions
