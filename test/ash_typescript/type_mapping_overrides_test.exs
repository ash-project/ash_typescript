# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.TypeMappingOverridesTest do
  use ExUnit.Case, async: false
  alias AshTypescript.Codegen
  alias AshTypescript.Test.CustomIdentifier

  setup do
    # Store original config
    original_overrides = Application.get_env(:ash_typescript, :type_mapping_overrides)

    # Set up test config
    Application.put_env(:ash_typescript, :type_mapping_overrides, [
      {CustomIdentifier, "string"}
    ])

    on_exit(fn ->
      # Restore original config
      if original_overrides do
        Application.put_env(:ash_typescript, :type_mapping_overrides, original_overrides)
      else
        Application.delete_env(:ash_typescript, :type_mapping_overrides)
      end
    end)

    :ok
  end

  describe "type mapping override configuration" do
    test "retrieves configured type mapping overrides" do
      overrides = AshTypescript.type_mapping_overrides()
      assert overrides == [{CustomIdentifier, "string"}]
    end

    test "returns empty list when no overrides configured" do
      Application.delete_env(:ash_typescript, :type_mapping_overrides)
      overrides = AshTypescript.type_mapping_overrides()
      assert overrides == []
    end
  end

  describe "type mapping override in codegen" do
    test "get_ts_type uses override for configured type" do
      result = Codegen.get_ts_type(%{type: CustomIdentifier, constraints: []})
      assert result == "string"
    end

    test "get_ts_type works with overridden type in array" do
      result = Codegen.get_ts_type(%{type: {:array, CustomIdentifier}, constraints: []})
      assert result == "Array<string>"
    end

    test "overrides take precedence over typescript_type_name callback" do
      # Even if a type has typescript_type_name callback, override should win
      # Our CustomIdentifier doesn't have the callback, but this tests the precedence
      result = Codegen.get_ts_type(%{type: CustomIdentifier, constraints: []})
      assert result == "string"
    end
  end

  describe "resource schema generation with type mapping overrides" do
    test "Task resource includes custom_id with overridden type" do
      schema =
        Codegen.generate_unified_resource_schema(AshTypescript.Test.Task, [
          AshTypescript.Test.Task
        ])

      assert schema =~ "customId: string | null"
    end
  end

  describe "type without override raises error" do
    test "custom type without override or typescript_type_name raises error" do
      # Remove the override temporarily
      Application.delete_env(:ash_typescript, :type_mapping_overrides)

      assert_raise RuntimeError, ~r/unsupported type/, fn ->
        Codegen.get_ts_type(%{type: CustomIdentifier, constraints: []})
      end
    end
  end

  describe "multiple type overrides" do
    test "supports multiple type mapping overrides" do
      # Define another test type module name
      another_type = AshTypescript.Test.AnotherCustomType

      Application.put_env(:ash_typescript, :type_mapping_overrides, [
        {CustomIdentifier, "string"},
        {another_type, "number"}
      ])

      overrides = AshTypescript.type_mapping_overrides()
      assert length(overrides) == 2
      assert {CustomIdentifier, "string"} in overrides
      assert {another_type, "number"} in overrides
    end
  end
end
