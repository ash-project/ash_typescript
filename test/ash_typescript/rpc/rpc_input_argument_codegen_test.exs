defmodule AshTypescript.Rpc.InputArgumentCodegenTest do
  use ExUnit.Case, async: true

  describe "Input argument type generation for read actions" do
    test "generates input types for read actions with arguments" do
      # Generate TypeScript types for the test domain
      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Test ListTodosConfig - validate complete structure integrity
      list_todos_config_regex =
        ~r/export type ListTodosConfig = \{\s*input\?\: \{\s*filterCompleted\?\: boolean;\s*priorityFilter\?\: "low" \| "medium" \| "high" \| "urgent";\s*\};\s*filter\?\: TodoFilterInput;\s*sort\?\: string;\s*page\?\:\s*\|\s*\{\s*limit\?\: number;\s*offset\?\: number;\s*count\?\: boolean;\s*\}\s*\|\s*\{\s*limit\?\: number;\s*after\?\: string;\s*before\?\: string;\s*count\?\: boolean;\s*\};\s*fields: UnifiedFieldSelection<TodoResourceSchema>\[\];\s*headers\?\: Record<string, string>;\s*\};/m

      assert Regex.match?(list_todos_config_regex, typescript_output),
             "ListTodosConfig structure is malformed. Expected complete type definition with input arguments in correct positions."

      # Also verify the specific input block structure independently
      input_block_regex =
        ~r/input\?\: \{\s*filterCompleted\?\: boolean;\s*priorityFilter\?\: "low" \| "medium" \| "high" \| "urgent";\s*\}/m

      assert Regex.match?(input_block_regex, typescript_output),
             "Input block structure is malformed. Arguments should be adjacent within input block."
    end

    test "generates input types for get actions with get_by fields" do
      # Generate TypeScript types for the test domain
      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Test GetTodoConfig - validate structure with get_by id argument (no sort/page for get actions)
      get_todo_config_regex =
        ~r/export type GetTodoConfig = \{\s*input\?\: \{\s*id\?\: UUID;\s*\};\s*fields: UnifiedFieldSelection<TodoResourceSchema>\[\];\s*headers\?\: Record<string, string>;\s*\};/m

      assert Regex.match?(get_todo_config_regex, typescript_output),
             "GetTodoConfig structure is malformed. Expected complete type definition with id argument in input block but no sort/page fields for get actions."
    end

    test "generates no input types for read actions without arguments" do
      # Since our test User resource may have arguments, let's verify
      # the basic structure for actions without arguments
      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Validate ListUsersConfig structure - User has no read action arguments, so no input field
      list_users_config_regex =
        ~r/export type ListUsersConfig = \{\s*filter\?\: UserFilterInput;\s*sort\?\: string;\s*page\?\:\s*\|\s*\{\s*limit\?\: number;\s*offset\?\: number;\s*count\?\: boolean;\s*\}\s*\|\s*\{\s*limit\?\: number;\s*after\?\: string;\s*before\?\: string;\s*count\?\: boolean;\s*\};\s*fields: UnifiedFieldSelection<UserResourceSchema>\[\];\s*headers\?\: Record<string, string>;\s*\};/m

      assert Regex.match?(list_users_config_regex, typescript_output),
             "ListUsersConfig structure is malformed. Expected complete type definition without input block since User has no read action arguments"
    end

    test "generates required input when at least one argument is required" do
      # This test verifies the logic for required vs optional input
      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Since all our current test read action arguments are optional, input should be optional for ListTodosConfig
      list_todos_optional_regex = ~r/ListTodosConfig = \{[^}]*input\?\: \{/m

      assert Regex.match?(list_todos_optional_regex, typescript_output),
             "ListTodosConfig input should be optional when all arguments are optional"

      # But create/update actions may have required input (that's expected)
      # This test validates the read action behavior specifically
    end

    test "correctly maps argument types to TypeScript types" do
      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Validate argument types are in correct input block context
      boolean_arg_regex = ~r/input\?\: \{[^}]*filterCompleted\?\: boolean;[^}]*\}/m

      assert Regex.match?(boolean_arg_regex, typescript_output),
             "Boolean argument filterCompleted should be within input block"

      # Test enum/atom argument mapping with constraints within input context
      enum_arg_regex =
        ~r/input\?\: \{[^}]*priorityFilter\?\: "low" \| "medium" \| "high" \| "urgent";[^}]*\}/m

      assert Regex.match?(enum_arg_regex, typescript_output),
             "Enum argument priorityFilter should be within input block with correct union type"

      # Test UUID mapping from get_by within input context
      uuid_arg_regex = ~r/input\?\: \{[^}]*id\?\: UUID;[^}]*\}/m

      assert Regex.match?(uuid_arg_regex, typescript_output),
             "UUID argument id should be within input block"
    end

    test "preserves field formatting for argument names" do
      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Validate formatted field names are within input block context
      # filterCompleted should be formatted correctly (from filter_completed)
      formatted_boolean_regex = ~r/input\?\: \{[^}]*filterCompleted\?\: boolean;[^}]*\}/m

      assert Regex.match?(formatted_boolean_regex, typescript_output),
             "filterCompleted should be properly formatted within input block"

      # priorityFilter should be formatted correctly (from priority_filter)
      formatted_enum_regex = ~r/input\?\: \{[^}]*priorityFilter\?\:[^}]*\}/m

      assert Regex.match?(formatted_enum_regex, typescript_output),
             "priorityFilter should be properly formatted within input block"
    end

    test "includes input in payload builders for read actions" do
      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Validate complete payload builder function structure
      payload_builder_regex =
        ~r/export function buildListTodosPayload\(\s*config: ListTodosConfig\s*\): Record<string, any> \{[\s\S]*?if \(\"input\" in config && config\.input\)[\s\S]*?payload\.input = config\.input;[\s\S]*?\}/m

      assert Regex.match?(payload_builder_regex, typescript_output),
             "buildListTodosPayload function structure is malformed. Expected complete function with proper input handling"
    end

    test "maintains backward compatibility for actions without input" do
      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Validate complete backward compatibility structure for ListTodosConfig
      backward_compat_regex =
        ~r/export type ListTodosConfig = \{\s*input\?\: \{[^}]*\};\s*filter\?\: TodoFilterInput;\s*sort\?\: string;\s*page\?\:[\s\S]*?count\?\: boolean;[\s\S]*?;\s*fields: UnifiedFieldSelection<TodoResourceSchema>\[\];\s*headers\?\: Record<string, string>;\s*\};/m

      assert Regex.match?(backward_compat_regex, typescript_output),
             "ListTodosConfig should maintain backward compatibility with all expected fields in correct order"

      # Verify input is optional to maintain backward compatibility
      optional_input_regex = ~r/ListTodosConfig = \{[^}]*input\?\:/m

      assert Regex.match?(optional_input_regex, typescript_output),
             "Input should be optional for backward compatibility"
    end

    test "excludes pagination and sorting for get actions" do
      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Validate GetTodoConfig excludes sort and page fields (get action)
      get_todo_config_regex =
        ~r/export type GetTodoConfig = \{\s*input\?\: \{\s*id\?\: UUID;\s*\};\s*fields: UnifiedFieldSelection<TodoResourceSchema>\[\];\s*headers\?\: Record<string, string>;\s*\};/m

      assert Regex.match?(get_todo_config_regex, typescript_output),
             "GetTodoConfig structure is malformed. Get actions should not have sort or page fields"

      # Validate ListTodosConfig includes sort and page fields (regular read action)  
      list_todos_config_regex =
        ~r/export type ListTodosConfig = \{\s*input\?\: \{[^}]*\};\s*filter\?\: TodoFilterInput;\s*sort\?\: string;\s*page\?\:[\s\S]*?count\?\: boolean;[\s\S]*?;\s*fields: UnifiedFieldSelection<TodoResourceSchema>\[\];\s*headers\?\: Record<string, string>;\s*\};/m

      assert Regex.match?(list_todos_config_regex, typescript_output),
             "ListTodosConfig structure is malformed. Regular read actions should include sort and page fields"
    end
  end

  describe "Input argument type generation for multitenancy actions" do
    test "generates input types for multitenant read actions" do
      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Validate multitenant config structure with input arguments
      multitenant_config_regex =
        ~r/export type ListOrgTodosConfig = \{\s*tenant: string;\s*input\?\: \{\s*filterCompleted\?\: boolean;\s*priorityFilter\?\: "low" \| "medium" \| "high" \| "urgent";\s*\};\s*filter\?\: OrgTodoFilterInput;\s*sort\?\: string;\s*fields: UnifiedFieldSelection<OrgTodoResourceSchema>\[\];\s*headers\?\: Record<string, string>;\s*\};/m

      assert Regex.match?(multitenant_config_regex, typescript_output),
             "ListOrgTodosConfig should have proper multitenant structure with tenant field first and input block"
    end

    test "generates input types for multitenant get actions" do
      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Validate multitenant get action structure (no sort/page for get actions)
      multitenant_get_regex =
        ~r/export type GetOrgTodoConfig = \{\s*tenant: string;\s*input\?\: \{\s*id\?\: UUID;\s*\};\s*fields: UnifiedFieldSelection<OrgTodoResourceSchema>\[\];\s*headers\?\: Record<string, string>;\s*\};/m

      assert Regex.match?(multitenant_get_regex, typescript_output),
             "GetOrgTodoConfig should have proper multitenant structure with tenant field and input block containing id but no sort/page fields"
    end
  end

  describe "Input argument type generation for non-read actions" do
    test "maintains existing input generation for create actions" do
      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Validate CreateTodoConfig has required input block with title field
      create_todo_config_regex =
        ~r/export type CreateTodoConfig = \{\s*input: \{[\s\S]*?title: string;[\s\S]*?\};\s*fields: UnifiedFieldSelection<TodoResourceSchema>\[\];\s*headers\?\: Record<string, string>;\s*\};/m

      assert Regex.match?(create_todo_config_regex, typescript_output),
             "CreateTodoConfig structure is malformed. Expected complete type definition with required input block and title field"
    end

    test "maintains existing input generation for update actions" do
      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Validate UpdateTodoConfig has primaryKey and input block with title field
      update_todo_config_regex =
        ~r/export type UpdateTodoConfig = \{\s*primaryKey: UUID;\s*input: \{[\s\S]*?title: string;[\s\S]*?\};\s*fields: UnifiedFieldSelection<TodoResourceSchema>\[\];\s*headers\?\: Record<string, string>;\s*\};/m

      assert Regex.match?(update_todo_config_regex, typescript_output),
             "UpdateTodoConfig structure is malformed. Expected complete type definition with primaryKey, input block with title field, and fields property"
    end

    test "correctly handles actions with only optional input fields" do
      typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Validate CompleteTodoConfig structure - typically has minimal input
      complete_todo_config_regex =
        ~r/export type CompleteTodoConfig = \{\s*primaryKey: UUID;\s*(input\?\: \{[^}]*\};\s*)?fields: UnifiedFieldSelection<TodoResourceSchema>\[\];\s*headers\?\: Record<string, string>;\s*\};/m

      assert Regex.match?(complete_todo_config_regex, typescript_output),
             "CompleteTodoConfig structure is malformed. Expected complete type definition with primaryKey and optional input block"
    end
  end
end
