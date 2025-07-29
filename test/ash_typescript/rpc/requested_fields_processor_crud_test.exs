defmodule AshTypescript.Rpc.RequestedFieldsProcessorCrudTest do
  use ExUnit.Case
  alias AshTypescript.Rpc.RequestedFieldsProcessor

  describe "read actions" do
    test "processes valid fields correctly" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          :title,
          :completed
        ])

      assert select == [:id, :title, :completed]
      assert load == []
      assert extraction_template == [:id, :title, :completed]
    end

    test "processes mixed attributes and loadable fields" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          :title,
          # aggregate
          :comment_count
        ])

      assert select == [:id, :title]
      assert load == [:comment_count]
      assert extraction_template == [:id, :title, :comment_count]
    end

    test "processes simple relationship fields" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :id,
          :title,
          %{user: [:id, :email]}
        ])

      assert select == [:id, :title]
      assert load == [{:user, [:id, :email]}]
      assert extraction_template == [:id, :title, user: [:id, :email]]
    end
  end

  describe "create actions" do
    test "processes fields correctly" do
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

    test "processes relationships in create actions" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :create, [
          :id,
          :title,
          %{user: [:id, :name]}
        ])

      assert select == [:id, :title]
      assert load == [{:user, [:id, :name]}]
      assert extraction_template == [:id, :title, user: [:id, :name]]
    end
  end

  describe "update actions" do
    test "processes fields correctly" do
      {:ok, {select, load, extraction_template}} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :update, [
          :id,
          :title,
          :completed,
          :created_at
        ])

      assert select == [:id, :title, :completed, :created_at]
      assert load == []
      assert extraction_template == [:id, :title, :completed, :created_at]
    end
  end

  describe "field validation for CRUD actions" do
    test "returns error for invalid attribute" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          :invalid_field
        ])

      assert error == {:unknown_field, :invalid_field, AshTypescript.Test.Todo, "invalidField"}
    end

    test "returns error for invalid nested field" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{user: [:invalid_field]}
        ])

      assert error == {:unknown_field, :invalid_field, AshTypescript.Test.User, "user.invalidField"}
    end

    test "returns error for invalid relationship" do
      {:error, error} =
        RequestedFieldsProcessor.process(AshTypescript.Test.Todo, :read, [
          %{invalid_relationship: [:id]}
        ])

      assert error == {:unknown_field, :invalid_relationship, AshTypescript.Test.Todo, "invalidRelationship"}
    end
  end
end
