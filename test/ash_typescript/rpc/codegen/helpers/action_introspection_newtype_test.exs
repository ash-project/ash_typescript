# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Codegen.Helpers.ActionIntrospectionNewTypeTest do
  @moduledoc """
  Tests that ActionIntrospection correctly classifies NewType-wrapped return types.

  These tests verify that `compute_action_returns_field_selectable_type?/2` unwraps
  NewTypes before classification, matching the runtime behavior in field_selector.ex.
  Actions come from the manifest, as they do in codegen.
  """
  use ExUnit.Case, async: true

  alias AshTypescript.Rpc.Codegen.Helpers.ActionIntrospection
  alias AshTypescript.Test.{Task, Todo}

  defp classify(resource, action_name) do
    resource
    |> ActionIntrospection.get_action!(action_name)
    |> ActionIntrospection.compute_action_returns_field_selectable_type?(
      AshTypescript.type_lookup()
    )
  end

  defp field_names(fields), do: Enum.map(fields, & &1.name)

  describe "compute_action_returns_field_selectable_type?/2 with NewType-wrapped map" do
    test "single NewType wrapping :map with fields returns {:ok, :typed_map, fields}" do
      assert {:ok, :typed_map, fields} = classify(Task, :get_suggestion)
      assert [:category, :name, :score] -- field_names(fields) == []
    end

    test "array of NewType wrapping :map with fields returns {:ok, :array_of_typed_map, fields}" do
      assert {:ok, :array_of_typed_map, fields} = classify(Task, :list_suggestions)
      assert [:category, :name, :score] -- field_names(fields) == []
    end
  end

  describe "action_returns_field_selectable_type?/1 preserves existing behavior" do
    test "non-action type returns :not_generic_action" do
      action = %{type: :read}

      assert {:error, :not_generic_action} =
               ActionIntrospection.action_returns_field_selectable_type?(action)
    end

    test "direct :map with fields still works" do
      assert {:ok, :typed_map, fields} = classify(Todo, :get_statistics)
      assert [:completed, :total] -- field_names(fields) == []
    end

    test "direct :map without fields returns unconstrained_map" do
      assert {:ok, :unconstrained_map, nil} = classify(Todo, :get_custom_data)
    end
  end
end
