# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.TypedController do
  @moduledoc """
  Standalone Spark DSL for defining typed controller routes.

  Generates TypeScript path helper functions and a thin Phoenix controller
  from routes configured in the DSL. This is completely independent from
  `Ash.Resource` — routes contain colocated arguments and handler functions.

  ## Usage

      defmodule MyApp.Session do
        use AshTypescript.TypedController

        typed_controller do
          module_name MyAppWeb.SessionController

          route :login do
            method :post
            run fn conn, params -> Plug.Conn.send_resp(conn, 200, "OK") end
            argument :code, :string, allow_nil?: false
          end

          route :auth do
            method :get
            run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "Auth") end
          end
        end
      end
  """

  use Spark.Dsl,
    default_extensions: [extensions: [AshTypescript.TypedController.Dsl]]
end
