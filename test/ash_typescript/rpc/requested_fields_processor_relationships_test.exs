# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.RequestedFieldsProcessorRelationshipsTest do
  use ExUnit.Case
  alias AshTypescript.Rpc.RequestedFieldsProcessor

  describe "single level relationships" do
    test "processes belongs_to relationships" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          :title,
          %{user: [:id, :name, :email]}
        ])

      assert select == [:id, :title]
      assert load == [{:user, [:id, :name, :email]}]
      assert extraction_template == [:id, :title, user: [:id, :name, :email]]
    end

    test "processes has_many relationships" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          :title,
          %{comments: [:id, :content, :rating]}
        ])

      assert select == [:id, :title]
      assert load == [{:comments, [:id, :content, :rating]}]
      assert extraction_template == [:id, :title, comments: [:id, :content, :rating]]
    end

    test "processes multiple relationships at same level" do
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
               user: [:id, :name],
               comments: [:id, :content]
             ]
    end
  end

  describe "nested relationships" do
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
      assert extraction_template == [:id, user: [:id, :name, comments: [:id, :content]]]
    end

    test "handles three-level nested relationships" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.User, :read, [
          :id,
          :name,
          %{
            todos: [
              :id,
              :title,
              %{
                comments: [
                  :id,
                  :content,
                  %{
                    user: [:id, :name]
                  }
                ]
              }
            ]
          }
        ])

      assert select == [:id, :name]

      assert load == [
               {:todos, [:id, :title, {:comments, [:id, :content, {:user, [:id, :name]}]}]}
             ]

      assert extraction_template == [
               :id,
               :name,
               todos: [:id, :title, comments: [:id, :content, user: [:id, :name]]]
             ]
    end

    test "handles multiple nested relationships in different branches" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          :title,
          %{
            user: [
              :id,
              :name,
              %{comments: [:id, :content]}
            ],
            comments: [
              :id,
              :rating,
              %{user: [:id, :email]}
            ]
          }
        ])

      assert select == [:id, :title]

      assert load == [
               {:user, [:id, :name, {:comments, [:id, :content]}]},
               {:comments, [:id, :rating, {:user, [:id, :email]}]}
             ]

      assert extraction_template == [
               :id,
               :title,
               user: [:id, :name, comments: [:id, :content]],
               comments: [:id, :rating, user: [:id, :email]]
             ]
    end
  end

  describe "mixed simple fields and relationships" do
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
               user: [:id, :email, comments: [:id, :content, :rating]]
             ]
    end

    test "handles loadable fields mixed with relationships" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          :title,
          # aggregate
          :comment_count,
          %{user: [:id, :name]},
          # calculation
          :is_overdue,
          %{comments: [:id, :content]}
        ])

      assert select == [:id, :title]

      assert load == [
               :comment_count,
               {:user, [:id, :name]},
               :is_overdue,
               {:comments, [:id, :content]}
             ]

      assert extraction_template == [
               :id,
               :title,
               :comment_count,
               :is_overdue,
               user: [:id, :name],
               comments: [:id, :content]
             ]
    end
  end

  describe "relationship validation" do
    test "returns error for invalid relationship field" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{user: [:invalid_field]}
        ])

      assert error ==
               {:unknown_field, :invalid_field, AshTypescript.Test.User, "user.invalidField"}
    end

    test "returns error for invalid nested relationship" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{user: [%{invalid_relationship: [:id]}]}
        ])

      assert error ==
               {:unknown_field, :invalid_relationship, AshTypescript.Test.User,
                "user.invalidRelationship"}
    end

    test "returns error for invalid deeply nested field" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{
            user: [
              :id,
              %{
                comments: [:id, :invalid_field]
              }
            ]
          }
        ])

      assert error ==
               {:unknown_field, :invalid_field, AshTypescript.Test.TodoComment,
                "user.comments.invalidField"}
    end

    test "validates relationship existence before processing nested fields" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{nonexistent_relation: [:id, :name]}
        ])

      assert error ==
               {:unknown_field, :nonexistent_relation, AshTypescript.Test.Todo,
                "nonexistentRelation"}
    end

    test "rejects relationships requested as simple atoms without field specification" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          # This should be rejected - relationships must specify fields
          :user
        ])

      assert error == {:requires_field_selection, :relationship, "user"}
    end
  end

  describe "edge cases" do
    test "rejects empty relationship field lists" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          %{user: []}
        ])

      assert error == {:requires_field_selection, "relationship", "user"}
    end

    test "handles relationship with only nested relationships (no direct fields)" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          %{
            user: [
              %{comments: [:id, :content]}
            ]
          }
        ])

      assert select == [:id]
      assert load == [{:user, [{:comments, [:id, :content]}]}]
      assert extraction_template == [:id, user: [comments: [:id, :content]]]
    end
  end
end
