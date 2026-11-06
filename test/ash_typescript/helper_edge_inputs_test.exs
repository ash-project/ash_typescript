# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.HelperEdgeInputsTest do
  @moduledoc """
  The documented edge inputs of small public helpers: `nil` and non-module
  arguments, the manifest node shapes `TypeMapper`'s wrappers accept, and the
  word lists the name checks extend.
  """
  use ExUnit.Case, async: true

  alias Ash.Info.Manifest.Type
  alias AshTypescript.Codegen.{CustomTypeAliases, TypeMapper}
  alias AshTypescript.CustomTypes
  alias AshTypescript.CustomTypes.{Builtin, Scalar}
  alias AshTypescript.Manifest.Custom
  alias AshTypescript.TypedController.Transformers.FoldArgumentConstraints
  alias AshTypescript.TypeSystem.Introspection

  test "CustomTypeAliases.plain_name/1 of no definition is nil" do
    assert CustomTypeAliases.plain_name(nil) == nil
  end

  test "Helpers.has_typescript_field_names?/1 is false for nil and non-modules" do
    refute AshTypescript.Helpers.has_typescript_field_names?(nil)
    refute AshTypescript.Helpers.has_typescript_field_names?("AshTypescript.Test.Todo")
  end

  test "Introspection.is_custom_type?/1 is false for a non-module" do
    refute Introspection.is_custom_type?("AshTypescript.Test.Todo")
  end

  test "Introspection.reachable_nodes/1 skips roots that aren't types" do
    string = %Type{kind: :string}
    assert Introspection.reachable_nodes([nil, string]) == [string]
  end

  test "Introspection.resolve_named_type/1 of an opaque scalar custom type is its definition" do
    ref = %Type{kind: :type_ref, module: AshTypescript.Test.CustomIdentifier}
    assert %Type{kind: :unknown} = Introspection.resolve_named_type(ref)
  end

  test "Custom.entrypoint_domain/1 of no entrypoint is nil" do
    assert Custom.entrypoint_domain(nil) == nil
  end

  test "Scalar.normalize_constraints/1 of no constraints is empty" do
    assert Scalar.normalize_constraints(nil) == []
  end

  test "CustomTypes.fields_fun/1 without persisted custom types uses the built-ins" do
    assert CustomTypes.fields_fun(nil).(AshMoney.Types.Money) ==
             CustomTypes.fields_for(AshMoney.Types.Money, %{}, Builtin.by_module())

    assert CustomTypes.fields_fun(nil).(AshMoney.Types.Money) != nil
  end

  test "NameValidation's word lists hold JavaScript's reserved words and TypeScript's type names" do
    assert "class" in AshTypescript.NameValidation.js_reserved_words()
    assert "string" in AshTypescript.NameValidation.ts_type_keywords()
  end

  test "FoldArgumentConstraints runs only before GenerateController" do
    assert FoldArgumentConstraints.before?(
             AshTypescript.TypedController.Transformers.GenerateController
           )

    refute FoldArgumentConstraints.before?(Spark.Dsl.Transformer)
  end

  describe "TypeMapper" do
    setup do
      todo = Map.fetch!(AshTypescript.resource_lookup(), AshTypescript.Test.Todo)
      title = Enum.find(Ash.Info.Manifest.Resource.all_fields(todo), &(&1.name == :title))
      %{title: title}
    end

    test "get_ts_input_type/1 maps a manifest field's type", %{title: title} do
      assert TypeMapper.get_ts_input_type(title) == "string"
    end

    test "get_ts_type/1 maps a manifest field, argument and metadata", %{title: title} do
      assert TypeMapper.get_ts_type(title) == "string"

      assert TypeMapper.get_ts_type(%Ash.Info.Manifest.Argument{type: %Type{kind: :integer}}) ==
               "number"

      assert TypeMapper.get_ts_type(%Ash.Info.Manifest.Metadata{type: %Type{kind: :boolean}}) ==
               "boolean"
    end

    test "get_ts_type/1 maps an aggregate kind" do
      assert TypeMapper.get_ts_type(:count) == "number"
      assert TypeMapper.get_ts_type(:list) == "any[]"
    end

    test "build_union_input_type_from_members/2 with no member kept is any" do
      union = %Type{kind: :union, members: [%{name: :a, type: %Type{kind: :string}}]}
      assert TypeMapper.build_union_input_type_from_members(union, fn _ -> false end) == "any"
    end

    test "map_type/3 of no type is null" do
      assert TypeMapper.map_type(nil, [], :output) == "null"
    end

    test "raise_unsupported_type!/1 of a module names it" do
      assert_raise RuntimeError, ~r/^unsupported type MyApp.Opaque — AshTypescript cannot/, fn ->
        TypeMapper.raise_unsupported_type!(MyApp.Opaque)
      end
    end
  end
end
