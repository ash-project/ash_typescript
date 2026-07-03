# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.EntrypointResolutionTest do
  use ExUnit.Case, async: false

  alias AshTypescript.Manifest.Custom

  test "an rpc read still runs end-to-end after discovery searches entrypoints" do
    conn = %Plug.Conn{private: %{}}
    params = %{"action" => "list_todos", "fields" => ["id", "title"]}
    result = AshTypescript.Rpc.run_action(:ash_typescript, conn, params)
    assert %{"success" => true} = result
  end

  test "every rpc_action name resolves to exactly one decorated entrypoint" do
    entrypoints = AshTypescript.entrypoints()

    rpc_names =
      for e <- entrypoints, rpc = Custom.rpc_action(e), rpc != nil, do: {e.resource, rpc.name}

    assert length(rpc_names) == length(Enum.uniq(rpc_names))
  end
end
