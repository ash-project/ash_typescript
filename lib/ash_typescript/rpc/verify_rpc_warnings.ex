# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.VerifyRpcWarnings do
  @moduledoc """
  Outputs warnings for potentially misconfigured RPC resources during compilation.

  This verifier checks for:
  - Resources with the AshTypescript.Resource extension that are not configured in any typescript_rpc block
  - Non-RPC resources that are referenced by RPC resources but not configured as RPC resources

  These are informational warnings only and do not halt compilation.
  """
  use Spark.Dsl.Verifier

  alias AshTypescript.Codegen.TypeDiscovery

  @impl true
  def verify(dsl) do
    # Only run on the first domain with RPC config to avoid duplicate warnings
    rpc_domains =
      Mix.Project.config()[:app]
      |> Ash.Info.domains()
      |> Enum.filter(&AshTypescript.Rpc.Info.typescript_rpc/1)

    case rpc_domains do
      [] ->
        :ok

      [first_domain_with_rpc | _] ->
        domain = dsl[:persist][:module]

        if first_domain_with_rpc != domain do
          :ok
        else
          # Run warnings only once for the entire app
          otp_app = Mix.Project.config()[:app]

          case TypeDiscovery.build_rpc_warnings(otp_app) do
            nil -> :ok
            message -> IO.warn(message)
          end

          # Always return :ok since these are warnings, not errors
          :ok
        end
    end
  end
end
