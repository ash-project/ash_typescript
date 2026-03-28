# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Codegen.Helpers.ActionIntrospectionNewTypeTest do
  @moduledoc """
  Tests that ActionIntrospection correctly classifies NewType-wrapped return types.

  These tests verify that `action_returns_field_selectable_type?/1` unwraps NewTypes
  before classification, matching the runtime behavior in field_selector.ex.
  """
  use ExUnit.Case, async: true

  alias AshTypescript.Rpc.Codegen.Helpers.ActionIntrospection

  describe "action_returns_field_selectable_type?/1 with NewType-wrapped map" do
    test "single NewType wrapping :map with fields returns {:ok, :typed_map, fields}" do
      action = %{
        type: :action,
        returns: AshTypescript.Test.Suggestion,
        constraints: []
      }

      result = ActionIntrospection.action_returns_field_selectable_type?(action)

      assert {:ok, :typed_map, fields} = result
      assert Keyword.has_key?(fields, :name)
      assert Keyword.has_key?(fields, :category)
      assert Keyword.has_key?(fields, :score)
    end

    test "array of NewType wrapping :map with fields returns {:ok, :array_of_typed_map, fields}" do
      action = %{
        type: :action,
        returns: {:array, AshTypescript.Test.Suggestion},
        constraints: []
      }

      result = ActionIntrospection.action_returns_field_selectable_type?(action)

      assert {:ok, :array_of_typed_map, fields} = result
      assert Keyword.has_key?(fields, :name)
      assert Keyword.has_key?(fields, :category)
      assert Keyword.has_key?(fields, :score)
    end
  end

  describe "action_returns_field_selectable_type?/1 preserves existing behavior" do
    test "non-action type returns :not_generic_action" do
      action = %{type: :read}

      assert {:error, :not_generic_action} =
               ActionIntrospection.action_returns_field_selectable_type?(action)
    end

    test "direct Ash.Type.Map with fields still works" do
      action = %{
        type: :action,
        returns: Ash.Type.Map,
        constraints: [
          fields: [
            total: [type: :integer],
            count: [type: :integer]
          ]
        ]
      }

      assert {:ok, :typed_map, fields} =
               ActionIntrospection.action_returns_field_selectable_type?(action)

      assert Keyword.has_key?(fields, :total)
      assert Keyword.has_key?(fields, :count)
    end

    test "direct Ash.Type.Map without fields returns unconstrained_map" do
      action = %{
        type: :action,
        returns: Ash.Type.Map,
        constraints: []
      }

      assert {:ok, :unconstrained_map, nil} =
               ActionIntrospection.action_returns_field_selectable_type?(action)
    end
  end
end
