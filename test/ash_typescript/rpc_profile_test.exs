# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.RpcProfileTest do
  use ExUnit.Case, async: false

  alias AshTypescript.RpcProfile

  test "manifest/0 is the configured, ash_rpc-decorated manifest" do
    assert AshRpc.Manifest.ash_rpc(RpcProfile.manifest())
  end

  test "error_handler/1 reads the typescript_rpc DSL and is nil before resolution" do
    assert RpcProfile.error_handler(nil) == nil

    assert RpcProfile.error_handler(AshTypescript.Test.Domain) ==
             {AshRpc.DefaultErrorHandler, :handle_error, []}
  end

  test "show_raised_errors?/1" do
    assert RpcProfile.show_raised_errors?(nil) == false
    assert RpcProfile.show_raised_errors?(AshTypescript.Test.Domain) == false
  end

  test "show_policy_breakdowns?/0 reads config :ash_typescript, :policies" do
    AshTypescript.Test.TestHelpers.restore_application_env_on_exit([:policies])
    Application.put_env(:ash_typescript, :policies, show_policy_breakdowns?: true)
    assert RpcProfile.show_policy_breakdowns?()
    Application.delete_env(:ash_typescript, :policies)
    refute RpcProfile.show_policy_breakdowns?()
  end

  test "stale_client_hint/0 points at the generated TypeScript file" do
    assert RpcProfile.stale_client_hint() =~ "generated typescript file"

    error =
      AshRpc.ErrorBuilder.build_error_response(
        AshRpc.Runtime.new(RpcProfile),
        {:action_not_found, "missing"}
      )

    assert error.details.hint == RpcProfile.stale_client_hint()
  end
end
