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

  # Errors use the RPC error shape, so the affected argument is in `fields`
  # (a list) rather than a singular `field` key.
  defp error_for(conn, field) when is_binary(field) do
    conn |> json_body() |> Map.fetch!("errors") |> Enum.find(&(field in &1["fields"]))
  end

  defp error_fields(conn) do
    conn |> json_body() |> Map.fetch!("errors") |> Enum.flat_map(& &1["fields"])
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
      assert is_list(json_body(conn)["errors"])

      assert %{
               "type" => "required",
               "message" => "is required",
               "shortMessage" => "Required field",
               "vars" => %{"field" => "code"},
               "fields" => ["code"],
               "path" => []
             } = error_for(conn, "code")
    end

    test "returns 422 with all missing required fields listed" do
      conn = call(:update_provider, %{})

      assert conn.status == 422
      assert "enabled" in error_fields(conn)
    end

    test "succeeds when required arguments are present" do
      conn = call(:login, %{"code" => "abc123"})

      assert conn.status == 200
      assert conn.resp_body == "LoggedIn"
    end

    test "succeeds when all required arguments are present with optional ones omitted" do
      conn = call(:update_provider, %{"provider" => "github", "enabled" => "true"})

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

      error = error_for(conn, "count")
      assert error["type"] == "invalid_argument"
      assert error["shortMessage"] == "Invalid argument"
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

      error = error_for(conn, "enabled")
      assert error["type"] == "invalid_argument"
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
      conn = call(:provider_page, %{"provider" => "github"})

      assert conn.status == 200
      assert conn.resp_body == "ProviderPage"
    end

    test "search route requires q argument" do
      conn = call(:search, %{})

      assert conn.status == 422
      assert "q" in error_fields(conn)
    end

    test "search route succeeds with required q argument" do
      conn = call(:search, %{"q" => "test"})

      assert conn.status == 200
      assert conn.resp_body == "Search"
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
      assert body["errors"] != []
    end

    test "each error carries the full RPC error shape" do
      conn = call(:login, %{})

      for error <- json_body(conn)["errors"] do
        assert is_binary(error["type"])
        assert is_binary(error["message"])
        assert is_binary(error["shortMessage"])
        assert is_map(error["vars"])
        assert is_list(error["fields"])
        assert is_list(error["path"])
      end
    end

    test "error keys respect the configured output_field_formatter" do
      prev = Application.get_env(:ash_typescript, :output_field_formatter)
      Application.put_env(:ash_typescript, :output_field_formatter, :pascal_case)
      on_exit(fn -> reset_env(:output_field_formatter, prev) end)

      conn = call(:login, %{})

      assert %{"Errors" => [%{"Type" => "required", "ShortMessage" => "Required field"} | _]} =
               json_body(conn)
    end

    test "cast errors and required errors can appear together" do
      conn = call(:echo_params, %{"count" => "not_a_number"})

      assert conn.status == 422

      fields_with_errors = error_fields(conn)
      # name is required and missing
      assert "name" in fields_with_errors
      # count has an invalid value
      assert "count" in fields_with_errors
    end
  end

  describe "error handler" do
    setup do
      prev = Application.get_env(:ash_typescript, :typed_controller_error_handler)
      on_exit(fn -> reset_env(:typed_controller_error_handler, prev) end)
      :ok
    end

    test "MFA error handler transforms 422 errors" do
      Application.put_env(
        :ash_typescript,
        :typed_controller_error_handler,
        {__MODULE__.TestErrorHandler, :handle, []}
      )

      conn = call(:login, %{})

      assert conn.status == 422
      body = json_body(conn)

      Enum.each(body["errors"], fn error ->
        assert error["transformed"] == true
      end)
    end

    test "MFA error handler can filter out errors by returning nil" do
      Application.put_env(
        :ash_typescript,
        :typed_controller_error_handler,
        {__MODULE__.FilteringErrorHandler, :handle, []}
      )

      conn = call(:login, %{})

      assert conn.status == 422
      body = json_body(conn)
      # FilteringErrorHandler returns nil for all errors
      assert body["errors"] == []
    end

    test "module error handler transforms errors" do
      Application.put_env(
        :ash_typescript,
        :typed_controller_error_handler,
        __MODULE__.ModuleErrorHandler
      )

      conn = call(:login, %{})

      assert conn.status == 422
      body = json_body(conn)

      # Handlers run before formatting, so keys they add are formatted too.
      Enum.each(body["errors"], fn error ->
        assert error["moduleHandled"] == true
      end)
    end
  end

  describe "show_raised_errors?" do
    setup do
      prev = Application.get_env(:ash_typescript, :typed_controller_show_raised_errors)
      on_exit(fn -> reset_env(:typed_controller_show_raised_errors, prev) end)
      :ok
    end

    test "returns generic message when show_raised_errors is false (default)" do
      Application.put_env(:ash_typescript, :typed_controller_show_raised_errors, false)

      conn = call(:raise_error, %{})

      assert conn.status == 500
      body = json_body(conn)
      error = hd(body["errors"])
      assert error["message"] == "Internal server error"
    end

    test "returns actual message when show_raised_errors is true" do
      Application.put_env(:ash_typescript, :typed_controller_show_raised_errors, true)

      conn = call(:raise_error, %{})

      assert conn.status == 500
      body = json_body(conn)
      error = hd(body["errors"])
      assert error["message"] == "test error for show_raised_errors"
    end
  end

  defp reset_env(key, nil), do: Application.delete_env(:ash_typescript, key)
  defp reset_env(key, value), do: Application.put_env(:ash_typescript, key, value)

  defmodule TestErrorHandler do
    def handle(error, _context) do
      Map.put(error, :transformed, true)
    end
  end

  describe "constraint application (Ash action-argument semantics)" do
    # The handler mirrors Ash's action-argument pipeline: cast_input, then
    # apply_constraints, then re-check allow_nil?. Strings therefore get the
    # allow_empty?: false default — "" becomes nil — and declared constraints
    # are enforced. The generated route schemas mirror this (e.g. `.min(1)`
    # on required strings).
    test "empty string is rejected for an allow_nil?: false string argument" do
      conn = call(:login, %{"code" => ""})

      assert conn.status == 422

      assert %{"errors" => [%{"type" => "required", "fields" => ["code"]}]} = json_body(conn)
    end

    test "empty string becomes nil for a nilable string argument" do
      conn = call(:echo_params, %{"name" => "alice", "bio" => ""})

      assert conn.status == 200
      assert json_body(conn)["params"]["bio"] == nil
    end

    test "strings are trimmed per the trim? default" do
      conn = call(:echo_params, %{"name" => "  alice  "})

      assert conn.status == 200
      assert json_body(conn)["params"]["name"] == "alice"
    end

    test "array arguments cast and enforce item constraints" do
      conn = call(:search, %{"q" => "elixir", "tags" => ["ash", "spark"]})
      assert conn.status == 200

      # `tags` declares `items: [min_length: 2]`
      conn = call(:search, %{"q" => "elixir", "tags" => ["ash", "x"]})
      assert conn.status == 422
      assert [%{"fields" => ["tags"], "type" => "invalid_argument"}] = json_body(conn)["errors"]
    end

    test "array arguments accept an omitted value" do
      conn = call(:search, %{"q" => "elixir"})
      assert conn.status == 200
    end

    test "declared constraints are enforced" do
      conn = call(:register, %{"username" => "x", "email" => "a@b.co", "age" => 20})

      assert conn.status == 422

      # `min_length: 3` — the placeholder stays in `message` and the value
      # lands in `vars`, so the client interpolates (as with RPC errors).
      error = error_for(conn, "username")
      assert error["type"] == "invalid_argument"
      assert error["message"] =~ "%{min}"
      assert error["vars"]["min"] == 3
    end
  end

  defmodule FilteringErrorHandler do
    def handle(_error, _context), do: nil
  end

  defmodule ModuleErrorHandler do
    def handle_error(error, _context) do
      Map.put(error, :module_handled, true)
    end
  end
end
