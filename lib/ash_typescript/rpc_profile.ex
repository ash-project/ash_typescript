# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.RpcProfile do
  @moduledoc """
  ash_typescript's `AshRpc.Profile`. Use it with `AshRpc.run_action/4`,
  `AshRpc.validate_action/4`, `AshRpc.Plug` and `AshRpc.Channel`.

  Error handling comes from each domain's `typescript_rpc` section
  (`error_handler`, `show_raised_errors?`); policy breakdowns from
  `config :ash_typescript, policies: [show_policy_breakdowns?: true]`.
  Request errors a stale client can cause point at regenerating the
  TypeScript file (`stale_client_hint/0`).
  """

  use AshRpc.Profile

  @impl AshRpc.Profile
  def manifest, do: AshTypescript.manifest()

  @impl AshRpc.Profile
  def error_handler(nil), do: nil

  def error_handler(domain) do
    with true <- function_exported?(domain, :spark_dsl_config, 0),
         {:ok, handler} <-
           Spark.Dsl.Extension.fetch_opt(domain, [:typescript_rpc], :error_handler) do
      handler
    else
      _ -> {AshRpc.DefaultErrorHandler, :handle_error, []}
    end
  end

  @impl AshRpc.Profile
  def show_raised_errors?(nil), do: false

  def show_raised_errors?(domain),
    do: AshTypescript.Rpc.Info.typescript_rpc_show_raised_errors?(domain)

  @impl AshRpc.Profile
  def show_policy_breakdowns? do
    Keyword.get(
      Application.get_env(:ash_typescript, :policies, []),
      :show_policy_breakdowns?,
      false
    )
  end

  @doc """
  The `details.hint` added to request errors a stale generated client can cause:
  regenerate the TypeScript file.
  """
  @impl AshRpc.Profile
  def stale_client_hint do
    "This error is most likely happening because the generated typescript file used is not up to date with the running backend. Check that you are using the latest generated file, and/or that a new file has been generated after the last backend changes."
  end
end
