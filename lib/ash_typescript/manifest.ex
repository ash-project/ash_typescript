# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest do
  @moduledoc """
  Standalone Spark DSL module for building a unified app-wide Ash.Info.Manifest.

  When the same resource appears in multiple domains' `typescript_rpc` blocks
  with different RPC actions, this module ensures all actions are merged into
  a single unified spec rather than each domain overwriting the previous one.

  ## Usage

      defmodule MyApp.AshTypescriptManifest do
        use AshTypescript.Manifest, otp_app: :my_app
      end

  ## Scoped manifests (testing)

  When `:domains` is supplied, the manifest is built from exactly those domains
  instead of walking `Ash.Info.domains(otp_app)`. This lets tests build an
  inline manifest from a freshly-defined domain without touching global state.

      defmodule TestManifest do
        use AshTypescript.Manifest,
          otp_app: :ash_typescript,
          domains: [MyTest.InlineDomain]
      end

  ## Custom types

  The `custom_types` section declares fields (`map`) or TypeScript mappings
  (`scalar`) for custom types the app doesn't own. Decoration also reads a
  type's own `typescript_fields/0` and `composite_types/1`, and the manifest
  recompiles when such a type module changes. Type modules consulted for
  fields must never read the manifest at compile time: it depends on them.
  """

  use Spark.Dsl,
    default_extensions: [extensions: [AshTypescript.Manifest.Dsl]],
    opt_schema: [
      domains: [
        type: {:or, [{:list, :atom}, nil]},
        default: nil,
        doc:
          "Explicit list of domain modules to build the manifest from. When nil, walks `Ash.Info.domains(otp_app)`."
      ],
      typed_controllers: [
        type: {:list, :atom},
        default: [],
        doc:
          "Typed controller modules (`use AshTypescript.TypedController`) whose routes the manifest stores. The only source of typed controllers."
      ],
      typed_channels: [
        type: {:list, :atom},
        default: [],
        doc:
          "Typed channel modules (`use AshTypescript.TypedChannel`) whose declared events the manifest stores. The only source of typed channels."
      ]
    ]

  @impl Spark.Dsl
  def handle_opts(opts) do
    warn_on_legacy_config()
    typed_controllers = opts[:typed_controllers] || []
    typed_channels = opts[:typed_channels] || []

    quote do
      @persist {:domains, unquote(opts[:domains])}
      @persist {:typed_controllers, unquote(typed_controllers)}
      @persist {:typed_channels, unquote(typed_channels)}
      # AshTypescript.RpcMappingSource reads these while the manifest compiles;
      # tracking them recompiles the manifest when the config changes.
      _ = Application.compile_env(:ash_typescript, :output_field_formatter, :camel_case)
      _ = Application.compile_env(:ash_typescript, :not_found_error?, true)
      unquote_splicing(compile_dependency_asts(opts[:otp_app], opts[:domains]))
      unquote_splicing(typed_module_dependency_asts(typed_controllers ++ typed_channels))
    end
  end

  # The manifest is built by a transformer that discovers domains via
  # `Ash.Info.domains/1` at compile time, which is invisible to the compiler's
  # dependency tracker — without explicit edges, editing a resource recompiles
  # the resource and its domain but not the manifest module, leaving the
  # persisted manifest stale on incremental compiles. Injecting a static
  # remote call per domain into the manifest module's body creates real
  # compile-time dependencies: resource edit -> domain recompile -> manifest
  # recompile. `Application.compile_env` additionally recompiles the manifest
  # when the `:ash_domains` config itself changes.
  defp compile_dependency_asts(otp_app, explicit_domains) do
    config_tracking =
      if is_nil(explicit_domains) and not is_nil(otp_app) do
        [quote(do: _ = Application.compile_env(unquote(otp_app), :ash_domains, []))]
      else
        []
      end

    domains =
      explicit_domains ||
        (otp_app && Application.get_env(otp_app, :ash_domains, [])) || []

    domain_deps =
      for domain <- domains do
        quote do
          _ = unquote(domain).module_info(:md5)
        end
      end

    config_tracking ++ domain_deps
  end

  # The lists live on the manifest module, so editing them recompiles it.
  # Each listed module gets a compile-time edge, so editing a route or a
  # channel declaration recompiles the manifest too. Those modules must never
  # read the manifest at compile time: it depends on them.
  defp typed_module_dependency_asts(modules) do
    for module <- Enum.uniq(modules), do: quote(do: _ = unquote(module).module_info(:md5))
  end

  # Config keys that were removed, with what replaces each. Nothing reads them,
  # so a leftover setting would silently drop typed controllers or channels
  # from the manifest, or change the generated types. The read happens at
  # macro-expansion time on purpose: it feeds a warning only.
  @legacy_config_keys [
    typed_controllers:
      "List the modules on the manifest module instead: " <>
        "use AshTypescript.Manifest, typed_controllers: [...]",
    typed_channels:
      "List the modules on the manifest module instead: " <>
        "use AshTypescript.Manifest, typed_channels: [...]",
    type_mapping_overrides:
      "Declare these types in your manifest module's `custom_types` section: " <>
        "`scalar MyType, :string, typescript: \"<ts type>\"`",
    zod_mapping_overrides:
      "Give these types a `zod` schema in your manifest module's `custom_types` section: " <>
        "`scalar MyType, :string, zod: \"<zod schema>\"` (or `map MyType do ... zod ... end`)",
    valibot_mapping_overrides:
      "Give these types a `valibot` schema in your manifest module's `custom_types` section: " <>
        "`scalar MyType, :string, valibot: \"<valibot schema>\"` (or `map MyType do ... valibot ... end`)"
  ]

  defp warn_on_legacy_config do
    for {key, instead} <- @legacy_config_keys,
        not is_nil(Application.get_env(:ash_typescript, key)) do
      IO.warn(
        "config :ash_typescript, #{inspect(key)} is no longer read and is ignored. " <> instead,
        []
      )
    end
  end

  @doc """
  Re-decorates `manifest` with a different `:output_formatter` (for tests).
  Runs `AshRpc.Manifest.redecorate/2`, then rebuilds the stored typed
  controller routes and typed channel publications, so their client names and
  decorated types follow the new formatter.
  """
  @spec redecorate(Ash.Info.Manifest.t(), keyword()) :: Ash.Info.Manifest.t()
  def redecorate(%Ash.Info.Manifest{} = manifest, opts) do
    manifest
    |> AshRpc.Manifest.redecorate(opts)
    |> AshTypescript.Manifest.TypedRoutes.redecorate()
  end

  @doc """
  Runs every manifest verifier against `manifest_module`'s persisted DSL state.

  Returns `:ok` when all verifiers pass, or `{:error, formatted_message}`
  aggregating every failure.

  Used by tests to drive the same verifier code path that compile-time runs.
  """
  def run_verifiers(manifest_module) when is_atom(manifest_module) do
    run_verifiers_on_dsl(manifest_module.spark_dsl_config())
  end

  @doc """
  Convenience wrapper for tests: compiles a one-shot inline manifest module
  scoped to `domains`, then runs all manifest verifiers against it.

  Returns `:ok` or `{:error, formatted_message}` — same shape as `run_verifiers/1`.

  The generated module name is deterministic from the domains list (via
  `:erlang.phash2/1`), so repeated calls with the same arguments reuse the same
  compiled module instead of triggering a redefinition warning. Each unique
  call creates one real `AshTypescript.Manifest`-using module at runtime —
  which means field-selector reads (`Spark.Dsl.Extension.get_persisted/3`)
  resolve against that module's persisted state, exactly like the production
  path does.
  """
  def verify_for_domains(domains, opts \\ []) when is_list(domains) do
    otp_app = Keyword.get(opts, :otp_app, :ash_typescript)
    suffix = :erlang.phash2({domains, otp_app})
    module_name = Module.concat([__MODULE__, "InlineForTest", "M#{suffix}"])

    unless Code.ensure_loaded?(module_name) do
      Module.create(
        module_name,
        quote do
          use AshTypescript.Manifest,
            otp_app: unquote(otp_app),
            domains: unquote(domains)
        end,
        Macro.Env.location(__ENV__)
      )
    end

    run_verifiers(module_name)
  end

  defp run_verifiers_on_dsl(dsl) do
    errors =
      AshTypescript.Manifest.Dsl.verifiers()
      |> Enum.filter(&ash_typescript_verifier?/1)
      |> Enum.flat_map(fn verifier ->
        try do
          case verifier.verify(dsl) do
            :ok -> []
            {:error, error} -> [{verifier, error}]
          end
        rescue
          e -> [{verifier, e}]
        end
      end)

    case errors do
      [] ->
        :ok

      _ ->
        message =
          errors
          |> Enum.map_join("\n\n", fn {verifier, error} ->
            """
            Verifier: #{inspect(verifier)}
            Error: #{format_error(error)}
            """
            |> String.trim()
          end)

        {:error, message}
    end
  end

  defp format_error(%Spark.Error.DslError{message: message}), do: message
  defp format_error(error) when is_binary(error), do: error
  defp format_error(error), do: Exception.message(error)

  # Skip Spark-injected generic verifiers (`VerifyEntityUniqueness` etc.) that
  # expect full DSL section data. We only run ash_typescript-owned ones, which
  # read solely from `:persist` and work against fabricated DSL state.
  defp ash_typescript_verifier?(verifier) do
    Code.ensure_loaded?(verifier) and
      function_exported?(verifier, :verify, 1) and
      verifier
      |> Module.split()
      |> List.starts_with?(["AshTypescript"])
  end
end
