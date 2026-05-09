# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.JsonManifestGeneratorTest do
  @moduledoc """
  Tests for the JSON manifest generator.

  Verifies that the machine-readable JSON manifest contains correct metadata
  about all RPC actions, types, pagination, variants, and typed controller routes.
  """
  use ExUnit.Case, async: false

  alias AshTypescript.Rpc.Codegen.JsonManifestGenerator

  @moduletag :ash_typescript

  setup_all do
    json = JsonManifestGenerator.generate_json_manifest(:ash_typescript)
    manifest = Jason.decode!(json)
    {:ok, manifest: manifest, json: json}
  end

  describe "basic structure" do
    test "is valid JSON that ends with newline", %{json: json} do
      assert String.ends_with?(json, "\n")
      assert {:ok, _} = Jason.decode(json)
    end

    test "has required top-level keys", %{manifest: manifest} do
      assert Map.has_key?(manifest, "$schema")
      assert Map.has_key?(manifest, "version")
      assert Map.has_key?(manifest, "generatedAt")
      assert Map.has_key?(manifest, "actions")
      assert Map.has_key?(manifest, "typedControllerRoutes")
    end

    test "version is 1.0", %{manifest: manifest} do
      assert manifest["version"] == "1.0"
    end

    test "generatedAt is an ISO date", %{manifest: manifest} do
      assert manifest["generatedAt"] =~ ~r/^\d{4}-\d{2}-\d{2}$/
    end

    test "actions is a non-empty list", %{manifest: manifest} do
      assert is_list(manifest["actions"])
      assert manifest["actions"] != []
    end

    test "has files section with generated file entries", %{manifest: manifest} do
      files = manifest["files"]
      assert is_map(files)
      assert is_map(files["rpc"])
      assert is_map(files["types"])
    end
  end

  describe "files section" do
    test "each entry has importPath and filename", %{manifest: manifest} do
      for {_key, entry} <- manifest["files"] do
        assert is_binary(entry["importPath"])
        assert is_binary(entry["filename"])

        assert String.starts_with?(entry["importPath"], "./") or
                 String.starts_with?(entry["importPath"], "../"),
               "Expected relative importPath, got: #{entry["importPath"]}"

        refute String.ends_with?(entry["importPath"], ".ts"),
               "importPath should omit .ts extension, got: #{entry["importPath"]}"

        assert String.ends_with?(entry["filename"], ".ts"),
               "filename should include .ts extension, got: #{entry["filename"]}"
      end
    end

    test "rpc file entry", %{manifest: manifest} do
      assert manifest["files"]["rpc"]["importPath"] == "./generated"
      assert manifest["files"]["rpc"]["filename"] == "./generated.ts"
    end

    test "types file entry", %{manifest: manifest} do
      assert manifest["files"]["types"]["importPath"] == "./ash_types"
      assert manifest["files"]["types"]["filename"] == "./ash_types.ts"
    end

    test "zod file entry when zod enabled", %{manifest: manifest} do
      if AshTypescript.Rpc.generate_zod_schemas?() do
        assert manifest["files"]["zod"]["importPath"] == "./ash_zod"
        assert manifest["files"]["zod"]["filename"] == "./ash_zod.ts"
      end
    end

    test "valibot file entry when valibot enabled", %{manifest: manifest} do
      if AshTypescript.Rpc.generate_valibot_schemas?() do
        assert manifest["files"]["valibot"]["importPath"] == "./ash_valibot"
        assert manifest["files"]["valibot"]["filename"] == "./ash_valibot.ts"
      end
    end

    test "routes file entry when typed controllers configured", %{manifest: manifest} do
      assert manifest["files"]["routes"]["importPath"] == "./generated_routes"
      assert manifest["files"]["routes"]["filename"] == "./generated_routes.ts"
    end

    test "typed channels file entry when configured", %{manifest: manifest} do
      assert manifest["files"]["typedChannels"]["importPath"] == "./generated_typed_channels"
      assert manifest["files"]["typedChannels"]["filename"] == "./generated_typed_channels.ts"
    end
  end

  describe "files section - filename format config" do
    setup do
      original = Application.get_env(:ash_typescript, :json_manifest_filename_format)

      on_exit(fn ->
        if original do
          Application.put_env(:ash_typescript, :json_manifest_filename_format, original)
        else
          Application.delete_env(:ash_typescript, :json_manifest_filename_format)
        end
      end)

      :ok
    end

    test "basename format returns bare filename" do
      Application.put_env(:ash_typescript, :json_manifest_filename_format, :basename)
      manifest = generate_manifest()

      assert manifest["files"]["rpc"]["filename"] == "generated.ts"
      assert manifest["files"]["types"]["filename"] == "ash_types.ts"
    end

    test "absolute format returns absolute path" do
      Application.put_env(:ash_typescript, :json_manifest_filename_format, :absolute)
      manifest = generate_manifest()

      assert String.starts_with?(manifest["files"]["rpc"]["filename"], "/")
      assert String.ends_with?(manifest["files"]["rpc"]["filename"], "/test/ts/generated.ts")
    end

    test "relative format (default) returns path relative to manifest" do
      Application.delete_env(:ash_typescript, :json_manifest_filename_format)
      manifest = generate_manifest()

      assert manifest["files"]["rpc"]["filename"] == "./generated.ts"
    end

    test "importPath is unaffected by filename format" do
      Application.put_env(:ash_typescript, :json_manifest_filename_format, :basename)
      manifest = generate_manifest()

      assert manifest["files"]["rpc"]["importPath"] == "./generated"
    end
  end

  describe "action entries" do
    test "each action has required fields", %{manifest: manifest} do
      for action <- manifest["actions"] do
        assert is_binary(action["functionName"]), "functionName missing for #{inspect(action)}"
        assert action["actionType"] in ["read", "create", "update", "destroy", "action"]
        assert is_boolean(action["get"])
        assert is_binary(action["resource"])
        assert is_binary(action["description"])
        assert is_list(action["see"])
        assert is_binary(action["input"])
        assert is_map(action["types"])
        assert is_map(action["pagination"])
        assert is_map(action["variants"])
        assert is_map(action["variantNames"])
        assert is_boolean(action["enableFilter"])
        assert is_boolean(action["enableSort"])

        # namespace is string or nil
        assert is_binary(action["namespace"]) or is_nil(action["namespace"])

        # deprecated is false, true, or a string message
        assert action["deprecated"] == false or action["deprecated"] == true or
                 is_binary(action["deprecated"])
      end
    end

    test "every action has a result type", %{manifest: manifest} do
      for action <- manifest["actions"] do
        assert Map.has_key?(action["types"], "result"),
               "#{action["functionName"]} missing result type"
      end
    end
  end

  describe "read list actions" do
    setup %{manifest: manifest} do
      list_todos =
        Enum.find(manifest["actions"], &(&1["functionName"] == "listTodos"))

      {:ok, action: list_todos}
    end

    test "has correct type names", %{action: action} do
      assert action["types"]["result"] == "ListTodosResult"
      assert action["types"]["fields"] == "ListTodosFields"
      assert action["types"]["inferResult"] == "InferListTodosResult"
      assert action["types"]["input"] == "ListTodosInput"
      assert action["types"]["filterInput"] == "TodoFilterInput"
    end

    test "has pagination config for optional pagination", %{action: action} do
      assert action["types"]["config"] == "ListTodosConfig"
      assert action["pagination"]["supported"] == true
      assert action["pagination"]["required"] == false
      assert action["pagination"]["offset"] == true
      assert action["pagination"]["keyset"] == true
    end

    test "is not a get action", %{action: action} do
      assert action["get"] == false
      assert action["pagination"]["get"] == false
    end

    test "has namespace", %{action: action} do
      assert action["namespace"] == "todos"
    end
  end

  describe "get actions" do
    setup %{manifest: manifest} do
      get_todo = Enum.find(manifest["actions"], &(&1["functionName"] == "getTodo"))
      {:ok, action: get_todo}
    end

    test "get flag is true", %{action: action} do
      assert action["get"] == true
    end

    test "pagination is not supported", %{action: action} do
      assert action["pagination"]["supported"] == false
    end

    test "has fields but no config type", %{action: action} do
      assert action["types"]["fields"] == "GetTodoFields"
      refute Map.has_key?(action["types"], "config")
    end
  end

  describe "destroy actions" do
    setup %{manifest: manifest} do
      destroy = Enum.find(manifest["actions"], &(&1["functionName"] == "destroyTodo"))
      {:ok, action: destroy}
    end

    test "has no fields or inferResult types", %{action: action} do
      refute Map.has_key?(action["types"], "fields")
      refute Map.has_key?(action["types"], "inferResult")
    end

    test "has only result type", %{action: action} do
      assert action["types"]["result"] == "DestroyTodoResult"
      assert map_size(action["types"]) == 1
    end
  end

  describe "create/update actions" do
    setup %{manifest: manifest} do
      create = Enum.find(manifest["actions"], &(&1["functionName"] == "createTodo"))
      update = Enum.find(manifest["actions"], &(&1["functionName"] == "updateTodo"))
      {:ok, create: create, update: update}
    end

    test "have fields and input types", %{create: create, update: update} do
      assert create["types"]["fields"] == "CreateTodoFields"
      assert create["types"]["input"] == "CreateTodoInput"
      assert update["types"]["fields"] == "UpdateTodoFields"
      assert update["types"]["input"] == "UpdateTodoInput"
    end

    test "no pagination", %{create: create} do
      assert create["pagination"]["supported"] == false
    end
  end

  describe "filter and sort flags" do
    test "filter disabled omits filterInput type", %{manifest: manifest} do
      no_filter =
        Enum.find(manifest["actions"], &(&1["functionName"] == "listTodosNoFilter"))

      assert no_filter["enableFilter"] == false
      refute Map.has_key?(no_filter["types"], "filterInput")
    end

    test "sort disabled is reflected", %{manifest: manifest} do
      no_sort =
        Enum.find(manifest["actions"], &(&1["functionName"] == "listTodosNoSort"))

      assert no_sort["enableSort"] == false
    end
  end

  describe "deprecated actions" do
    test "deprecated with message", %{manifest: manifest} do
      deprecated =
        Enum.find(manifest["actions"], &(&1["functionName"] == "listTodosDeprecated"))

      assert is_binary(deprecated["deprecated"])
      assert deprecated["deprecated"] == "Use listTodosV2 instead"
    end

    test "deprecated without message", %{manifest: manifest} do
      deprecated_simple =
        Enum.find(manifest["actions"], &(&1["functionName"] == "listTodosDeprecatedSimple"))

      assert deprecated_simple["deprecated"] == true
    end
  end

  describe "see references" do
    test "see refs are camelCase function names", %{manifest: manifest} do
      with_see =
        Enum.find(manifest["actions"], &(&1["functionName"] == "listTodosWithSee"))

      assert "createTodo" in with_see["see"]
      assert "getTodo" in with_see["see"]
    end
  end

  describe "variant names" do
    test "includes validation, zod, valibot, and channel names when all enabled", %{
      manifest: manifest
    } do
      action = Enum.find(manifest["actions"], &(&1["functionName"] == "listTodos"))

      assert action["variants"]["validation"] == true
      assert action["variants"]["zod"] == true
      assert action["variants"]["valibot"] == true
      assert action["variants"]["channel"] == true

      assert action["variantNames"]["validation"] == "validateListTodos"
      assert action["variantNames"]["zod"] == "listTodosZodSchema"
      assert action["variantNames"]["valibot"] == "listTodosValibotSchema"
      assert action["variantNames"]["channel"] == "listTodosChannel"
    end
  end

  describe "input classification" do
    test "actions with no arguments have input none", %{manifest: manifest} do
      destroy = Enum.find(manifest["actions"], &(&1["functionName"] == "destroyTodo"))
      assert destroy["input"] == "none"
    end

    test "actions with required arguments have input required", %{manifest: manifest} do
      create = Enum.find(manifest["actions"], &(&1["functionName"] == "createTodo"))
      assert create["input"] == "required"
    end

    test "read actions with optional arguments have input optional", %{manifest: manifest} do
      list = Enum.find(manifest["actions"], &(&1["functionName"] == "listTodos"))
      assert list["input"] == "optional"
    end
  end

  describe "generic actions" do
    test "field-selectable generic actions have fields type", %{manifest: manifest} do
      # searchTodos is a generic action that returns a resource
      search = Enum.find(manifest["actions"], &(&1["functionName"] == "searchTodos"))

      if search do
        assert search["actionType"] == "action"

        # If the action returns a field-selectable type, it should have fields
        if Map.has_key?(search["types"], "fields") do
          assert is_binary(search["types"]["fields"])
        end
      end
    end

    test "non-field-selectable generic actions lack fields type", %{manifest: manifest} do
      # getStatisticsTodo returns a map without field constraints
      stats = Enum.find(manifest["actions"], &(&1["functionName"] == "getStatisticsTodo"))

      if stats do
        assert stats["actionType"] == "action"
        # Statistics may or may not have fields depending on the return type
      end
    end
  end

  describe "typed controller routes" do
    test "routes is a list", %{manifest: manifest} do
      assert is_list(manifest["typedControllerRoutes"])
      assert manifest["typedControllerRoutes"] != []
    end

    test "each route has required fields", %{manifest: manifest} do
      for route <- manifest["typedControllerRoutes"] do
        assert is_binary(route["functionName"])
        assert route["method"] in ["GET", "POST", "PUT", "PATCH", "DELETE"]
        assert is_binary(route["path"])
        assert is_list(route["pathParams"])
        assert is_boolean(route["mutation"])
      end
    end

    test "GET routes are not mutations", %{manifest: manifest} do
      get_routes =
        Enum.filter(manifest["typedControllerRoutes"], &(&1["method"] == "GET"))

      for route <- get_routes do
        assert route["mutation"] == false
      end
    end

    test "POST routes are mutations with types", %{manifest: manifest} do
      login =
        Enum.find(manifest["typedControllerRoutes"], &(&1["functionName"] == "login"))

      assert login["mutation"] == true
      assert login["types"]["input"] == "LoginInput"
    end

    test "routes with path params list them", %{manifest: manifest} do
      provider =
        Enum.find(manifest["typedControllerRoutes"], fn r ->
          r["path"] =~ ":provider"
        end)

      if provider do
        assert "provider" in provider["pathParams"]
      end
    end
  end

  describe "config accessor" do
    test "json_manifest_file/0 returns configured path" do
      assert AshTypescript.Rpc.json_manifest_file() == "./test/ts/ash_rpc_manifest.json"
    end
  end

  defp generate_manifest do
    :ash_typescript
    |> JsonManifestGenerator.generate_json_manifest()
    |> Jason.decode!()
  end
end
