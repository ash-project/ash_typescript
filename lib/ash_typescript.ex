# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript do
  @moduledoc false

  @doc """
  Gets the type mapping overrides from application configuration.

  This allows users to map Ash types to specific TypeScript types when they can't
  modify the type module itself (e.g., for types from dependencies).

  ## Configuration

      config :ash_typescript,
        type_mapping_overrides: [
          {AshUUID.UUID, "string"},
          {SomeOtherType, "CustomTSType"}
        ]

  ## Returns
  A keyword list of {type_module, typescript_type_string} tuples, or an empty list if not configured.
  """
  def type_mapping_overrides do
    Application.get_env(:ash_typescript, :type_mapping_overrides, [])
  end

  @doc """
  Gets the TypeScript type to use for untyped maps from application configuration.

  This controls the TypeScript type generated for Ash.Type.Map, Ash.Type.Keyword,
  Ash.Type.Tuple, and unconstrained Ash.Type.Struct types that don't have field
  definitions. The default is `"Record<string, any>"`, but users can configure it
  to use stricter types like `"Record<string, unknown>"` for better type safety.

  ## Configuration

      # Default - allows any value type
      config :ash_typescript, untyped_map_type: "Record<string, any>"

      # Stricter - requires type checking before use
      config :ash_typescript, untyped_map_type: "Record<string, unknown>"

      # Custom - use your own type definition
      config :ash_typescript, untyped_map_type: "MyCustomMapType"

  ## Returns
  A string representing the TypeScript type to use, defaulting to `"Record<string, any>"`.
  """
  def untyped_map_type do
    Application.get_env(:ash_typescript, :untyped_map_type, "Record<string, any>")
  end

  @doc """
  Gets the beforeRequest hook function name for RPC actions from application configuration.

  This hook is called before making the HTTP request for run actions, allowing you to
  modify the config (add headers, set fetchOptions, etc.). The hook receives the config
  and hookCtx, and must return the modified config.

  ## Configuration

      config :ash_typescript,
        rpc_action_before_request_hook: "myHooks.beforeRequest"

  ## Returns
  A string representing the hook function name, or `nil` if not configured.
  """
  def rpc_action_before_request_hook do
    Application.get_env(:ash_typescript, :rpc_action_before_request_hook)
  end

  @doc """
  Gets the afterRequest hook function name for RPC actions from application configuration.

  This hook is called after the HTTP request completes for run actions, regardless of
  success or failure. The hook receives the Response object, parsed result (or nil if
  response.ok is false), config, and hookCtx. Used for logging, telemetry, timing, etc.

  ## Configuration

      config :ash_typescript,
        rpc_action_after_request_hook: "myHooks.afterRequest"

  ## Returns
  A string representing the hook function name, or `nil` if not configured.
  """
  def rpc_action_after_request_hook do
    Application.get_env(:ash_typescript, :rpc_action_after_request_hook)
  end

  @doc """
  Gets the beforeRequest hook function name for RPC validations from application configuration.

  This hook is called before making the HTTP request for validation actions, allowing you
  to modify the config (add headers, set fetchOptions, etc.). The hook receives the config
  and hookCtx, and must return the modified config.

  ## Configuration

      config :ash_typescript,
        rpc_validation_before_request_hook: "myHooks.beforeValidation"

  ## Returns
  A string representing the hook function name, or `nil` if not configured.
  """
  def rpc_validation_before_request_hook do
    Application.get_env(:ash_typescript, :rpc_validation_before_request_hook)
  end

  @doc """
  Gets the afterRequest hook function name for RPC validations from application configuration.

  This hook is called after the HTTP request completes for validation actions, regardless
  of success or failure. The hook receives the Response object, parsed result (or nil if
  response.ok is false), config, and hookCtx. Used for logging, telemetry, timing, etc.

  ## Configuration

      config :ash_typescript,
        rpc_validation_after_request_hook: "myHooks.afterValidation"

  ## Returns
  A string representing the hook function name, or `nil` if not configured.
  """
  def rpc_validation_after_request_hook do
    Application.get_env(:ash_typescript, :rpc_validation_after_request_hook)
  end

  @doc """
  Gets the TypeScript type for RPC action hook context from application configuration.

  This controls the type of the optional `hookCtx` field in RPC action configs. The default
  is `"Record<string, any>"`, but you can configure it to use a custom type imported via
  `import_into_generated`.

  ## Configuration

      config :ash_typescript,
        rpc_action_hook_context_type: "MyCustomHookContext",
        import_into_generated: [
          %{import_name: "MyTypes", file: "./myTypes"}
        ]

  ## Returns
  A string representing the TypeScript type to use, defaulting to `"Record<string, any>"`.
  """
  def rpc_action_hook_context_type do
    Application.get_env(:ash_typescript, :rpc_action_hook_context_type, "Record<string, any>")
  end

  @doc """
  Gets the TypeScript type for RPC validation hook context from application configuration.

  This controls the type of the optional `hookCtx` field in RPC validation configs. The default
  is `"Record<string, any>"`, but you can configure it to use a custom type imported via
  `import_into_generated`.

  ## Configuration

      config :ash_typescript,
        rpc_validation_hook_context_type: "MyCustomValidationContext",
        import_into_generated: [
          %{import_name: "MyTypes", file: "./myTypes"}
        ]

  ## Returns
  A string representing the TypeScript type to use, defaulting to `"Record<string, any>"`.
  """
  def rpc_validation_hook_context_type do
    Application.get_env(:ash_typescript, :rpc_validation_hook_context_type, "Record<string, any>")
  end

  @doc """
  Gets the beforeChannelPush hook function name for RPC actions from application configuration.

  This hook is called before pushing a message to a Phoenix Channel for run actions, allowing
  you to modify the config (add timeout, etc.). The hook receives the config and must return
  the modified config.

  ## Configuration

      config :ash_typescript,
        rpc_action_before_channel_push_hook: "myChannelHooks.beforeChannelPush"

  ## Returns
  A string representing the hook function name, or `nil` if not configured.
  """
  def rpc_action_before_channel_push_hook do
    Application.get_env(:ash_typescript, :rpc_action_before_channel_push_hook)
  end

  @doc """
  Gets the afterChannelResponse hook function name for RPC actions from application configuration.

  This hook is called after receiving a response from a Phoenix Channel for run actions,
  regardless of the response type (ok, error, or timeout). The hook receives the response type,
  data, and config. Used for logging, telemetry, timing, etc.

  ## Configuration

      config :ash_typescript,
        rpc_action_after_channel_response_hook: "myChannelHooks.afterChannelResponse"

  ## Returns
  A string representing the hook function name, or `nil` if not configured.
  """
  def rpc_action_after_channel_response_hook do
    Application.get_env(:ash_typescript, :rpc_action_after_channel_response_hook)
  end

  @doc """
  Gets the beforeChannelPush hook function name for RPC validations from application configuration.

  This hook is called before pushing a message to a Phoenix Channel for validation actions,
  allowing you to modify the config (add timeout, etc.). The hook receives the config and must
  return the modified config.

  ## Configuration

      config :ash_typescript,
        rpc_validation_before_channel_push_hook: "myChannelHooks.beforeValidationChannelPush"

  ## Returns
  A string representing the hook function name, or `nil` if not configured.
  """
  def rpc_validation_before_channel_push_hook do
    Application.get_env(:ash_typescript, :rpc_validation_before_channel_push_hook)
  end

  @doc """
  Gets the afterChannelResponse hook function name for RPC validations from application configuration.

  This hook is called after receiving a response from a Phoenix Channel for validation actions,
  regardless of the response type (ok, error, or timeout). The hook receives the response type,
  data, and config. Used for logging, telemetry, timing, etc.

  ## Configuration

      config :ash_typescript,
        rpc_validation_after_channel_response_hook: "myChannelHooks.afterValidationChannelResponse"

  ## Returns
  A string representing the hook function name, or `nil` if not configured.
  """
  def rpc_validation_after_channel_response_hook do
    Application.get_env(:ash_typescript, :rpc_validation_after_channel_response_hook)
  end

  @doc """
  Gets the TypeScript type for RPC action channel hook context from application configuration.

  This controls the type of the optional `hookCtx` field in channel-based RPC action configs.
  The default is `"Record<string, any>"`, but you can configure it to use a custom type imported
  via `import_into_generated`.

  ## Configuration

      config :ash_typescript,
        rpc_action_channel_hook_context_type: "MyChannelHookContext",
        import_into_generated: [
          %{import_name: "MyTypes", file: "./myTypes"}
        ]

  ## Returns
  A string representing the TypeScript type to use, defaulting to `"Record<string, any>"`.
  """
  def rpc_action_channel_hook_context_type do
    Application.get_env(
      :ash_typescript,
      :rpc_action_channel_hook_context_type,
      "Record<string, any>"
    )
  end

  @doc """
  Gets the TypeScript type for RPC validation channel hook context from application configuration.

  This controls the type of the optional `hookCtx` field in channel-based RPC validation configs.
  The default is `"Record<string, any>"`, but you can configure it to use a custom type imported
  via `import_into_generated`.

  ## Configuration

      config :ash_typescript,
        rpc_validation_channel_hook_context_type: "MyValidationChannelHookContext",
        import_into_generated: [
          %{import_name: "MyTypes", file: "./myTypes"}
        ]

  ## Returns
  A string representing the TypeScript type to use, defaulting to `"Record<string, any>"`.
  """
  def rpc_validation_channel_hook_context_type do
    Application.get_env(
      :ash_typescript,
      :rpc_validation_channel_hook_context_type,
      "Record<string, any>"
    )
  end

  @doc """
  Gets whether to warn about resources with the AshTypescript.Resource extension
  that are not configured in any domain's typescript_rpc block.

  When enabled, during code generation, a warning will be displayed for any resource
  that has the AshTypescript.Resource extension but is not listed in any domain's
  typescript_rpc configuration block. These resources will not have TypeScript types
  generated.

  ## Configuration

      # Disable warnings (silent)
      config :ash_typescript, warn_on_missing_rpc_config: false

      # Enable warnings (default)
      config :ash_typescript, warn_on_missing_rpc_config: true

  ## Returns
  A boolean indicating whether to display warnings, defaulting to `true`.
  """
  def warn_on_missing_rpc_config? do
    Application.get_env(:ash_typescript, :warn_on_missing_rpc_config, true)
  end

  @doc """
  Gets whether to warn about non-RPC resources that are referenced by RPC resources.

  When enabled, a warning will be displayed for any non-RPC resource that is
  referenced in attributes, calculations, aggregates, or relationships of RPC
  resources (directly, or through other resources they reach). The warning
  lists the referencing resource and field/relationship for each reference,
  helping you decide whether the resource should be added to the RPC
  configuration.

  ## Configuration

      # Disable warnings (silent)
      config :ash_typescript, warn_on_non_rpc_references: false

      # Enable warnings (default)
      config :ash_typescript, warn_on_non_rpc_references: true

  ## Returns
  A boolean indicating whether to display warnings, defaulting to `true`.
  """
  def warn_on_non_rpc_references? do
    Application.get_env(:ash_typescript, :warn_on_non_rpc_references, true)
  end

  @doc """
  Gets whether to warn about typed channel publications that are not marked `public?: true`.

  When enabled, during typed channel verification, a warning is displayed for any
  publication referenced by a `typed_channel` whose `pub_sub` entry is not marked
  `public?: true`. Disable it if you intentionally publish non-public events.

  ## Configuration

      # Disable warnings (silent)
      config :ash_typescript, warn_on_non_public_publications: false

      # Enable warnings (default)
      config :ash_typescript, warn_on_non_public_publications: true

  ## Returns
  A boolean indicating whether to display warnings, defaulting to `true`.
  """
  def warn_on_non_public_publications? do
    Application.get_env(:ash_typescript, :warn_on_non_public_publications, true)
  end

  @doc """
  Gets whether to warn about typed channel publications that have no `returns` type.

  When enabled, during typed channel verification, a warning is displayed for any
  publication referenced by a `typed_channel` that has no `returns` set (whose
  TypeScript payload type therefore falls back to `unknown`). Disable it if the
  `unknown` payload is intentional.

  ## Configuration

      # Disable warnings (silent)
      config :ash_typescript, warn_on_missing_channel_returns: false

      # Enable warnings (default)
      config :ash_typescript, warn_on_missing_channel_returns: true

  ## Returns
  A boolean indicating whether to display warnings, defaulting to `true`.
  """
  def warn_on_missing_channel_returns? do
    Application.get_env(:ash_typescript, :warn_on_missing_channel_returns, true)
  end

  @doc """
  Gets whether to always regenerate TypeScript files instead of raising on pending codegen.

  When enabled, `--check` will write changed files instead of raising
  `Ash.Error.Framework.PendingCodegen`, but **only** when the `--dev` flag is also
  passed. `AshPhoenix.Plug.CheckCodegenStatus` passes `--dev --check` automatically,
  so this setting takes effect during development requests without affecting CI where
  `mix ash_typescript.codegen --check` is run without `--dev`.

  ## Configuration

      # Auto-regenerate in dev when triggered by CheckCodegenStatus plug
      config :ash_typescript, always_regenerate: true

      # Only raise on pending codegen (default)
      config :ash_typescript, always_regenerate: false

  ## Returns
  A boolean indicating whether to always regenerate, defaulting to `false`.
  """
  def always_regenerate? do
    Application.get_env(:ash_typescript, :always_regenerate, false)
  end

  @doc """
  Gets the configured Phoenix router module.

  Used to introspect actual URL paths for generated controller actions.

  ## Configuration

      config :ash_typescript,
        router: MyAppWeb.Router

  ## Returns
  The router module atom, or `nil` if not configured.
  """
  def router do
    Application.get_env(:ash_typescript, :router)
  end

  @doc """
  Gets the list of TypedController modules from application configuration.

  ## Configuration

      config :ash_typescript,
        typed_controllers: [MyApp.Session, MyApp.Admin]

  ## Returns
  A list of module atoms, or an empty list if not configured.
  """
  def typed_controllers do
    Application.get_env(:ash_typescript, :typed_controllers, [])
  end

  @doc """
  Gets the output file path for generated route helper TypeScript.

  `mix ash_typescript.codegen` generates typed route functions
  from modules using `AshTypescript.TypedController`.

  Auto-derives from `output_file` directory with default name `ash_routes.ts`.
  Falls back to `"assets/js/ash_routes.ts"` if `output_file` is also unset.

  ## Configuration

      config :ash_typescript,
        routes_output_file: "assets/js/routes.ts"

  ## Returns
  A string file path (always non-nil).
  """
  def routes_output_file do
    config_or_derive(:routes_output_file, "ash_routes.ts", "assets/js/ash_routes.ts")
  end

  @doc """
  Gets the base path to prefix all typed controller route URLs.

  When set, all generated path helpers and action function URLs will be prefixed
  with this value. Useful when the frontend calls a backend on a different domain.

  Accepts either:
  - A string: Embedded as a quoted literal (e.g. `"https://api.example.com"`)
  - A tuple `{:runtime_expr, "expression"}`: Embedded as a raw JS expression

  ## Configuration

      # Static base path
      config :ash_typescript,
        typed_controller_base_path: "https://api.example.com"

      # Runtime expression
      config :ash_typescript,
        typed_controller_base_path: {:runtime_expr, "AppConfig.getBasePath()"}

  ## Returns
  A string, a `{:runtime_expr, expr}` tuple, or `""` (default, no prefix).
  """
  def typed_controller_base_path do
    Application.get_env(:ash_typescript, :typed_controller_base_path, "")
  end

  @doc """
  Gets the typed controller generation mode.

  Controls what TypeScript code is generated for typed controller routes:
  - `:full` (default) — generates path helpers AND fetch-based action functions for mutation routes
  - `:paths_only` — generates only path helpers, no fetch action functions

  ## Example

      config :ash_typescript,
        typed_controller_mode: :paths_only

  ## Returns
  An atom, either `:full` or `:paths_only`.
  """
  def typed_controller_mode do
    Application.get_env(:ash_typescript, :typed_controller_mode, :full)
  end

  @doc """
  Gets the path params style for typed controller TypeScript generation.

  Controls how path parameters are represented in generated TypeScript functions:

  - `:object` (default) — all functions use `path: { param: Type }` object style
  - `:args` — all functions use flat positional `param: Type` arguments

  ## Example

      config :ash_typescript,
        typed_controller_path_params_style: :object

  ## Returns
  An atom, either `:object` or `:args`.
  """
  def typed_controller_path_params_style do
    Application.get_env(:ash_typescript, :typed_controller_path_params_style, :object)
  end

  @doc """
  Gets the beforeRequest hook function name for typed controller actions from application configuration.

  This hook is called before making the HTTP request for typed controller mutation actions,
  allowing you to modify the config (add headers, set fetchOptions, etc.).

  ## Configuration

      config :ash_typescript,
        typed_controller_before_request_hook: "RouteHooks.beforeRequest"

  ## Returns
  A string representing the hook function name, or `nil` if not configured.
  """
  def typed_controller_before_request_hook do
    Application.get_env(:ash_typescript, :typed_controller_before_request_hook)
  end

  @doc """
  Gets the afterRequest hook function name for typed controller actions from application configuration.

  This hook is called after the HTTP request completes for typed controller mutation actions,
  regardless of success or failure.

  ## Configuration

      config :ash_typescript,
        typed_controller_after_request_hook: "RouteHooks.afterRequest"

  ## Returns
  A string representing the hook function name, or `nil` if not configured.
  """
  def typed_controller_after_request_hook do
    Application.get_env(:ash_typescript, :typed_controller_after_request_hook)
  end

  @doc """
  Gets the TypeScript type for typed controller hook context from application configuration.

  ## Configuration

      config :ash_typescript,
        typed_controller_hook_context_type: "MyHookContext"

  ## Returns
  A string representing the TypeScript type to use, defaulting to `"Record<string, any>"`.
  """
  def typed_controller_hook_context_type do
    Application.get_env(
      :ash_typescript,
      :typed_controller_hook_context_type,
      "Record<string, any>"
    )
  end

  @doc """
  Returns true if any typed controller hooks are configured.
  """
  def typed_controller_hooks_enabled? do
    typed_controller_before_request_hook() != nil or
      typed_controller_after_request_hook() != nil
  end

  @doc """
  Gets custom imports to add to the generated typed controller routes file.

  ## Configuration

      config :ash_typescript,
        typed_controller_import_into_generated: [
          %{import_name: "RouteHooks", file: "./routeHooks"}
        ]

  ## Returns
  A list of import config maps, or an empty list.
  """
  def typed_controller_import_into_generated do
    Application.get_env(:ash_typescript, :typed_controller_import_into_generated, [])
  end

  @doc """
  Gets the error handler for typed controller requests.

  Can be:
  - `nil` (default) - no error transformation
  - `{Module, :function, extra_args}` - MFA tuple
  - `Module` - module implementing `handle_error/2`

  ## Configuration

      config :ash_typescript,
        typed_controller_error_handler: {MyApp.ErrorHandler, :handle, []}

  ## Returns
  The error handler configuration, or `nil`.
  """
  def typed_controller_error_handler do
    Application.get_env(:ash_typescript, :typed_controller_error_handler)
  end

  @doc """
  Gets whether to show actual error detail in typed controller 500 responses.

  When `false` (default), 500 responses return "Internal server error".
  When `true`, the actual exception message — or the inspected value of an
  unexpected (non-`%Plug.Conn{}`) handler return — is included.

  ## Configuration

      config :ash_typescript, typed_controller_show_raised_errors: true

  ## Returns
  A boolean, defaulting to `false`.
  """
  def typed_controller_show_raised_errors? do
    Application.get_env(:ash_typescript, :typed_controller_show_raised_errors, false)
  end

  @doc """
  Gets the output field formatter for TypeScript generation and API responses.

  This determines how internal Elixir field names are converted for client
  consumption. It is fixed when the manifest compiles, from
  `config :ash_typescript, :output_field_formatter` (default `:camel_case`), and
  read here from the manifest's `custom.ash_rpc` decoration.
  Can be:
  - Built-in: :camel_case, :pascal_case, :snake_case
  - Custom: {Module, :function} or {Module, :function, [extra_args]}
  """
  def output_field_formatter, do: AshRpc.Manifest.output_formatter(manifest())

  @doc """
  Gets the input field formatter for parsing input parameters.

  This determines how client field names are converted to internal Elixir field
  names. It is fixed when the manifest compiles, from
  `config :ash_typescript, :input_field_formatter` (default `:camel_case`), and
  read here from the manifest's `custom.ash_rpc` decoration.
  Can be:
  - Built-in: :camel_case, :pascal_case, :snake_case
  - Custom: {Module, :function} or {Module, :function, [extra_args]}
  """
  def input_field_formatter, do: AshRpc.Manifest.input_formatter(manifest())

  @doc """
  Gets the output file path for shared TypeScript type definitions.

  Shared types (type aliases, resource schemas, filter types, utility types)
  are generated into this dedicated file. Both RPC and typed controller files import
  from this file instead of generating types inline.

  Auto-derives from `output_file` directory with default name `ash_types.ts`.
  Falls back to `"assets/js/ash_types.ts"` if `output_file` is also unset.

  ## Configuration

      config :ash_typescript,
        types_output_file: "assets/js/ash_types.ts"

  ## Returns
  A string file path (always non-nil).
  """
  def types_output_file do
    config_or_derive(:types_output_file, "ash_types.ts", "assets/js/ash_types.ts")
  end

  @doc """
  Gets the output file path for shared Zod validation schemas.

  Resource Zod schemas are generated into this dedicated file.
  Both RPC and typed controller files import from this file.

  Auto-derives from `output_file` directory with default name `ash_zod.ts`.
  Falls back to `"assets/js/ash_zod.ts"` if `output_file` is also unset.

  ## Configuration

      config :ash_typescript,
        zod_output_file: "assets/js/ash_zod.ts"

  ## Returns
  A string file path (always non-nil).
  """
  def zod_output_file do
    config_or_derive(:zod_output_file, "ash_zod.ts", "assets/js/ash_zod.ts")
  end

  @doc """
  Gets the output file path for shared Valibot validation schemas.

  Resource Valibot schemas are generated into this dedicated file.
  Both RPC and typed controller files import from this file.

  Auto-derives from `output_file` directory with default name `ash_valibot.ts`.
  Falls back to `"assets/js/ash_valibot.ts"` if `output_file` is also unset.

  ## Configuration

      config :ash_typescript,
        valibot_output_file: "assets/js/ash_valibot.ts"

  ## Returns
  A string file path (always non-nil).
  """
  def valibot_output_file do
    config_or_derive(:valibot_output_file, "ash_valibot.ts", "assets/js/ash_valibot.ts")
  end

  @doc """
  Determines if controller namespace file generation is enabled.

  When true, namespaced typed controller routes are generated into separate files.
  When false (default), all routes are in a single file.
  """
  def enable_controller_namespace_files? do
    Application.get_env(:ash_typescript, :enable_controller_namespace_files, false)
  end

  @doc """
  Gets the output directory for controller namespace files.

  When nil, namespace files are written to the same directory as the routes output file.
  """
  def controller_namespace_output_dir do
    Application.get_env(:ash_typescript, :controller_namespace_output_dir)
  end

  @doc """
  Gets the list of TypedChannel modules from application configuration.

  Each module must `use AshTypescript.TypedChannel` and declare a `topic` in its DSL.
  """
  def typed_channels do
    Application.get_env(:ash_typescript, :typed_channels, [])
  end

  @doc """
  Gets the output file path for typed channel subscription functions.

  When nil, no separate typed channels file is generated.
  """
  def typed_channels_output_file do
    Application.get_env(:ash_typescript, :typed_channels_output_file)
  end

  defp config_or_derive(key, derived_name, fallback) do
    case Application.get_env(:ash_typescript, key) do
      nil -> derive_from_output_file(derived_name) || fallback
      path -> path
    end
  end

  defp derive_from_output_file(default_name) do
    case Application.get_env(:ash_typescript, :output_file) do
      nil -> nil
      output_file -> Path.join(Path.dirname(output_file), default_name)
    end
  end

  @doc """
  Returns the configured `AshTypescript.Manifest` module.

  Reads from `config :ash_typescript, manifest: MyApp.AshTypescriptManifest`. Raises
  if not configured — every AshTypescript-using project must declare a manifest
  module.
  """
  def manifest_module do
    case Application.get_env(:ash_typescript, :manifest) do
      nil ->
        raise """
        No `:manifest` module configured for AshTypescript.

        Add this to your config:

            config :ash_typescript, manifest: MyApp.AshTypescriptManifest

        And define the module:

            defmodule MyApp.AshTypescriptManifest do
              use AshTypescript.Manifest, otp_app: :my_app
            end
        """

      module when is_atom(module) ->
        module
    end
  end

  @override_key {__MODULE__, :manifest_override}

  @doc """
  Runs `fun` with `manifest` as this process's manifest: `manifest/0`,
  `resource_lookup/1`, `action_lookup/1`, `type_lookup/1` and the formatter
  accessors return it (or derive from it); `entrypoints/1` and
  `typed_query_lookup/1` still read the configured manifest module unless
  given a source explicitly. Used by
  tests to vary formatters without mutating global config; safe under
  `async: true`.
  """
  @spec with_manifest(Ash.Info.Manifest.t(), (-> result)) :: result when result: term()
  def with_manifest(%Ash.Info.Manifest{} = manifest, fun) when is_function(fun, 0) do
    previous = Process.get(@override_key)
    Process.put(@override_key, manifest)

    try do
      fun.()
    after
      if previous, do: Process.put(@override_key, previous), else: Process.delete(@override_key)
    end
  end

  @doc """
  Returns the full `%Ash.Info.Manifest{}`. With no argument, returns the
  process's `with_manifest/2` override, or the configured manifest module's
  manifest. Accepts a manifest module or an `%Ash.Info.Manifest{}`.
  """
  def manifest(source \\ nil)
  def manifest(nil), do: Process.get(@override_key) || manifest(manifest_module())
  def manifest(%Ash.Info.Manifest{} = m), do: m

  def manifest(module) when is_atom(module),
    do: Spark.Dsl.Extension.get_persisted(module, :manifest)

  @doc "Returns the entrypoints from `manifest_module` (defaults to the configured manifest module)."
  def entrypoints(manifest_module \\ manifest_module()), do: manifest(manifest_module).entrypoints

  @doc """
  Returns the resource lookup map for `source` (a manifest module or
  `%Ash.Info.Manifest{}`; defaults to `manifest/0`, override included).
  """
  def resource_lookup(source \\ nil),
    do: lookup(source, :resource_lookup, &AshRpc.Manifest.resource_lookup/1)

  @doc "Returns the action lookup map for `source` (see `resource_lookup/1`)."
  def action_lookup(source \\ nil),
    do: lookup(source, :action_lookup, &AshRpc.Manifest.action_lookup/1)

  @doc "Returns the named-type lookup map for `source` (see `resource_lookup/1`)."
  def type_lookup(source \\ nil), do: lookup(source, :type_lookup, &AshRpc.Manifest.type_lookup/1)

  defp lookup(nil, key, from_struct) do
    case Process.get(@override_key) do
      nil -> lookup(manifest_module(), key, from_struct)
      manifest -> from_struct.(manifest)
    end
  end

  defp lookup(%Ash.Info.Manifest{} = m, _key, from_struct), do: from_struct.(m)

  defp lookup(module, key, _from_struct) when is_atom(module),
    do: Spark.Dsl.Extension.get_persisted(module, key) || %{}

  @doc """
  Returns the `%{typed_query_name_string => %Ash.Info.Manifest.Entrypoint{}}`
  lookup for typed-query entrypoints (defaults to the configured manifest module).
  """
  def typed_query_lookup(manifest \\ manifest_module()),
    do: Spark.Dsl.Extension.get_persisted(manifest, :typed_query_lookup) || %{}

  @doc """
  Runs a typed query (server-side rendering, controllers).

  Looks the query up in the manifest's `custom.ash_typescript`, presets its
  `fields`, and runs it through `AshRpc.run_action/4` with the `entrypoint:`
  option, so it isn't reachable from wire params. `params` may contain
  `:input`, `:page`, `:filter`, `:sort`. `opts` accepts `manifest:`.
  """
  @spec run_typed_query(atom(), map(), Plug.Conn.t(), keyword()) :: map()
  def run_typed_query(typed_query_name, params, conn, opts \\ []) do
    manifest = Keyword.get_lazy(opts, :manifest, &manifest/0)

    case AshTypescript.Manifest.Custom.typed_query_entrypoint(manifest, typed_query_name) do
      nil ->
        AshRpc.failure_response(
          AshTypescript.RpcProfile,
          [typed_query_not_found(typed_query_name)],
          manifest: manifest
        )

      entrypoint ->
        wire_params =
          [input: "input", page: "page", filter: "filter", sort: "sort"]
          |> Enum.reduce(%{"fields" => entrypoint.preset_fields}, fn {key, wire}, acc ->
            case params[key] do
              nil -> acc
              value -> Map.put(acc, wire, value)
            end
          end)

        AshRpc.run_action(AshTypescript.RpcProfile, conn, wire_params,
          manifest: manifest,
          entrypoint: entrypoint
        )
    end
  end

  defp typed_query_not_found(name) do
    %{
      type: "typed_query_not_found",
      message: "Typed query %{typed_query_name} not found",
      short_message: "Typed query not found",
      vars: %{typed_query_name: to_string(name)},
      path: [],
      fields: [],
      details: %{
        suggestion:
          "Check that the typed query is defined in a typed_queries block in your domain's typescript_rpc configuration"
      }
    }
  end
end
