# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.Session do
  @moduledoc """
  Test resource for controller resource extension testing.
  A session management controller with login/logout and provider management.
  """
  use Ash.Resource,
    domain: AshTypescript.Test.ControllerResourceDomain,
    extensions: [AshTypescript.ControllerResource]

  controller do
    module_name AshTypescript.Test.SessionController

    route :auth, :auth, method: :get
    route :provider_page, :provider_page, method: :get
    route :login, :login, method: :post
    route :logout, :logout, method: :post
    route :update_provider, :update_provider, method: :patch
  end

  actions do
    action :auth do
      run fn _input, ctx ->
        conn = ctx.conn
        {:ok, Plug.Conn.send_resp(conn, 200, "Auth")}
      end
    end

    action :provider_page do
      argument :provider, :string

      run fn input, ctx ->
        _provider = input.arguments[:provider]
        conn = ctx.conn
        {:ok, Plug.Conn.send_resp(conn, 200, "ProviderPage")}
      end
    end

    action :login do
      argument :code, :string, allow_nil?: false
      argument :remember_me, :boolean

      run fn _input, ctx ->
        conn = ctx.conn
        {:ok, Plug.Conn.send_resp(conn, 200, "LoggedIn")}
      end
    end

    action :logout do
      run fn _input, ctx ->
        conn = ctx.conn
        {:ok, Plug.Conn.send_resp(conn, 200, "LoggedOut")}
      end
    end

    action :update_provider do
      argument :enabled, :boolean, allow_nil?: false
      argument :display_name, :string

      run fn _input, ctx ->
        conn = ctx.conn
        {:ok, Plug.Conn.send_resp(conn, 200, "ProviderUpdated")}
      end
    end
  end
end
