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
  """

  use Spark.Dsl,
    default_extensions: [extensions: [AshTypescript.Manifest.Dsl]],
    opt_schema: [
      domains: [
        type: {:or, [{:list, :atom}, nil]},
        default: nil,
        doc:
          "Explicit list of domain modules to build the manifest from. When nil, walks `Ash.Info.domains(otp_app)`."
      ]
    ]

  @impl Spark.Dsl
  def handle_opts(opts) do
    quote do
      @persist {:domains, unquote(opts[:domains])}
      unquote_splicing(compile_dependency_asts(opts[:otp_app], opts[:domains]))
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
