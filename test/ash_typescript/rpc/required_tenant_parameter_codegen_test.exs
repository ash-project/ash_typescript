# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.RequiredTenantParameterCodegenTest do
  # With `require_tenant_parameters: true`, a multitenant resource's RPC
  # functions take a required `tenant` and always send it; the test config
  # leaves it optional.
  use ExUnit.Case, async: false

  alias AshTypescript.Test.{CodegenTestHelper, TestHelpers}

  setup do
    TestHelpers.restore_application_env_on_exit([:require_tenant_parameters])
    Application.put_env(:ash_typescript, :require_tenant_parameters, true)
    {:ok, files} = CodegenTestHelper.generate_files()
    %{rpc: CodegenTestHelper.rpc_content(files)}
  end

  setup %{rpc: rpc} do
    [function] =
      Regex.run(~r/export async function listOrgTodos<.*?return executeActionRpcRequest/s, rpc)

    %{function: function}
  end

  test "the config requires the tenant", %{function: function} do
    assert function =~ "  config: {\n  tenant: string;\n"
  end

  test "the payload always sends it", %{function: function} do
    assert function =~ "\n    tenant: config.tenant,\n"
    refute function =~ "config.tenant !== undefined"
  end

  test "a resource without multitenancy keeps no tenant requirement", %{rpc: rpc} do
    assert rpc =~
             ~r/export async function listTodos<[^\n]*\n  config: Config & \{ fields: Fields \}/

    assert rpc =~ ~r/export type ListTodosConfig = \{\n  tenant\?: string;/
  end
end
