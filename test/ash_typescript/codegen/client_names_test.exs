# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.ClientNamesTest do
  use ExUnit.Case, async: true

  @moduletag :ash_typescript

  alias Ash.Info.Manifest
  alias AshTypescript.Codegen.ClientNames

  defmodule NotInManifest do
    @moduledoc false
    use Ash.Type.NewType,
      subtype_of: :map,
      constraints: [fields: [is_set?: [type: :boolean]]]
  end

  test "resource fields come from the decoration (struct or module)" do
    user = AshTypescript.resource_lookup()[AshTypescript.Test.User]
    assert ClientNames.resource_field(user, :is_active?) == "isActive"
    assert ClientNames.resource_field(AshTypescript.Test.User, :address_line_1) == "addressLine1"
    assert ClientNames.resource_field(AshTypescript.Test.User, :todos) == "todos"
  end

  test "a resource copy without custom.ash_rpc is resolved through the lookup" do
    user = AshTypescript.resource_lookup()[AshTypescript.Test.User]
    assert ClientNames.resource_field(%{user | custom: %{}}, :is_active?) == "isActive"
  end

  test "codegen raises for a named type outside the manifest instead of naming it itself" do
    assert_raise ArgumentError, ~r/not in the manifest/, fn ->
      AshTypescript.Codegen.TypeMapper.map_type(
        %Manifest.Type{kind: :type_ref, module: NotInManifest},
        [],
        :output
      )
    end
  end

  test "names follow with_manifest/2" do
    m =
      AshTypescript.Manifest.redecorate(AshTypescript.manifest(), output_formatter: :pascal_case)

    AshTypescript.with_manifest(m, fn ->
      assert ClientNames.resource_field(AshTypescript.Test.User, :name) == "Name"
      assert ClientNames.resource_field(AshTypescript.Test.User, :is_active?) == "isActive"
    end)
  end

  test "calculation arguments come from the decoration" do
    assert ClientNames.calculation_argument(AshTypescript.Test.Todo, :filtered_data, :after_date) ==
             "afterDate"
  end

  test "type fields resolve type_refs" do
    ref = %Manifest.Type{kind: :type_ref, module: AshTypescript.Test.TaskStats}
    assert ClientNames.type_field(ref, :is_urgent?) == "isUrgent"
  end

  test "union members come from the decoration" do
    todo = AshTypescript.resource_lookup()[AshTypescript.Test.Todo]
    content = Manifest.Resource.get_field(todo, :content)
    assert ClientNames.union_member(content.type, :priority_value) == "priorityValue"
  end

  test "metadata fields come from the wire entrypoint" do
    wire = ClientNames.wire_entrypoint!(:read_tasks_with_mapped_metadata)
    assert ClientNames.metadata_field(wire, :meta_1) == "meta1"
  end

  test "action inputs come from expected_input_keys" do
    action = AshTypescript.action_lookup()[{AshTypescript.Test.User, :read_with_invalid_arg}]
    assert ClientNames.action_input(AshTypescript.Test.User, action, :is_active?) == "isActive"
  end

  test "a miss or an undecorated node raises, naming node and field" do
    user = AshTypescript.resource_lookup()[AshTypescript.Test.User]

    assert_raise ArgumentError, ~r/:nope.*AshTypescript.Test.User/, fn ->
      ClientNames.resource_field(user, :nope)
    end

    assert_raise ArgumentError, ~r/not decorated/, fn ->
      ClientNames.type_field(%Manifest.Type{kind: :map, fields: [%{name: :a}]}, :a)
    end

    assert_raise ArgumentError, ~r/NotAModule/, fn ->
      ClientNames.resolve_type!(%Manifest.Type{kind: :type_ref, module: NotAModule})
    end

    assert_raise ArgumentError, ~r/no_such_rpc/, fn ->
      ClientNames.wire_entrypoint!(:no_such_rpc)
    end

    assert_raise ArgumentError, ~r/NotAResource.*not in the manifest/, fn ->
      ClientNames.resource_field(NotAResource, :id)
    end
  end
end
