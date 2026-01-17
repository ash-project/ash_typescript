# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.RestrictedSchemaCodegenTest do
  use ExUnit.Case

  @moduletag :ash_typescript

  setup_all do
    {:ok, generated_typescript} = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)
    %{generated: generated_typescript}
  end

  describe "denied_loads schema generation" do
    test "generates Omit schema for simple denied_loads", %{generated: generated} do
      # denied_loads: [:user] should generate Omit<TodoResourceSchema, 'user'>
      assert generated =~ ~r/type ListTodosDenyUserSchema = Omit<TodoResourceSchema, 'user'>/
    end

    test "uses restricted schema in Fields type", %{generated: generated} do
      assert generated =~ ~r/ListTodosDenyUserFields = UnifiedFieldSelection<ListTodosDenyUserSchema>/
    end

    test "uses restricted schema in InferResult", %{generated: generated} do
      assert generated =~ ~r/InferResult<ListTodosDenyUserSchema, Fields>/
    end
  end

  describe "allowed_loads schema generation" do
    test "generates Omit schema and overrides allowed fields with AttributesOnlySchema", %{generated: generated} do
      # allowed_loads: [:user] omits non-allowed fields AND overrides user with AttributesOnlySchema
      assert generated =~ ~r/type ListTodosAllowOnlyUserSchema = Omit<TodoResourceSchema,/
      # 'comments' should appear since it's not in the allow list
      assert generated =~ ~r/type ListTodosAllowOnlyUserSchema = Omit<TodoResourceSchema, [^>]*'comments'/
      # 'user' is also omitted (to be replaced with AttributesOnlySchema override)
      assert generated =~ ~r/type ListTodosAllowOnlyUserSchema = Omit<TodoResourceSchema, [^>]*'user'/
      # user override uses AttributesOnlySchema (no nested loads allowed)
      assert generated =~ ~r/user: \{ __type: "Relationship"; __resource: UserAttributesOnlySchema/
    end

    test "uses restricted schema in Fields type", %{generated: generated} do
      assert generated =~ ~r/ListTodosAllowOnlyUserFields = UnifiedFieldSelection<ListTodosAllowOnlyUserSchema>/
    end
  end

  describe "nested denied_loads schema generation" do
    test "generates nested restricted schema for denied_loads: [comments: [:todo]]", %{
      generated: generated
    } do
      # Should generate a nested schema for comments that omits 'todo'
      assert generated =~
               ~r/type ListTodosDenyNestedSchemaComments = Omit<TodoCommentResourceSchema, 'todo'>/
    end

    test "generates main schema that overrides comments relationship", %{generated: generated} do
      # Main schema should omit 'comments' (to replace it) and add it back with restricted type
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
      # Comments uses nested schema with todo allowed (via AttributesOnlySchema)
      assert generated =~ ~r/type ListTodosAllowNestedSchemaComments = Omit<TodoCommentResourceSchema,/
      # 'todo' is in omit list (to be replaced with AttributesOnlySchema override)
      assert generated =~ ~r/type ListTodosAllowNestedSchemaComments = Omit<TodoCommentResourceSchema, [^>]*'todo'/
      # todo override uses AttributesOnlySchema (separate assertion for the override)
      assert generated =~ ~r/todo: \{ __type: "Relationship"; __resource: TodoAttributesOnlySchema/
    end

    test "generates main schema with user and comments using appropriate schemas", %{generated: generated} do
      # Main schema omits both user and comments (to replace with restricted versions)
      assert generated =~ ~r/type ListTodosAllowNestedSchema = Omit<TodoResourceSchema,/
      # 'user' is in omit list (to be replaced with AttributesOnlySchema)
      assert generated =~ ~r/type ListTodosAllowNestedSchema = Omit<TodoResourceSchema, [^>]*'user'/
      # user override uses AttributesOnlySchema (flat allow = no nested loads)
      assert generated =~ ~r/user: \{ __type: "Relationship"; __resource: UserAttributesOnlySchema/
    end
  end

  describe "unrestricted actions" do
    test "use base resource schema when no restrictions", %{generated: generated} do
      # list_todos has no restrictions, should use TodoResourceSchema directly
      assert generated =~ ~r/ListTodosFields = UnifiedFieldSelection<TodoResourceSchema>/
      # And should NOT have a ListTodosSchema restricted type
      refute generated =~ ~r/type ListTodosSchema = /
    end
  end

  describe "schema integration with InferResult" do
    test "restricted schema works with pagination types", %{generated: generated} do
      # Ensure the restricted schema flows through to pagination result types
      assert generated =~
               ~r/InferListTodosDenyUserResult<[^>]*Fields[^>]*Page[^>]*> = ConditionalPaginatedResultMixed<Page, Array<InferResult<ListTodosDenyUserSchema, Fields>>/
    end
  end
end
