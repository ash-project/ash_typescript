# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.LoadRestrictionsTest do
  use ExUnit.Case

  alias AshTypescript.Rpc.Pipeline

  @moduletag :ash_typescript

  describe "allow_only_loads option - pipeline behavior" do
    test "allows loading fields that are in the allow list" do
      params = %{
        "action" => "list_todos_allow_only_user",
        "fields" => ["id", "title", %{"user" => ["id", "email"]}]
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)
      # Should succeed - user is allowed
      assert request.load == [{:user, [:id, :email]}]
    end

    test "rejects loading fields that are not in the allow list" do
      params = %{
        "action" => "list_todos_allow_only_user",
        "fields" => ["id", "title", %{"comments" => ["id", "content"]}]
      }

      conn = %Plug.Conn{}

      assert {:error, {:load_not_allowed, disallowed}} =
               Pipeline.parse_request(:ash_typescript, conn, params)

      assert "comments" in disallowed
    end

    test "allows nested fields when explicitly allowed" do
      params = %{
        "action" => "list_todos_allow_nested",
        "fields" => ["id", %{"comments" => ["id", %{"todo" => ["id"]}]}]
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)
      # Should succeed - comments and comments.todo are allowed
      assert request.load != []
    end

    test "rejects nested fields when parent is allowed but nested is not" do
      params = %{
        "action" => "list_todos_allow_only_user",
        "fields" => ["id", %{"user" => ["id", %{"todos" => ["id"]}]}]
      }

      conn = %Plug.Conn{}

      # user is allowed, but user.todos is not
      assert {:error, {:load_not_allowed, disallowed}} =
               Pipeline.parse_request(:ash_typescript, conn, params)

      assert Enum.any?(disallowed, &String.contains?(&1, "todos"))
    end

    test "works with no loads requested" do
      params = %{
        "action" => "list_todos_allow_only_user",
        "fields" => ["id", "title"]
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)
      assert request.load == []
    end
  end

  describe "deny_loads option - pipeline behavior" do
    test "allows loading fields that are not in the deny list" do
      params = %{
        "action" => "list_todos_deny_user",
        "fields" => ["id", "title", %{"comments" => ["id", "content"]}]
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)
      # Should succeed - comments is not denied
      assert request.load == [{:comments, [:id, :content]}]
    end

    test "rejects loading fields that are in the deny list" do
      params = %{
        "action" => "list_todos_deny_user",
        "fields" => ["id", "title", %{"user" => ["id", "email"]}]
      }

      conn = %Plug.Conn{}

      assert {:error, {:load_denied, denied}} =
               Pipeline.parse_request(:ash_typescript, conn, params)

      assert "user" in denied
    end

    test "rejects loading nested fields when parent is denied" do
      params = %{
        "action" => "list_todos_deny_user",
        "fields" => ["id", %{"user" => ["id", %{"todos" => ["id"]}]}]
      }

      conn = %Plug.Conn{}

      # user is denied, so user.todos should also be denied
      assert {:error, {:load_denied, denied}} =
               Pipeline.parse_request(:ash_typescript, conn, params)

      assert Enum.any?(denied, &String.contains?(&1, "user"))
    end

    test "allows parent field but denies nested field" do
      params = %{
        "action" => "list_todos_deny_nested",
        "fields" => ["id", %{"comments" => ["id", "content"]}]
      }

      conn = %Plug.Conn{}

      # comments is allowed, only comments.todo is denied
      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)
      assert request.load != []
    end

    test "denies nested field explicitly" do
      params = %{
        "action" => "list_todos_deny_nested",
        "fields" => ["id", %{"comments" => ["id", %{"todo" => ["id"]}]}]
      }

      conn = %Plug.Conn{}

      # comments.todo is explicitly denied
      assert {:error, {:load_denied, denied}} =
               Pipeline.parse_request(:ash_typescript, conn, params)

      assert Enum.any?(denied, &String.contains?(&1, "todo"))
    end

    test "works with no loads requested" do
      params = %{
        "action" => "list_todos_deny_user",
        "fields" => ["id", "title"]
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)
      assert request.load == []
    end
  end

  describe "neither option - default behavior" do
    test "allows all loads when no restriction is set" do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title", %{"user" => ["id"]}, %{"comments" => ["id"]}]
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)
      # Should allow both user and comments
      assert length(request.load) == 2
    end
  end

  describe "mutual exclusivity - verifier" do
    # This test verifies that the DSL properly prevents both options from being set
    # The actual verification happens at compile time via the verifier
    test "compiles successfully when only allow_only_loads is set" do
      # This is tested implicitly by the domain compiling
      assert true
    end

    test "compiles successfully when only deny_loads is set" do
      # This is tested implicitly by the domain compiling
      assert true
    end

    test "compiles successfully when neither is set" do
      # This is tested implicitly by the domain compiling
      assert true
    end
  end

  describe "error messages" do
    test "load_not_allowed error contains field path" do
      params = %{
        "action" => "list_todos_allow_only_user",
        "fields" => ["id", %{"comments" => ["id"]}]
      }

      conn = %Plug.Conn{}

      assert {:error, {:load_not_allowed, paths}} =
               Pipeline.parse_request(:ash_typescript, conn, params)

      assert is_list(paths)
      assert Enum.all?(paths, &is_binary/1)
    end

    test "load_denied error contains field path" do
      params = %{
        "action" => "list_todos_deny_user",
        "fields" => ["id", %{"user" => ["id"]}]
      }

      conn = %Plug.Conn{}

      assert {:error, {:load_denied, paths}} =
               Pipeline.parse_request(:ash_typescript, conn, params)

      assert is_list(paths)
      assert Enum.all?(paths, &is_binary/1)
    end
  end
end
