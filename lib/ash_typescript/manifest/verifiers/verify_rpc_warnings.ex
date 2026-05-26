# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.Verifiers.VerifyRpcWarnings do
  @moduledoc """
  Emits compile-time warnings for likely-misconfigured RPC setups.

  Reports:

    * Resources that carry the `AshTypescript.Resource` extension but aren't
      listed in any domain's `typescript_rpc` block — they won't get TypeScript
      types generated.
    * Resources reachable from RPC resources (via attribute types or
      relationships) that aren't themselves declared as RPC resources — they
      won't have TS types either, and any references will fall back to inline
      shapes.

  Each warning is gated by an application-level toggle:
    * `config :ash_typescript, warn_on_missing_rpc_config: true` (default)
    * `config :ash_typescript, warn_on_non_rpc_references: true` (default)

  Runs once per compile of the manifest module, so there's no need for the
  per-domain deduplication hack the previous Rpc-DSL-level verifier used.
  Always returns `:ok` — warnings are informational, not errors.
  """
  use Spark.Dsl.Verifier
  alias AshTypescript.Codegen.TypeDiscovery
  alias Spark.Dsl.Verifier

  @impl true
  def verify(dsl) do
    manifest = Verifier.get_persisted(dsl, :manifest)
    resource_lookup = Verifier.get_persisted(dsl, :resource_lookup)
    rpc_configs = Verifier.get_persisted(dsl, :rpc_configs) || []
    do_verify(manifest, resource_lookup, rpc_configs)
  end

  defp do_verify(nil, _resource_lookup, _rpc_configs), do: :ok

  defp do_verify(%Ash.Info.Manifest{} = _manifest, resource_lookup, rpc_configs) do
    otp_app = Mix.Project.config()[:app]
    rpc_resources = rpc_configs |> Enum.map(fn {_d, rc} -> rc.resource end) |> Enum.uniq()

    case TypeDiscovery.build_rpc_warnings(otp_app, resource_lookup, rpc_resources) do
      nil -> :ok
      message -> IO.warn(message)
    end

    :ok
  end
end
