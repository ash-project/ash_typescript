# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.Session do
  @moduledoc """
  Test module for typed controller extension testing.
  A session management controller with login/logout and provider management.
  """
  use AshTypescript.TypedController

  typed_controller do
    module_name AshTypescript.Test.SessionController

    route :auth do
      method :get
      run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "Auth") end
    end

    route :provider_page do
      method :get
      run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "ProviderPage") end
      argument :provider, :string
      argument :tab, :string
    end

    route :search do
      method :get
      run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "Search") end
      argument :q, :string, allow_nil?: false
      argument :page, :integer
    end

    route :login do
      method :post
      run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "LoggedIn") end
      argument :code, :string, allow_nil?: false
      argument :remember_me, :boolean
    end

    route :logout do
      method :post
      run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "LoggedOut") end
    end

    route :update_provider do
      method :patch
      run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "ProviderUpdated") end
      argument :provider, :string
      argument :enabled, :boolean, allow_nil?: false
      argument :display_name, :string
    end

    route :echo_params do
      method :post

      run fn conn, params ->
        # Echoes received params as JSON so tests can inspect them
        json_params = Map.new(params, fn {k, v} -> {to_string(k), v} end)
        body = Jason.encode!(%{params: json_params})

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, body)
      end

      argument :name, :string, allow_nil?: false
      argument :count, :integer
      argument :active, :boolean
    end
  end
end
