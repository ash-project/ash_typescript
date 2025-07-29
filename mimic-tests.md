# RPC Run Action Test Mimicking Plan

## Overview

This document outlines the comprehensive plan to create RPC run action integration tests that mimic all existing requested fields processor unit tests. These tests provide end-to-end validation of the field processing pipeline by testing actual `Rpc.run_action/3` calls instead of just the internal `RequestedFieldsProcessor.process/3` function.

## Test Categories & Priority

### Status Summary

**✅ COMPLETED:**
- `rpc_run_action_aggregates_test.exs` - mimics `requested_fields_processor_aggregates_test.exs`
- `rpc_run_action_crud_test.exs` - mimics `requested_fields_processor_crud_test.exs`
- `rpc_run_action_union_types_test.exs` - mimics `requested_fields_processor_union_types_test.exs` ✅ COMPLETED
- `rpc_run_action_calculations_test.exs` - mimics `requested_fields_processor_calculations_test.exs` ✅ COMPLETED  
- `rpc_run_action_relationships_test.exs` - mimics `requested_fields_processor_relationships_test.exs` ✅ COMPLETED
- `rpc_run_action_embedded_test.exs` - mimics `requested_fields_processor_embedded_test.exs` ✅ COMPLETED

**🔥 HIGH PRIORITY - Core Field Processing (ALL COMPLETED):**

### 1. `rpc_run_action_union_types_test.exs` ✅ COMPLETED
**Mimics:** `requested_fields_processor_union_types_test.exs`
**Priority:** HIGH - Core functionality for union types
**Status:** COMPLETED - Comprehensive test covering embedded resource union members, simple type union members, mixed union members, array union types, map with tag storage unions, validation and error handling, and complex union field selection scenarios.
**Test Areas:**
- Embedded resource union members with field selection
- Simple type union members (string, integer)
- Mixed simple and complex union members
- Array union types (attachments)
- Map with tag storage unions (status_info)
- Union validation and error handling
- Single map syntax for multiple union members
- Nested calculations within union members

**Key RPC Patterns to Test:**
```elixir
# Single union member with field selection
Rpc.run_action(:ash_typescript, conn, %{
  "action" => "list_todos",
  "fields" => ["id", %{"content" => [%{"text" => ["id", "text", "formatting"]}]}]
})

# Multiple union members in single map (new syntax)
Rpc.run_action(:ash_typescript, conn, %{
  "action" => "list_todos",
  "fields" => ["id", %{
    "content" => [%{
      "text" => ["id", "text"],
      "checklist" => ["id", "title", "items"],
      "link" => ["url", "displayTitle"]
    }]
  }]
})

# Array union type
Rpc.run_action(:ash_typescript, conn, %{
  "action" => "list_todos",
  "fields" => [%{"attachments" => ["url", %{"file" => ["filename", "size"]}]}]
})
```

### 2. `rpc_run_action_calculations_test.exs` ✅ COMPLETED
**Mimics:** `requested_fields_processor_calculations_test.exs`
**Priority:** HIGH - Core functionality for calculations
**Status:** COMPLETED - Comprehensive test covering simple calculations without arguments, calculations with arguments and field selection, mixed calculations with other field types, and calculation validation and error handling.
**Test Areas:**
- Simple calculations without arguments (boolean, integer)
- Calculations with arguments and field selection (struct calculations)
- Calculation with nested relationship field selection
- Mixed calculations with regular fields
- Calculation validation and error handling
- Complex nested calculations with arguments

**Key RPC Patterns to Test:**
```elixir
# Simple calculation
Rpc.run_action(:ash_typescript, conn, %{
  "action" => "list_todos",
  "fields" => ["id", "isOverdue", "daysUntilDue"]
})

# Calculation with args and field selection
Rpc.run_action(:ash_typescript, conn, %{
  "action" => "list_todos", 
  "fields" => [%{"self" => %{"args" => %{"prefix" => "test"}, "fields" => ["title", "description"]}}]
})
```

### 3. `rpc_run_action_relationships_test.exs` ✅ COMPLETED
**Mimics:** `requested_fields_processor_relationships_test.exs`
**Priority:** HIGH - Core functionality for relationships
**Status:** COMPLETED - Comprehensive test covering single level relationships, nested relationships, mixed simple fields and relationships, relationship validation, and edge cases.
**Test Areas:**
- Single level relationships (belongs_to, has_many)
- Nested relationships (user -> settings -> preferences)
- Mixed simple fields and relationships
- Relationship validation and error handling
- Edge cases (empty relationships, deep nesting)

**Key RPC Patterns to Test:**
```elixir
# Single level relationship
Rpc.run_action(:ash_typescript, conn, %{
  "action" => "list_todos",
  "fields" => ["id", %{"user" => ["id", "name"]}]
})

# Nested relationships
Rpc.run_action(:ash_typescript, conn, %{
  "action" => "list_todos",
  "fields" => ["id", %{"user" => ["id", %{"settings" => ["theme", "language"]}]}]
})
```

### 4. `rpc_run_action_embedded_test.exs` ✅ COMPLETED
**Mimics:** `requested_fields_processor_embedded_test.exs`
**Priority:** HIGH - Core functionality for embedded resources
**Status:** COMPLETED - Comprehensive test covering simple embedded resource fields, array of embedded resources, union types with embedded resources, error handling for embedded resources, and create/update actions with embedded resources.
**Test Areas:**
- Simple embedded resource fields (attributes, calculations)
- Array of embedded resources
- Union type with embedded resources
- Embedded resources in create/update actions
- Error handling for embedded resources

**Key RPC Patterns to Test:**
```elixir
# Embedded resource with field selection
Rpc.run_action(:ash_typescript, conn, %{
  "action" => "list_todos",
  "fields" => ["id", %{"metadata" => ["createdBy", "priority", "tags"]}]
})

# Array of embedded resources
Rpc.run_action(:ash_typescript, conn, %{
  "action" => "list_todos", 
  "fields" => ["id", %{"metadataHistory" => ["createdBy", "priority"]}]
})
```

**🟡 MEDIUM PRIORITY - Advanced Features:**

### 5. `rpc_run_action_custom_types_test.exs`
**Mimics:** `requested_fields_processor_custom_types_test.exs`  
**Priority:** MEDIUM - Important for custom type handling
**Test Areas:**
- Simple scalar custom types (priority_score)
- Complex structured custom types (color_palette)
- Custom types in complex scenarios (with relationships, calculations)
- Custom type validation and error handling
- Edge cases and boundary conditions

### 6. `rpc_run_action_typed_structs_test.exs`
**Mimics:** `requested_fields_processor_typed_structs_test.exs`
**Priority:** MEDIUM - Advanced Ash.TypedStruct support
**Test Areas:**
- Simple typed struct fields
- Typed struct fields with other field types
- Create/update actions with typed structs
- Map field nesting within typed structs
- Error handling for typed structs

### 7. `rpc_run_action_generic_actions_test.exs`
**Mimics:** `requested_fields_processor_generic_actions_test.exs`
**Priority:** MEDIUM - Generic actions support
**Test Areas:**
- Map return type actions
- Array return type actions
- Action validation
- Unknown return types
- Complex return type validation

**🟢 LOW PRIORITY - Specialized/Integration:**

### 8. `rpc_run_action_core_test.exs`
**Mimics:** `requested_fields_processor_test.exs` (main test)
**Priority:** LOW - Core processor logic (mostly internal)
**Test Areas:**
- Field atomization with different formatters (snake_case, camelCase)
- Complex nested field processing
- Core CRUD action support
- Action validation basics

**Note:** Much of this file tests internal processor logic that's already covered by integration in other tests.

## Additional Integration Tests (Beyond Processor Mimicking)

**Worth Considering for Complete Coverage:**

### 9. `rpc_run_action_pagination_test.exs`
**Mimics:** `pagination_advanced_test.exs`
**Test Areas:**
- Offset pagination with field selection
- Keyset pagination with field selection
- Pagination metadata handling

## Test Implementation Patterns

### Mandatory Requirements

**1. Result Unwrapping:**
```elixir
# ✅ ALWAYS - Setup calls
%{"success" => true, "data" => user} = Rpc.run_action(:ash_typescript, conn, %{...})

# ✅ ALWAYS - Test calls that expect success
result = Rpc.run_action(:ash_typescript, conn, %{...})
assert result["success"] == true

# ✅ ALWAYS - Test calls that expect failure  
result = Rpc.run_action(:ash_typescript, conn, %{...})
assert result["success"] == false
```

**2. No Redundant Assertions:**
```elixir
# ❌ WRONG - Redundant
assert Map.has_key?(todo, "title")
assert todo["title"] == "Test Title"

# ✅ CORRECT - Value assertion implies key existence
assert todo["title"] == "Test Title"

# ✅ CORRECT - Only check existence when no value assertion follows
assert Map.has_key?(todo, "user")
if todo["user"] do
  # ... nested checks
end
```

**3. Setup Patterns:**
```elixir
setup do
  conn = TestHelpers.build_rpc_conn()
  
  # Create test data with proper unwrapping
  %{"success" => true, "data" => user} = Rpc.run_action(:ash_typescript, conn, %{
    "action" => "create_user",
    "input" => %{"name" => "Test User", "email" => "test@example.com"},
    "fields" => ["id", "name"]
  })
  
  %{conn: conn, user: user}
end
```

**4. Test Structure:**
```elixir
test "descriptive test name", %{conn: conn, user: user} do
  result = Rpc.run_action(:ash_typescript, conn, %{
    "action" => "list_todos",
    "fields" => ["id", "title", %{"user" => ["name"]}]
  })
  
  assert result["success"] == true
  assert is_list(result["data"])
  
  Enum.each(result["data"], fn todo ->
    assert is_binary(todo["title"])
    assert Map.has_key?(todo, "user")
    # Verify only what's expected, refute what shouldn't exist
    refute Map.has_key?(todo, "description")
  end)
end
```

## Implementation Timeline

### Phase 1 (HIGH Priority - Core Functionality)
1. `rpc_run_action_union_types_test.exs` - Essential for union type support (NEW!)
2. `rpc_run_action_calculations_test.exs` - Essential for calculation support
3. `rpc_run_action_relationships_test.exs` - Essential for relationship support
4. `rpc_run_action_embedded_test.exs` - Essential for embedded resource support

### Phase 2 (MEDIUM Priority - Advanced Features)
5. `rpc_run_action_custom_types_test.exs` - Important for custom type handling
6. `rpc_run_action_typed_structs_test.exs` - Advanced Ash.TypedStruct support
7. `rpc_run_action_generic_actions_test.exs` - Generic actions support

### Phase 3 (LOW Priority - Nice to Have)  
8. `rpc_run_action_core_test.exs` - Internal logic (mostly covered by integration)
9. `rpc_run_action_pagination_test.exs` - Pagination integration

## Testing Strategy

### Coverage Goals
- **100% field type coverage** - Every field type should have end-to-end RPC tests
- **All action types** - CREATE, READ, UPDATE, custom actions
- **Error scenarios** - Invalid fields, malformed requests, etc.
- **Integration scenarios** - Mixed field types, complex nesting

### Quality Standards
- **No redundant assertions** - Follow established cleanup patterns
- **Proper result unwrapping** - All setup calls must unwrap, test calls check success
- **Clear test names** - Descriptive names that explain what's being tested
- **Comprehensive setup** - Proper test data creation with relationships
- **Edge case handling** - Test boundary conditions and error cases

### Validation Approach
1. **Generate TypeScript** after implementation: `mix test.codegen`
2. **Validate TypeScript compilation**: `cd test/ts && npm run compileGenerated`
3. **Run Elixir tests**: `mix test test/ash_typescript/rpc/rpc_run_action_*_test.exs`
4. **Integration validation**: All new tests should pass consistently

## Notes & Considerations

### Differences from Processor Tests
- **Processor tests** validate internal logic (`RequestedFieldsProcessor.process/3`)
- **RPC run action tests** validate end-to-end behavior (`Rpc.run_action/3`)
- **Integration vs Unit** - RPC tests are integration tests with real data setup
- **Error handling** - RPC tests validate user-facing error messages and structure

### Maintenance Strategy
- **Keep in sync** - When processor tests change, update corresponding RPC tests
- **Avoid duplication** - Focus on integration testing, not reimplementing unit test logic
- **Real-world scenarios** - Prioritize testing patterns that users will actually encounter

### Success Criteria
✅ All high priority tests implemented and passing  
✅ TypeScript generation works with all new test scenarios  
✅ No redundant assertions in any test files  
✅ All RPC calls properly unwrapped  
✅ Comprehensive error scenario coverage  
✅ Tests follow established patterns from existing RPC tests