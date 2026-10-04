# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.ChannelTenantOverrideTest do
  use ExUnit.Case, async: true

  test "a tenant param overrides assigns[:ash_tenant] on the socket path" do
    socket = %Phoenix.Socket{
      assigns: %{ash_actor: nil, ash_tenant: "socket_tenant", ash_context: %{}}
    }

    assert {:ok, request} =
             AshRpc.Pipeline.parse_request(
               AshRpc.Runtime.new(AshTypescript.RpcProfile),
               AshRpc.Context.from_socket(socket),
               %{"action" => "list_todos", "fields" => ["id"], "tenant" => "param_tenant"}
             )

    assert request.tenant == "param_tenant"
  end
end
