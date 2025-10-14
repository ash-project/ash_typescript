# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.RequestedFieldsProcessorTest do
  use ExUnit.Case
  alias AshTypescript.Rpc.RequestedFieldsProcessor

  describe "atomize_requested_fields/1" do
    setup do
      # Store original configuration
      original_input_field_formatter =
        Application.get_env(:ash_typescript, :input_field_formatter)

      on_exit(fn ->
        # Restore original configuration
        if original_input_field_formatter do
          Application.put_env(
            :ash_typescript,
            :input_field_formatter,
            original_input_field_formatter
          )
        else
          Application.delete_env(:ash_typescript, :input_field_formatter)
        end
      end)

      {:ok, original_input_field_formatter: original_input_field_formatter}
    end

    test "atomizes simple string fields with snake_case formatter" do
      Application.put_env(:ash_typescript, :input_field_formatter, :snake_case)

      result = RequestedFieldsProcessor.atomize_requested_fields(["id", "title", "is_overdue"])

      assert result == [:id, :title, :is_overdue]
    end

    test "atomizes simple string fields with camelCase formatter" do
      Application.put_env(:ash_typescript, :input_field_formatter, :camel_case)

      result = RequestedFieldsProcessor.atomize_requested_fields(["id", "title", "isOverdue"])

      assert result == [:id, :title, :is_overdue]
    end

    test "passes through atom fields unchanged" do
      Application.put_env(:ash_typescript, :input_field_formatter, :snake_case)

      result = RequestedFieldsProcessor.atomize_requested_fields([:id, :title, :is_overdue])

      assert result == [:id, :title, :is_overdue]
    end

    test "atomizes map keys in relationship fields with snake_case formatter" do
      Application.put_env(:ash_typescript, :input_field_formatter, :snake_case)

      result =
        RequestedFieldsProcessor.atomize_requested_fields([
          "id",
          "title",
          %{"user" => ["id", "name"]},
          %{"metadata" => ["category"]}
        ])

      assert result == [
               :id,
               :title,
               %{user: [:id, :name]},
               %{metadata: [:category]}
             ]
    end

    test "atomizes map keys in relationship fields with camelCase formatter" do
      Application.put_env(:ash_typescript, :input_field_formatter, :camel_case)

      result =
        RequestedFieldsProcessor.atomize_requested_fields([
          "id",
          "title",
          %{"user" => ["id", "name"]},
          %{"createdBy" => ["id", "userName"]}
        ])

      assert result == [
               :id,
               :title,
               %{user: [:id, :name]},
               %{created_by: [:id, :user_name]}
             ]
    end

    test "handles complex calculation with arguments format" do
      Application.put_env(:ash_typescript, :input_field_formatter, :snake_case)

      result =
        RequestedFieldsProcessor.atomize_requested_fields([
          "id",
          "title",
          %{"self" => %{"args" => %{"prefix" => "test"}}}
        ])

      assert result == [
               :id,
               :title,
               %{self: %{args: %{prefix: "test"}}}
             ]
    end

    test "handles complex calculation with arguments and fields format" do
      Application.put_env(:ash_typescript, :input_field_formatter, :camel_case)

      result =
        RequestedFieldsProcessor.atomize_requested_fields([
          "id",
          "title",
          %{
            "selfWithFields" => %{
              "args" => %{"prefix" => "test"},
              "fields" => ["id", "createdAt"]
            }
          }
        ])

      assert result == [
               :id,
               :title,
               %{self_with_fields: %{args: %{prefix: "test"}, fields: [:id, :created_at]}}
             ]
    end

    test "handles mixed atom and string keys in maps" do
      Application.put_env(:ash_typescript, :input_field_formatter, :camel_case)

      result =
        RequestedFieldsProcessor.atomize_requested_fields([
          "id",
          %{"user" => ["id", "name"]},
          # Already atom key
          %{metadata: ["category"]}
        ])

      assert result == [
               :id,
               %{user: [:id, :name]},
               %{metadata: [:category]}
             ]
    end

    test "handles nested maps recursively" do
      Application.put_env(:ash_typescript, :input_field_formatter, :camel_case)

      result =
        RequestedFieldsProcessor.atomize_requested_fields([
          "id",
          %{"deeplyNested" => %{"nestedField" => %{"innerField" => "value"}}}
        ])

      assert result == [
               :id,
               %{deeply_nested: %{nested_field: %{inner_field: "value"}}}
             ]
    end

    test "preserves primitive values in nested structures" do
      Application.put_env(:ash_typescript, :input_field_formatter, :snake_case)

      result =
        RequestedFieldsProcessor.atomize_requested_fields([
          "id",
          %{"calc" => %{"args" => %{"count" => 5, "active" => true, "ratio" => 0.5}}}
        ])

      assert result == [
               :id,
               %{calc: %{args: %{count: 5, active: true, ratio: 0.5}}}
             ]
    end
  end

  describe "CRUD actions" do
    test "processes valid fields for read actions correctly" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          :title,
          %{
            user: [:id, :email]
          }
        ])

      assert select == [:id, :title]
      assert load == [{:user, [:id, :email]}]
      assert extraction_template == [:id, :title, {:user, [:id, :email]}]
    end

    test "processes fields for create actions correctly" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :create, [
          :id,
          :title,
          :completed
        ])

      assert select == [:id, :title, :completed]
      assert load == []
      assert extraction_template == [:id, :title, :completed]
    end

    test "processes invalid fields for resources as expected" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{user: [:non_existing_field]}
        ])

      assert error ==
               {:unknown_field, :non_existing_field, AshTypescript.Test.User,
                "user.nonExistingField"}
    end
  end

  describe "generic actions with map return types" do
    test "processes valid fields for map return type actions" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(
          AshTypescript.Test.Todo,
          :get_statistics,
          [
            :total,
            :completed,
            :pending
          ]
        )

      # Map fields are not selected/loaded in Ash sense, just included in template
      assert select == []
      assert load == []
      assert extraction_template == [:total, :completed, :pending]
    end

    test "rejects invalid fields for map return type actions" do
      {:error, error} =
        RequestedFieldsProcessor.process(
          AshTypescript.Test.Todo,
          :get_statistics,
          [
            :invalid_field
          ]
        )

      assert error == {:unknown_field, :invalid_field, "map", "invalidField"}
    end
  end

  describe "generic actions with array return types" do
    test "processes fields for array of UUIDs correctly" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(
          AshTypescript.Test.Todo,
          :bulk_complete,
          []
        )

      # Array of primitives has no field selection
      assert select == []
      assert load == []
      assert extraction_template == []
    end

    test "rejects field selection for array of primitive types" do
      {:error, error} =
        RequestedFieldsProcessor.process(
          AshTypescript.Test.Todo,
          :bulk_complete,
          [:id]
        )

      assert error == {:invalid_field_selection, :primitive_type, {:ash_type, Ash.Type.UUID, []}}
    end

    test "processes fields for array of structs correctly" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :search, [
          :id,
          :title,
          %{user: [:id, :name]}
        ])

      # Array of Todo structs - processes like regular resource fields
      assert select == [:id, :title]
      assert load == [{:user, [:id, :name]}]
      assert extraction_template == [:id, :title, {:user, [:id, :name]}]
    end
  end

  describe "action validation" do
    test "returns error for non-existent action" do
      {:error, error} =
        RequestedFieldsProcessor.process(
          AshTypescript.Test.Todo,
          :non_existent_action,
          []
        )

      assert error == {:action_not_found, :non_existent_action}
    end
  end

  describe "complex nested field processing" do
    test "handles deeply nested relationships correctly" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          %{
            user: [
              :id,
              :name,
              %{
                comments: [:id, :content]
              }
            ]
          }
        ])

      assert select == [:id]
      # Now properly includes nested relationship loads
      assert load == [{:user, [:id, :name, {:comments, [:id, :content]}]}]
      assert extraction_template == [:id, {:user, [:id, :name, {:comments, [:id, :content]}]}]
    end

    test "handles multiple nested relationships in same resource" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          :title,
          %{
            user: [:id, :name],
            comments: [:id, :content]
          }
        ])

      assert select == [:id, :title]
      # Multiple relationships at the same level
      assert load == [{:user, [:id, :name]}, {:comments, [:id, :content]}]

      assert extraction_template == [
               :id,
               :title,
               {:user, [:id, :name]},
               {:comments, [:id, :content]}
             ]
    end

    test "handles mixed simple fields and nested relationships" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          :title,
          :completed,
          %{
            user: [
              :id,
              :email,
              %{
                comments: [:id, :content, :rating]
              }
            ]
          },
          :created_at
        ])

      assert select == [:id, :title, :completed, :created_at]
      assert load == [{:user, [:id, :email, {:comments, [:id, :content, :rating]}]}]

      assert extraction_template == [
               :id,
               :title,
               :completed,
               :created_at,
               {:user, [:id, :email, {:comments, [:id, :content, :rating]}]}
             ]
    end
  end

  describe "relationship access restrictions" do
    test "rejects relationships to resources without AshTypescript.Resource extension" do
      # Try to access :not_exposed_items relationship which points to AshTypescript.Test.NotExposed
      # that doesn't have the AshTypescript.Resource extension
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          :title,
          %{
            not_exposed_items: [:id, :name]
          }
        ])

      assert error ==
               {:unknown_field, :not_exposed_items, AshTypescript.Test.Todo, "notExposedItems"}
    end

    test "allows relationships to resources with AshTypescript.Resource extension" do
      # Verify that normal relationships to resources with the extension still work
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          :title,
          %{
            comments: [:id, :content]
          }
        ])

      assert select == [:id, :title]
      assert load == [{:comments, [:id, :content]}]
      assert extraction_template == [:id, :title, {:comments, [:id, :content]}]
    end
  end
end
