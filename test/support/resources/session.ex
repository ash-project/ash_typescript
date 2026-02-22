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
    namespace "auth"

    route :auth do
      method :get
      run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "Auth") end
    end

    route :provider_page do
      method :get
      run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "ProviderPage") end
      argument :provider, :string, allow_nil?: false
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
      see [:auth, :logout]
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
      argument :provider, :string, allow_nil?: false
      argument :enabled, :boolean, allow_nil?: false
      argument :display_name, :string
    end

    route :profile do
      method :get
      namespace "account"
      run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "Profile") end
      argument :user_id, :string
      argument :bio, :string
    end

    route :raise_error do
      method :post
      run fn _conn, _params -> raise "test error for show_raised_errors" end
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

    route :register do
      method :post
      run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "Registered") end

      argument :username, :string,
        allow_nil?: false,
        constraints: [min_length: 3, max_length: 20, match: ~r/^[a-zA-Z0-9_]+$/]

      argument :email, :string,
        allow_nil?: false,
        constraints: [match: ~r/^[^@]+@[^@]+\.[^@]+$/]

      argument :age, :integer,
        allow_nil?: false,
        constraints: [min: 13, max: 120]

      argument :score, :float, constraints: [min: 0, max: 100]

      argument :bio, :string, constraints: [max_length: 500]

      argument :invite_code, :string, constraints: [min_length: 8, max_length: 8]
    end

    route :create_task do
      method :post
      run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "TaskCreated") end
      zod_schema_name "createTaskRouteZodSchema"

      argument :title, :string, allow_nil?: false, constraints: [min_length: 1, max_length: 200]
      argument :metadata, AshTypescript.Test.TaskMetadata, allow_nil?: false
      argument :priority, :integer, constraints: [min: 1, max: 5]
    end
  end
end
