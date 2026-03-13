# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshApiSpec.Generator.ResourceBuilderTest do
  use ExUnit.Case, async: true

  alias AshApiSpec.{Field, Relationship, Resource}
  alias AshApiSpec.Generator.ResourceBuilder

  describe "build/2" do
    test "builds a resource from Todo" do
      resource = ResourceBuilder.build(AshTypescript.Test.Todo)
      assert %Resource{} = resource
      assert resource.name == "Todo"
      assert resource.module == AshTypescript.Test.Todo
      assert resource.embedded? == false
      assert :id in resource.primary_key
    end

    test "includes public attributes as fields" do
      resource = ResourceBuilder.build(AshTypescript.Test.Todo)

      assert Map.has_key?(resource.fields, :title)
      assert Map.has_key?(resource.fields, :description)
      assert Map.has_key?(resource.fields, :completed)
      assert Map.has_key?(resource.fields, :status)
    end

    test "marks attribute field properties correctly" do
      resource = ResourceBuilder.build(AshTypescript.Test.Todo)
      title_field = resource.fields[:title]

      assert %Field{} = title_field
      assert title_field.kind == :attribute
      assert title_field.allow_nil? == false
      assert title_field.primary_key? == false
    end

    test "includes id as primary key field" do
      resource = ResourceBuilder.build(AshTypescript.Test.Todo)
      id_field = resource.fields[:id]

      assert %Field{} = id_field
      assert id_field.primary_key? == true
      assert id_field.type.kind == :uuid
    end

    test "includes calculations as fields" do
      resource = ResourceBuilder.build(AshTypescript.Test.Todo)
      calc_fields = resource.fields |> Map.values() |> Enum.filter(&(&1.kind == :calculation))

      calc_names = Enum.map(calc_fields, & &1.name)
      assert :is_overdue in calc_names
      assert :days_until_due in calc_names
    end

    test "calculation fields include arguments" do
      resource = ResourceBuilder.build(AshTypescript.Test.Todo)

      self_calc = resource.fields[:self]
      assert self_calc != nil
      assert self_calc.kind == :calculation
      assert is_list(self_calc.arguments)
      assert self_calc.arguments != []

      arg_names = Enum.map(self_calc.arguments, & &1.name)
      assert :prefix in arg_names
    end

    test "includes aggregates as fields" do
      resource = ResourceBuilder.build(AshTypescript.Test.Todo)
      agg_fields = resource.fields |> Map.values() |> Enum.filter(&(&1.kind == :aggregate))

      agg_names = Enum.map(agg_fields, & &1.name)
      assert :comment_count in agg_names
      assert :has_comments in agg_names
    end

    test "aggregate fields have aggregate_kind" do
      resource = ResourceBuilder.build(AshTypescript.Test.Todo)

      comment_count = resource.fields[:comment_count]
      assert comment_count.aggregate_kind == :count
    end

    test "includes relationships" do
      assert Map.has_key?(ResourceBuilder.build(AshTypescript.Test.Todo).relationships, :user)
      assert Map.has_key?(ResourceBuilder.build(AshTypescript.Test.Todo).relationships, :comments)
    end

    test "relationship properties are correct" do
      resource = ResourceBuilder.build(AshTypescript.Test.Todo)

      user_rel = resource.relationships[:user]
      assert %Relationship{} = user_rel
      assert user_rel.type == :belongs_to
      assert user_rel.cardinality == :one
      assert user_rel.destination == AshTypescript.Test.User

      comments_rel = resource.relationships[:comments]
      assert %Relationship{} = comments_rel
      assert comments_rel.type == :has_many
      assert comments_rel.cardinality == :many
    end

    test "includes all actions when no filter" do
      resource = ResourceBuilder.build(AshTypescript.Test.Todo)

      assert Map.has_key?(resource.actions, :read)
      assert Map.has_key?(resource.actions, :create)
      assert Map.has_key?(resource.actions, :update)
      assert Map.has_key?(resource.actions, :destroy)
    end

    test "filters actions when action_names provided" do
      resource = ResourceBuilder.build(AshTypescript.Test.Todo, action_names: [:read, :create])

      assert Map.has_key?(resource.actions, :read)
      assert Map.has_key?(resource.actions, :create)
      refute Map.has_key?(resource.actions, :update)
      refute Map.has_key?(resource.actions, :destroy)
    end

    test "builds embedded resource" do
      resource = ResourceBuilder.build(AshTypescript.Test.TodoMetadata)
      assert resource.embedded? == true
    end

    test "builds resource with multitenancy" do
      resource = ResourceBuilder.build(AshTypescript.Test.OrgTodo)

      if resource.multitenancy do
        assert is_atom(resource.multitenancy.strategy)
      end
    end
  end
end
