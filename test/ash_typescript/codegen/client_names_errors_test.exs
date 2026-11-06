# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.ClientNamesErrorsTest do
  # Each raise of ClientNames, against the configured manifest or a copy of it
  # with one node's custom.ash_rpc removed (through with_manifest/2).
  use ExUnit.Case, async: true

  @moduletag :ash_typescript

  alias Ash.Info.Manifest
  alias AshTypescript.Codegen.ClientNames
  alias AshTypescript.Test.{TaskStats, Todo, TodoMetadata, User}

  @rejects "codegen would emit a name the runtime rejects"

  defp without_decoration(fun) do
    manifest = AshTypescript.manifest()

    resources =
      Enum.map(manifest.resources, fn
        %Manifest.Resource{module: User} = user ->
          %{user | custom: Map.delete(user.custom, :ash_rpc)}

        resource ->
          resource
      end)

    types =
      Enum.map(manifest.types, fn
        %Manifest.Type{module: TaskStats} = type ->
          %{type | custom: Map.delete(type.custom, :ash_rpc)}

        type ->
          type
      end)

    %{manifest | resources: resources, types: types}
    |> AshRpc.Manifest.put_lookups()
    |> AshTypescript.with_manifest(fun)
  end

  defp todo, do: AshTypescript.resource_lookup()[Todo]

  describe "resources" do
    test "an undecorated resource in the manifest" do
      without_decoration(fn ->
        error = assert_raise ArgumentError, fn -> ClientNames.resource_field(User, :name) end

        assert error.message ==
                 "resource AshTypescript.Test.User is not decorated (no custom.ash_rpc)"
      end)
    end

    test "a calculation argument without a client name" do
      error =
        assert_raise ArgumentError, fn ->
          ClientNames.calculation_argument(Todo, :filtered_data, :nope)
        end

      assert error.message ==
               "no client name for :nope on calculation :filtered_data on resource " <>
                 "AshTypescript.Test.Todo; #{@rejects}"
    end

    test "an argument of a calculation that has none" do
      error =
        assert_raise ArgumentError, fn ->
          ClientNames.calculation_argument(Todo, :no_such_calculation, :after_date)
        end

      assert error.message ==
               "no client name for :after_date on calculation :no_such_calculation on resource " <>
                 "AshTypescript.Test.Todo; #{@rejects}"
    end
  end

  describe "action inputs" do
    setup do
      %{action: AshTypescript.action_lookup()[{User, :read_with_invalid_arg}]}
    end

    test "an undecorated action", %{action: action} do
      undecorated = %{action | custom: Map.delete(action.custom, :ash_rpc)}

      # apply/3: the type checker sees that an undecorated action always raises.
      error =
        assert_raise ArgumentError, fn ->
          apply(ClientNames, :action_input, [User, undecorated, :is_active?])
        end

      assert error.message ==
               "action :read_with_invalid_arg on resource AshTypescript.Test.User is not " <>
                 "decorated (no custom.ash_rpc expected_input_keys); cannot name input :is_active?"
    end

    test "an input the action doesn't take", %{action: action} do
      user = AshTypescript.resource_lookup()[User]
      error = assert_raise ArgumentError, fn -> ClientNames.action_input(user, action, :nope) end

      assert error.message ==
               "no client name for :nope on action :read_with_invalid_arg on resource " <>
                 "AshTypescript.Test.User; #{@rejects}"
    end
  end

  describe "type fields" do
    test "a resource-typed field names the field through the resource" do
      metadata = Manifest.Resource.get_field(todo(), :metadata)
      assert metadata.type.kind == :embedded_resource
      assert ClientNames.type_field(metadata.type, :priority_score) == "priorityScore"

      error = assert_raise ArgumentError, fn -> ClientNames.type_field(metadata.type, :nope) end

      assert error.message ==
               "no client name for :nope on resource #{inspect(TodoMetadata)}; #{@rejects}"
    end

    test "a decorated type without the field" do
      ref = %Manifest.Type{kind: :type_ref, module: TaskStats}
      error = assert_raise ArgumentError, fn -> ClientNames.type_field(ref, :nope) end

      assert error.message ==
               "no client name for :nope on type \"TaskStats\" " <>
                 "(AshTypescript.Test.TaskStats, kind :struct); #{@rejects}"
    end

    test "an undecorated named type" do
      without_decoration(fn ->
        ref = %Manifest.Type{kind: :type_ref, module: TaskStats}
        error = assert_raise ArgumentError, fn -> ClientNames.type_field(ref, :is_urgent?) end

        assert error.message ==
                 "type \"TaskStats\" (AshTypescript.Test.TaskStats, kind :struct) is not " <>
                   "decorated (no custom.ash_rpc); cannot name :is_urgent?"
      end)
    end

    test "a type that is no type_ref resolves to itself" do
      type = %Manifest.Type{kind: :map, fields: []}
      assert ClientNames.resolve_type!(type) == type
    end
  end

  describe "union members" do
    setup do
      %{content: Manifest.Resource.get_field(todo(), :content).type}
    end

    test "a type that is not a union", %{content: content} do
      ref = %Manifest.Type{kind: :type_ref, module: TaskStats}
      error = assert_raise ArgumentError, fn -> ClientNames.union_member(ref, :text) end

      assert error.message ==
               "type \"TaskStats\" (AshTypescript.Test.TaskStats, kind :struct) is not a " <>
                 "decorated union; cannot name member :text"

      undecorated = %{content | custom: Map.delete(content.custom, :ash_rpc)}
      error = assert_raise ArgumentError, fn -> ClientNames.union_member(undecorated, :text) end

      assert error.message ==
               "type \"Union\" (Ash.Type.Union, kind :union) is not a decorated union; " <>
                 "cannot name member :text"
    end

    test "a member the union doesn't have", %{content: content} do
      error = assert_raise ArgumentError, fn -> ClientNames.union_member(content, :nope) end

      assert error.message ==
               "no client name for :nope on type \"Union\" (Ash.Type.Union, kind :union); #{@rejects}"
    end
  end

  test "a metadata field the entrypoint doesn't expose" do
    wire = ClientNames.wire_entrypoint!(:read_tasks_with_mapped_metadata)
    error = assert_raise ArgumentError, fn -> ClientNames.metadata_field(wire, :nope) end

    assert error.message ==
             "no client name for :nope on metadata of entrypoint " <>
               "\"read_tasks_with_mapped_metadata\"; #{@rejects}"
  end
end
