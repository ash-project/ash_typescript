defmodule AshTypescript.Rpc.RequestedFieldsProcessorTest do
  use ExUnit.Case
  alias AshTypescript.Rpc.RequestedFieldsProcessor

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
      assert extraction_template == [:id, :title, [user: [:id, :email]]]
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

      assert error == %{type: :invalid_field, field: "user.nonExistingField"}
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

      assert error == %{type: :invalid_field, field: "invalidField"}
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

      assert error.type == :invalid_field
      assert error.field =~ "Cannot select fields from primitive type"
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
      assert extraction_template == [:id, :title, [user: [:id, :name]]]
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

      assert error == %{
               type: :invalid_field,
               field:
                 "Action non_existent_action not found on resource Elixir.AshTypescript.Test.Todo"
             }
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
      assert extraction_template == [:id, [user: [:id, :name, [comments: [:id, :content]]]]]
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
               [user: [:id, :name]],
               [comments: [:id, :content]]
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
               [user: [:id, :email, [comments: [:id, :content, :rating]]]],
               :created_at
             ]
    end
  end
end
