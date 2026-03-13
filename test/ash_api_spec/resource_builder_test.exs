defmodule AshApiSpec.Generator.ResourceBuilderTest do
  use ExUnit.Case, async: true

  alias AshApiSpec.Generator.ResourceBuilder
  alias AshApiSpec.{Resource, Field, Relationship}

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

      field_names = Enum.map(resource.fields, & &1.name)
      assert :title in field_names
      assert :description in field_names
      assert :completed in field_names
      assert :status in field_names
    end

    test "marks attribute field properties correctly" do
      resource = ResourceBuilder.build(AshTypescript.Test.Todo)
      title_field = Enum.find(resource.fields, &(&1.name == :title))

      assert %Field{} = title_field
      assert title_field.kind == :attribute
      assert title_field.allow_nil? == false
      assert title_field.primary_key? == false
    end

    test "includes id as primary key field" do
      resource = ResourceBuilder.build(AshTypescript.Test.Todo)
      id_field = Enum.find(resource.fields, &(&1.name == :id))

      assert %Field{} = id_field
      assert id_field.primary_key? == true
      assert id_field.type.kind == :uuid
    end

    test "includes calculations as fields" do
      resource = ResourceBuilder.build(AshTypescript.Test.Todo)
      calc_fields = Enum.filter(resource.fields, &(&1.kind == :calculation))

      calc_names = Enum.map(calc_fields, & &1.name)
      assert :is_overdue in calc_names
      assert :days_until_due in calc_names
    end

    test "calculation fields include arguments" do
      resource = ResourceBuilder.build(AshTypescript.Test.Todo)

      self_calc = Enum.find(resource.fields, &(&1.name == :self))
      assert self_calc != nil
      assert self_calc.kind == :calculation
      assert is_list(self_calc.arguments)
      assert length(self_calc.arguments) > 0

      arg_names = Enum.map(self_calc.arguments, & &1.name)
      assert :prefix in arg_names
    end

    test "includes aggregates as fields" do
      resource = ResourceBuilder.build(AshTypescript.Test.Todo)
      agg_fields = Enum.filter(resource.fields, &(&1.kind == :aggregate))

      agg_names = Enum.map(agg_fields, & &1.name)
      assert :comment_count in agg_names
      assert :has_comments in agg_names
    end

    test "aggregate fields have aggregate_kind" do
      resource = ResourceBuilder.build(AshTypescript.Test.Todo)

      comment_count = Enum.find(resource.fields, &(&1.name == :comment_count))
      assert comment_count.aggregate_kind == :count
    end

    test "includes relationships" do
      resource = ResourceBuilder.build(AshTypescript.Test.Todo)
      rel_names = Enum.map(resource.relationships, & &1.name)

      assert :user in rel_names
      assert :comments in rel_names
    end

    test "relationship properties are correct" do
      resource = ResourceBuilder.build(AshTypescript.Test.Todo)

      user_rel = Enum.find(resource.relationships, &(&1.name == :user))
      assert %Relationship{} = user_rel
      assert user_rel.type == :belongs_to
      assert user_rel.cardinality == :one
      assert user_rel.destination == AshTypescript.Test.User

      comments_rel = Enum.find(resource.relationships, &(&1.name == :comments))
      assert %Relationship{} = comments_rel
      assert comments_rel.type == :has_many
      assert comments_rel.cardinality == :many
    end

    test "includes all actions when no filter" do
      resource = ResourceBuilder.build(AshTypescript.Test.Todo)
      action_names = Enum.map(resource.actions, & &1.name)

      assert :read in action_names
      assert :create in action_names
      assert :update in action_names
      assert :destroy in action_names
    end

    test "filters actions when action_names provided" do
      resource = ResourceBuilder.build(AshTypescript.Test.Todo, action_names: [:read, :create])
      action_names = Enum.map(resource.actions, & &1.name)

      assert :read in action_names
      assert :create in action_names
      refute :update in action_names
      refute :destroy in action_names
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
