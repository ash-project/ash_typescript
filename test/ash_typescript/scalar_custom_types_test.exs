# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.ScalarCustomTypesTest do
  # `scalar` entries of the manifest's `custom_types` section map custom types
  # the app doesn't own (formerly `config :ash_typescript, :type_mapping_overrides`).
  # Variants of the test manifest go through `AshTypescript.with_manifest/2`.
  use ExUnit.Case, async: false

  alias AshTypescript.Codegen
  alias AshTypescript.CustomTypes.Scalar
  alias AshTypescript.Manifest.Custom
  alias AshTypescript.Test.CustomIdentifier
  alias AshTypescript.Test.Todo.PriorityScore

  defp with_declared(update, fun) do
    manifest = AshTypescript.manifest()
    manifest = update_in(manifest.custom.ash_typescript.custom_types.declared, update)
    AshTypescript.with_manifest(manifest, fun)
  end

  describe "the test manifest's scalar entries" do
    test "are read from the manifest" do
      assert %Scalar{module: CustomIdentifier, type: Ash.Type.String} =
               Custom.declared_custom_type(nil, CustomIdentifier)
    end

    test "a module without an entry has none" do
      assert Custom.declared_custom_type(nil, PriorityScore) == nil
    end
  end

  describe "scalar entries in codegen" do
    test "get_ts_type maps a declared scalar to its alias" do
      assert Codegen.get_ts_type(%{type: CustomIdentifier, constraints: []}) == "CustomIdentifier"
    end

    test "get_ts_type maps an array of a declared scalar" do
      assert Codegen.get_ts_type(%{type: {:array, CustomIdentifier}, constraints: []}) ==
               "Array<CustomIdentifier>"
    end

    test "an entry takes precedence over the typescript_type/0 callback" do
      entry = %Scalar{module: PriorityScore, type: Ash.Type.String, ts_type: "Score"}

      with_declared(&Map.put(&1, PriorityScore, entry), fn ->
        assert Codegen.get_ts_type(%{type: PriorityScore, constraints: []}) == "Score"
      end)
    end
  end

  describe "resource schema generation with scalar entries" do
    test "Task resource includes custom_id mapped by its entry" do
      schema =
        Codegen.generate_unified_resource_schema(AshTypescript.Test.Task, [
          AshTypescript.Test.Task
        ])

      assert schema =~ "customId: CustomIdentifier | null"
    end
  end

  describe "a type without an entry" do
    test "raises, pointing to the custom_types section" do
      with_declared(&Map.delete(&1, CustomIdentifier), fn ->
        error =
          assert_raise RuntimeError, ~r/unsupported type/, fn ->
            Codegen.get_ts_type(%{type: CustomIdentifier, constraints: []})
          end

        assert Exception.message(error) =~ "custom_types"
        refute Exception.message(error) =~ "type_mapping_overrides"
      end)
    end
  end

  describe "multiple scalar entries" do
    test "each entry maps its own module" do
      another = %Scalar{module: PriorityScore, type: Ash.Type.Integer, ts_type: "Score"}

      with_declared(&Map.put(&1, PriorityScore, another), fn ->
        assert Codegen.get_ts_type(%{type: CustomIdentifier, constraints: []}) ==
                 "CustomIdentifier"

        assert Codegen.get_ts_type(%{type: PriorityScore, constraints: []}) == "Score"
      end)
    end
  end
end
