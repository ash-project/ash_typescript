# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.TypedController.Route do
  @moduledoc """
  Behaviour for typed controller route handlers.

  Implement this behaviour for handler modules passed to `run:` in the DSL.
  The handler receives the conn and a map of normalized params, and must
  return a `%Plug.Conn{}`.

  ## Example

      defmodule MyApp.LoginHandler do
        @behaviour AshTypescript.TypedController.Route

        @impl true
        def run(conn, params) do
          # Handle login...
          Plug.Conn.send_resp(conn, 200, "OK")
        end
      end

  Then in the DSL:

      route :login, method: :post, run: MyApp.LoginHandler do
        argument :code, :string, allow_nil?: false
      end
  """

  @callback run(Plug.Conn.t(), map()) :: Plug.Conn.t()
end
