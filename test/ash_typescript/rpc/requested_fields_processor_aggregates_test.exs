defmodule AshTypescript.Rpc.RequestedFieldsProcessorAggregatesTest do
  use ExUnit.Case
  alias AshTypescript.Rpc.RequestedFieldsProcessor

  describe "primitive aggregates (no nested field selection)" do
    test "processes simple count aggregate" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          :title,
          :comment_count
        ])

      # Aggregates are loaded, not selected
      assert select == [:id, :title]
      assert load == [:comment_count]
      assert extraction_template == [:id, :title, :comment_count]
    end

    test "processes filtered count aggregate" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          :helpful_comment_count
        ])

      assert select == [:id]
      assert load == [:helpful_comment_count]
      assert extraction_template == [:id, :helpful_comment_count]
    end

    test "processes exists aggregate" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          :has_comments
        ])

      assert select == [:id]
      assert load == [:has_comments]
      assert extraction_template == [:id, :has_comments]
    end

    test "processes avg and max aggregates" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          :average_rating,
          :highest_rating
        ])

      assert select == [:id]
      assert load == [:average_rating, :highest_rating]
      assert extraction_template == [:id, :average_rating, :highest_rating]
    end

    test "processes first aggregate of primitive field" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          :latest_comment_content
        ])

      assert select == [:id]
      assert load == [:latest_comment_content]
      assert extraction_template == [:id, :latest_comment_content]
    end

    test "processes list aggregate of primitive field" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          :comment_authors
        ])

      assert select == [:id]
      assert load == [:comment_authors]
      assert extraction_template == [:id, :comment_authors]
    end

    test "rejects nested field selection on primitive aggregates" do
      # Count aggregate (returns integer)
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{comment_count: [:id]}
        ])

      assert error == {:invalid_field_selection, :comment_count, :aggregate, "commentCount"}
    end

    test "rejects nested field selection on exists aggregate" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{has_comments: [:id]}
        ])

      assert error == {:invalid_field_selection, :has_comments, :aggregate, "hasComments"}
    end

    test "rejects nested field selection on primitive list aggregate" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{comment_authors: [:id]}
        ])

      assert error == {:invalid_field_selection, :comment_authors, :aggregate, "commentAuthors"}
    end
  end

  describe "validation of non-existent complex aggregates" do
    test "rejects non-existent complex aggregate (latest_comment)" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          %{latest_comment: [:id, :content, :author_name]}
        ])

      assert error == {:unknown_field, :latest_comment, AshTypescript.Test.Todo, "latestComment"}
    end

    test "rejects non-existent complex aggregate (recent_comments)" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          %{recent_comments: [:id, :content, :rating]}
        ])

      assert error == {:unknown_field, :recent_comments, AshTypescript.Test.Todo, "recentComments"}
    end

    test "rejects non-existent complex aggregate with nested relationships" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          %{
            latest_comment: [
              :id,
              :content,
              %{user: [:id, :name]}
            ]
          }
        ])

      assert error == {:unknown_field, :latest_comment, AshTypescript.Test.Todo, "latestComment"}
    end

    test "rejects non-existent complex aggregate with empty field selection" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{latest_comment: []}
        ])

      assert error == {:unknown_field, :latest_comment, AshTypescript.Test.Todo, "latestComment"}
    end

    test "rejects non-existent complex aggregate as simple atom" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :latest_comment  # Non-existent aggregate requested as simple atom
        ])

      assert error == {:unknown_field, :latest_comment, AshTypescript.Test.Todo, "latestComment"}
    end

    test "rejects non-existent complex aggregate in mixed field selection" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          :comment_count,  # Valid primitive aggregate
          %{latest_comment: [:id, :content]}  # Invalid complex aggregate
        ])

      assert error == {:unknown_field, :latest_comment, AshTypescript.Test.Todo, "latestComment"}
    end
  end

  describe "mixed aggregate types" do
    test "processes multiple primitive aggregates together" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          # primitive aggregates
          :comment_count,
          :has_comments,
          :latest_comment_content,
          :comment_authors,
          # other field types
          :title,
          %{user: [:id, :name]}
        ])

      assert select == [:id, :title]

      assert load == [
               :comment_count,
               :has_comments,
               :latest_comment_content,
               :comment_authors,
               {:user, [:id, :name]}
             ]

      assert extraction_template == [
               :id,
               :comment_count,
               :has_comments,
               :latest_comment_content,
               :comment_authors,
               :title,
               user: [:id, :name]
             ]
    end

    test "processes primitive aggregates with calculations" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          # primitive aggregates
          :comment_count,
          :recent_comment_ids,
          # calculation
          :is_overdue,
          # calculation with args
          %{
            self: %{args: %{prefix: "test"}, fields: [:title, :description]}
          }
        ])

      assert select == [:id]

      assert load == [
               :comment_count,
               :recent_comment_ids,
               :is_overdue,
               {:self, {%{prefix: "test"}, [:title, :description]}}
             ]

      assert extraction_template == [
               :id,
               :comment_count,
               :recent_comment_ids,
               :is_overdue,
               self: [:title, :description]
             ]
    end
  end

  describe "aggregate validation and error handling" do
    test "rejects non-existent aggregate" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          :non_existent_aggregate
        ])

      assert error == {:unknown_field, :non_existent_aggregate, AshTypescript.Test.Todo, "nonExistentAggregate"}
    end

    test "rejects duplicate aggregate fields" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :comment_count,
          :comment_count
        ])

      assert error == {:duplicate_field, :comment_count, "commentCount"}
    end

    test "rejects mixed atom and map for same aggregate" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :comment_count,
          %{comment_count: []}
        ])

      assert error == {:duplicate_field, :comment_count, "commentCount"}
    end

    test "handles non-existent aggregate" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :latest_comment  # Non-existent aggregate requested as simple atom
        ])

      assert error == {:unknown_field, :latest_comment, AshTypescript.Test.Todo, "latestComment"}
    end
  end

  describe "aggregates in different action types" do
    test "processes aggregates in create actions" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :create, [
          :id,
          :title,
          :comment_count,
          :latest_comment_content
        ])

      assert select == [:id, :title]
      assert load == [:comment_count, :latest_comment_content]
      assert extraction_template == [:id, :title, :comment_count, :latest_comment_content]
    end

    test "processes aggregates in update actions" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :update, [
          :id,
          :title,
          :comment_count,
          :recent_comment_ids
        ])

      assert select == [:id, :title]

      assert load == [
               :comment_count,
               :recent_comment_ids
             ]

      assert extraction_template == [
               :id,
               :title,
               :comment_count,
               :recent_comment_ids
             ]
    end
  end
end