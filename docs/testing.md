# Testing System

## Test Structure

### Elixir Tests
- `test/ts_codegen_test.exs`: Core type generation testing
- `test/rpc_test.exs`: RPC DSL and endpoint testing
- `test/ts_filter_test.exs`: Filter handling verification

### TypeScript Tests
- `test/ts/`: TypeScript compilation and type verification
- `test/ts/generated.ts`: Generated output from test resources
- `test/ts/typeTests.ts`: Type assertion tests

## Test Resources

### Test Resource Definitions
Located in `test/support/todo.ex`:
- `AshTypescript.Test.User`: Basic user resource
- `AshTypescript.Test.Todo`: Full-featured todo with all field types
- `AshTypescript.Test.Comment`: Relationship testing

### Key Test Patterns
- **Comprehensive attributes**: All Ash types represented
- **Relationships**: belongs_to, has_many, many_to_many examples
- **Calculations**: Custom calculation implementations
- **Aggregates**: Count, sum, exists examples
- **Custom actions**: Beyond standard CRUD
- **RPC configuration**: Exposed actions for client generation

## Verification Workflows

### Type Generation Verification
```elixir
test "generates correct TypeScript types" do
  # Run codegen on test resources
  typescript_content = generate_typescript_types()

  # Verify specific type definitions exist
  assert typescript_content =~ "type TodoSchema = {"
  assert typescript_content =~ "title: string"
  assert typescript_content =~ "completed?: boolean"
end
```

### TypeScript Compilation Check
```bash
# From test/ts/ directory
npm run compile

# Verifies:
# - Generated types are syntactically valid
# - No TypeScript compilation errors
# - Type references resolve correctly
```

### RPC Client Testing
```elixir
test "generates RPC client functions" do
  # Verify client function generation
  assert typescript_content =~ "async createTodo("
  assert typescript_content =~ "TodoCreateInput"
  assert typescript_content =~ "Promise<TodoSchema>"
end
```

## Test Commands

### Run All Tests
```bash
mix test
```

### Generate and Verify Types
```bash
mix test.codegen  # Alias for ash_typescript.codegen
```

### TypeScript Compilation
```bash
cd test/ts && npm run compile
```

### CI Verification
Tests ensure generated TypeScript:
1. Compiles without errors
2. Has correct type definitions
3. Matches expected schema structure
4. Includes all exposed RPC actions

## Test Resource Features

### Todo Resource Attributes
- All major Ash types (string, integer, boolean, datetime, etc.)
- Enum constraints (`status` field)
- Optional vs required fields
- Default values

### Relationship Testing
- User has many todos and comments
- Todo belongs to user
- Comment belongs to user and todo
- Many-to-many tag relationships

### Advanced Features
- Custom calculations with arguments
- Aggregates (post count, etc.)
- Custom actions beyond CRUD
- Complex validation rules
- Authorization policies

## Output Verification

### Generated File Structure
```typescript
// Base type aliases
type UUID = string;
type DateTime = string;

// Resource schemas
type TodoSchema = { /* ... */ };
type UserSchema = { /* ... */ };

// Input types
type TodoCreateInput = { /* ... */ };

// RPC client
class AshRpc { /* ... */ }
```

### Validation Points
- Correct TypeScript syntax
- Proper type mapping from Ash
- Complete coverage of resource features
- Valid RPC client generation
- No compilation errors

### Development Workflow
1. Make changes to core library files
2. Update test resources if needed
3. Run `mix test` to verify functionality
4. Run `mix credo --strict` for code quality
5. Update documentation if API changes
