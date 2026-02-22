# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.RestrictedSchemaCodegenTest do
  use ExUnit.Case

  @moduletag :ash_typescript

  setup do
    Application.put_env(:ash_typescript, :enable_namespace_files, false)
    :ok
  end

  setup_all do
    {:ok, generated_typescript} =
      AshTypescript.Test.CodegenTestHelper.generate_all_content()

    %{generated: generated_typescript}
  end

  describe "denied_loads schema generation" do
    test "generates Omit schema for simple denied_loads", %{generated: generated} do
      assert generated =~ ~r/type ListTodosDenyUserSchema = Omit<TodoResourceSchema, 'user'>/
    end

    test "uses restricted schema in Fields type", %{generated: generated} do
      assert generated =~
               ~r/ListTodosDenyUserFields = UnifiedFieldSelection<ListTodosDenyUserSchema>/
    end

    test "uses restricted schema in InferResult", %{generated: generated} do
      assert generated =~ ~r/InferResult<ListTodosDenyUserSchema, Fields>/
    end
  end

  describe "allowed_loads schema generation" do
    test "generates Omit schema and overrides allowed fields with AttributesOnlySchema", %{
      generated: generated
    } do
      assert generated =~ ~r/type ListTodosAllowOnlyUserSchema = Omit<TodoResourceSchema,/

      assert generated =~
               ~r/type ListTodosAllowOnlyUserSchema = Omit<TodoResourceSchema, [^>]*'comments'/

      assert generated =~
               ~r/type ListTodosAllowOnlyUserSchema = Omit<TodoResourceSchema, [^>]*'user'/

      assert generated =~
               ~r/user: \{ __type: "Relationship"; __resource: UserAttributesOnlySchema/
    end

    test "uses restricted schema in Fields type", %{generated: generated} do
      assert generated =~
               ~r/ListTodosAllowOnlyUserFields = UnifiedFieldSelection<ListTodosAllowOnlyUserSchema>/
    end
  end

  describe "nested denied_loads schema generation" do
    test "generates nested restricted schema for denied_loads: [comments: [:todo]]", %{
      generated: generated
    } do
      assert generated =~
               ~r/type ListTodosDenyNestedSchemaComments = Omit<TodoCommentResourceSchema, 'todo'>/
    end

    test "generates main schema that overrides comments relationship", %{generated: generated} do
      assert generated =~
               ~r/type ListTodosDenyNestedSchema = Omit<TodoResourceSchema, 'comments'> & \{/

      assert generated =~
               ~r/comments: \{ __type: "Relationship"; __array: true; __resource: ListTodosDenyNestedSchemaComments; \}/
    end
  end

  describe "nested allowed_loads schema generation" do
    test "generates nested restricted schema for allowed_loads: [:user, comments: [:todo]]", %{
      generated: generated
    } do
      assert generated =~
               ~r/type ListTodosAllowNestedSchemaComments = Omit<TodoCommentResourceSchema,/

      assert generated =~
               ~r/type ListTodosAllowNestedSchemaComments = Omit<TodoCommentResourceSchema, [^>]*'todo'/

      assert generated =~
               ~r/todo: \{ __type: "Relationship"; __resource: TodoAttributesOnlySchema/
    end

    test "generates main schema with user and comments using appropriate schemas", %{
      generated: generated
    } do
      assert generated =~ ~r/type ListTodosAllowNestedSchema = Omit<TodoResourceSchema,/

      assert generated =~
               ~r/type ListTodosAllowNestedSchema = Omit<TodoResourceSchema, [^>]*'user'/

      assert generated =~
               ~r/user: \{ __type: "Relationship"; __resource: UserAttributesOnlySchema/
    end
  end

  describe "unrestricted actions" do
    test "use base resource schema when no restrictions", %{generated: generated} do
      assert generated =~ ~r/ListTodosFields = UnifiedFieldSelection<TodoResourceSchema>/
      refute generated =~ ~r/type ListTodosSchema = /
    end
  end

  describe "schema integration with InferResult" do
    test "restricted schema works with pagination types", %{generated: generated} do
      assert generated =~
               ~r/InferListTodosDenyUserResult<[^>]*Fields[^>]*Page[^>]*> = ConditionalPaginatedResultMixed<Page, Array<InferResult<ListTodosDenyUserSchema, Fields>>/
    end
  end
end
