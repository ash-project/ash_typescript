# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.TypedController.RequestHandlerTest do
  use ExUnit.Case

  @moduletag :ash_typescript

  alias AshTypescript.TypedController.RequestHandler

  defp call(action, params) do
    :get
    |> Plug.Test.conn("/test", "")
    |> RequestHandler.handle(AshTypescript.Test.Session, action, params)
  end

  defp json_body(conn) do
    conn.resp_body |> Jason.decode!()
  end

  describe "argument extraction — only declared arguments are passed to handler" do
    test "undeclared params are dropped" do
      conn = call(:echo_params, %{"name" => "alice", "extra_field" => "ignored"})

      assert conn.status == 200
      body = json_body(conn)
      params = body["params"]

      assert Map.has_key?(params, "name")
      refute Map.has_key?(params, "extra_field")
    end

    test "Phoenix internal params (_format, action, controller) are dropped" do
      conn =
        call(:echo_params, %{
          "name" => "alice",
          "_format" => "json",
          "action" => "echo_params",
          "controller" => "Elixir.SomeController"
        })

      assert conn.status == 200
      body = json_body(conn)
      params = body["params"]

      refute Map.has_key?(params, "_format")
      refute Map.has_key?(params, "action")
      refute Map.has_key?(params, "controller")
    end

    test "underscore-prefixed params are dropped" do
      conn = call(:echo_params, %{"name" => "alice", "_csrf_token" => "tok123"})

      assert conn.status == 200
      body = json_body(conn)
      params = body["params"]

      refute Map.has_key?(params, "_csrf_token")
    end

    test "route with no arguments receives empty map" do
      conn = call(:logout, %{"unexpected" => "param"})

      assert conn.status == 200
      assert conn.resp_body == "LoggedOut"
    end

    test "handler receives params with atom keys" do
      conn = call(:echo_params, %{"name" => "alice", "count" => "5"})

      assert conn.status == 200
      body = json_body(conn)
      params = body["params"]

      # Keys were atoms in the handler, serialized to strings by Jason
      assert Map.has_key?(params, "name")
      assert Map.has_key?(params, "count")
    end
  end

  describe "required argument validation (allow_nil?: false)" do
    test "returns 422 when required argument is missing" do
      conn = call(:login, %{})

      assert conn.status == 422
      body = json_body(conn)
      errors = body["errors"]
      assert is_list(errors)

      code_error = Enum.find(errors, &(&1["field"] == "code"))
      assert code_error["message"] == "is required"
    end

    test "returns 422 with all missing required fields listed" do
      conn = call(:update_provider, %{})

      assert conn.status == 422
      body = json_body(conn)

      field_names = Enum.map(body["errors"], & &1["field"])
      assert "enabled" in field_names
    end

    test "succeeds when required arguments are present" do
      conn = call(:login, %{"code" => "abc123"})

      assert conn.status == 200
      assert conn.resp_body == "LoggedIn"
    end

    test "succeeds when all required arguments are present with optional ones omitted" do
      conn = call(:update_provider, %{"enabled" => "true"})

      assert conn.status == 200
      assert conn.resp_body == "ProviderUpdated"
    end
  end

  describe "Ash.Type.cast_input type casting" do
    test "casts string type" do
      conn = call(:echo_params, %{"name" => "alice"})

      assert conn.status == 200
      body = json_body(conn)
      assert body["params"]["name"] == "alice"
    end

    test "casts integer from string" do
      conn = call(:echo_params, %{"name" => "alice", "count" => "42"})

      assert conn.status == 200
      body = json_body(conn)
      assert body["params"]["count"] == 42
    end

    test "casts integer from actual integer" do
      conn = call(:echo_params, %{"name" => "alice", "count" => 7})

      assert conn.status == 200
      body = json_body(conn)
      assert body["params"]["count"] == 7
    end

    test "returns 422 for invalid integer value" do
      conn = call(:echo_params, %{"name" => "alice", "count" => "not_a_number"})

      assert conn.status == 422
      body = json_body(conn)

      error = Enum.find(body["errors"], &(&1["field"] == "count"))
      assert error["message"] =~ "invalid"
    end

    test "casts boolean from string 'true'" do
      conn = call(:echo_params, %{"name" => "alice", "active" => "true"})

      assert conn.status == 200
      body = json_body(conn)
      assert body["params"]["active"] == true
    end

    test "casts boolean from string 'false'" do
      conn = call(:echo_params, %{"name" => "alice", "active" => "false"})

      assert conn.status == 200
      body = json_body(conn)
      assert body["params"]["active"] == false
    end

    test "casts boolean from actual boolean" do
      conn = call(:echo_params, %{"name" => "alice", "active" => true})

      assert conn.status == 200
      body = json_body(conn)
      assert body["params"]["active"] == true
    end

    test "returns 422 for invalid boolean value" do
      conn = call(:update_provider, %{"enabled" => "not_a_bool"})

      assert conn.status == 422
      body = json_body(conn)

      error = Enum.find(body["errors"], &(&1["field"] == "enabled"))
      assert error["message"] =~ "invalid"
    end
  end

  describe "camelCase → snake_case normalization" do
    test "camelCase param keys are normalized to snake_case" do
      conn = call(:login, %{"code" => "abc", "rememberMe" => "true"})

      assert conn.status == 200
    end

    test "snake_case param keys still work" do
      conn = call(:login, %{"code" => "abc", "remember_me" => "true"})

      assert conn.status == 200
    end

    test "camelCase required field is resolved after normalization" do
      conn = call(:echo_params, %{"name" => "alice", "displayName" => "Alice"})

      # displayName should be normalized but it's not a declared arg on echo_params,
      # so it should be dropped (only name, count, active are declared)
      assert conn.status == 200
      body = json_body(conn)
      refute Map.has_key?(body["params"], "display_name")
      refute Map.has_key?(body["params"], "displayName")
    end
  end

  describe "optional arguments" do
    test "optional argument defaults to nil when omitted" do
      conn = call(:echo_params, %{"name" => "alice"})

      assert conn.status == 200
      body = json_body(conn)
      assert body["params"]["count"] == nil
      assert body["params"]["active"] == nil
    end

    test "optional argument is passed through when provided" do
      conn = call(:echo_params, %{"name" => "alice", "count" => "3", "active" => "true"})

      assert conn.status == 200
      body = json_body(conn)
      assert body["params"]["count"] == 3
      assert body["params"]["active"] == true
    end

    test "route with all optional arguments works when none provided" do
      conn = call(:provider_page, %{})

      assert conn.status == 200
      assert conn.resp_body == "ProviderPage"
    end
  end

  describe "handler dispatch" do
    test "handler receives Plug.Conn and returns Plug.Conn" do
      conn = call(:auth, %{})

      assert %Plug.Conn{} = conn
      assert conn.status == 200
      assert conn.resp_body == "Auth"
    end

    test "handler receives only declared arguments in params map" do
      conn =
        call(:echo_params, %{
          "name" => "alice",
          "count" => "10",
          "undeclared" => "dropped",
          "_meta" => "dropped"
        })

      assert conn.status == 200
      body = json_body(conn)
      params = body["params"]

      assert params["name"] == "alice"
      assert params["count"] == 10
      # undeclared and underscore-prefixed params are not passed to handler
      refute Map.has_key?(params, "undeclared")
      refute Map.has_key?(params, "_meta")
    end
  end

  describe "error responses" do
    test "422 response has errors array" do
      conn = call(:login, %{})

      assert conn.status == 422
      body = json_body(conn)
      assert is_list(body["errors"])
      assert length(body["errors"]) > 0
    end

    test "each error has field and message keys" do
      conn = call(:login, %{})

      body = json_body(conn)

      for error <- body["errors"] do
        assert Map.has_key?(error, "field")
        assert Map.has_key?(error, "message")
      end
    end

    test "cast errors and required errors can appear together" do
      conn = call(:echo_params, %{"count" => "not_a_number"})

      assert conn.status == 422
      body = json_body(conn)

      fields_with_errors = Enum.map(body["errors"], & &1["field"])
      # name is required and missing
      assert "name" in fields_with_errors
      # count has an invalid value
      assert "count" in fields_with_errors
    end
  end
end
