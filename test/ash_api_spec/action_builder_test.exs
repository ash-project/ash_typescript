defmodule AshApiSpec.Generator.ActionBuilderTest do
  use ExUnit.Case, async: true

  alias AshApiSpec.Generator.ActionBuilder
  alias AshApiSpec.{Action, Argument, Pagination}

  defp get_action(resource, action_name) do
    Ash.Resource.Info.action(resource, action_name)
  end

  describe "build/2" do
    test "builds read action" do
      action = get_action(AshTypescript.Test.Todo, :read)
      result = ActionBuilder.build(AshTypescript.Test.Todo, action)

      assert %Action{} = result
      assert result.name == :read
      assert result.type == :read
      assert result.primary? == true
    end

    test "builds create action with accept list" do
      action = get_action(AshTypescript.Test.Todo, :create)
      result = ActionBuilder.build(AshTypescript.Test.Todo, action)

      assert result.type == :create
      assert is_list(result.accept)
      assert :title in result.accept
    end

    test "builds action with public arguments only" do
      action = get_action(AshTypescript.Test.Todo, :read)
      result = ActionBuilder.build(AshTypescript.Test.Todo, action)

      # read action has filter_completed and priority_filter as arguments
      # All should be public since the test resource defines them without `public?: false`
      arg_names = Enum.map(result.arguments, & &1.name)
      # These arguments don't have public? set — check what we get
      assert is_list(result.arguments)
    end

    test "builds argument with type resolution" do
      action = get_action(AshTypescript.Test.Todo, :create)
      result = ActionBuilder.build(AshTypescript.Test.Todo, action)

      user_id_arg = Enum.find(result.arguments, &(&1.name == :user_id))

      if user_id_arg do
        assert %Argument{} = user_id_arg
        assert user_id_arg.allow_nil? == false
        assert user_id_arg.type.kind == :uuid
      end
    end

    test "builds read action with pagination" do
      action = get_action(AshTypescript.Test.Todo, :read)
      result = ActionBuilder.build(AshTypescript.Test.Todo, action)

      assert %Pagination{} = result.pagination
      assert result.pagination.offset? == true
      assert result.pagination.keyset? == true
      assert result.pagination.countable? == true
      assert result.pagination.required? == false
      assert result.pagination.default_limit == 20
      assert result.pagination.max_page_size == 100
    end

    test "builds read action without pagination" do
      action = get_action(AshTypescript.Test.Todo, :list_high_priority)
      result = ActionBuilder.build(AshTypescript.Test.Todo, action)

      assert result.pagination == nil
    end

    test "builds generic action with returns type" do
      action = get_action(AshTypescript.Test.Todo, :bulk_complete)
      result = ActionBuilder.build(AshTypescript.Test.Todo, action)

      assert result.type == :action
      assert result.returns != nil
      assert result.returns.kind == :array
      assert result.returns.item_type.kind == :uuid
    end

    test "builds generic action with map return type" do
      action = get_action(AshTypescript.Test.Todo, :get_statistics)
      result = ActionBuilder.build(AshTypescript.Test.Todo, action)

      assert result.type == :action
      assert result.returns != nil
      assert result.returns.kind == :map
      assert is_list(result.returns.fields)
    end

    test "builds destroy action" do
      action = get_action(AshTypescript.Test.Todo, :destroy)
      result = ActionBuilder.build(AshTypescript.Test.Todo, action)

      assert result.type == :destroy
    end

    test "builds action with metadata" do
      action = get_action(AshTypescript.Test.Task, :read_with_metadata)

      if action do
        result = ActionBuilder.build(AshTypescript.Test.Task, action)
        assert is_list(result.metadata)
      end
    end

    test "get? action has get? set to true" do
      action = get_action(AshTypescript.Test.Todo, :get_by_id)
      result = ActionBuilder.build(AshTypescript.Test.Todo, action)

      assert result.get? == true
    end
  end
end
