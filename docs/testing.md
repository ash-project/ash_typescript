# Testing System

## Test Architecture

### Core Test Domain: AshTypescript.Test.Domain
Located at `test/support/domain.ex` with comprehensive RPC configuration:
- All major resources with RPC actions
- Resource catalog including edge cases
- Proper AshTypescript.Rpc extension setup

### Test Resources Overview

**Primary Resources** (Full-featured):
- **`AshTypescript.Test.Todo`** - Main comprehensive test resource
- **`AshTypescript.Test.User`** - User management with relationships
- **`AshTypescript.Test.TodoComment`** - Comment system with ratings

**Secondary Resources** (Specialized):
- **`AshTypescript.Test.Post`** - Blog-style content
- **`AshTypescript.Test.PostComment`** - Secondary comment system
- **`AshTypescript.Test.NotExposed`** - Non-RPC resource (visibility testing)

**Edge Case Resources**:
- **`AshTypescript.Test.EmptyResource`** - Minimal resource with only ID
- **`AshTypescript.Test.NoRelationshipsResource`** - Simple without relationships

### Primary Test Resource: Todo

The `Todo` resource (`test/support/resources/todo.ex`) provides complete Ash feature coverage:

#### Attributes Coverage
- Primary key (UUID), basic types (string, boolean, date, integer)
- Enums (custom `Status` enum), constraints (one_of validation, min/max)
- Defaults, timestamps, visibility mix (public/private)

#### Relationships Coverage
- belongs_to (required user with foreign key)
- has_many (comments with filtering/sorting)
- Mixed visibility (including non-exposed resources)

#### Aggregates Coverage
- **count**: `comment_count`, `helpful_comment_count` (with filters)
- **exists**: `has_comments`
- **avg**: `average_rating`
- **max**: `highest_rating`
- **first**: `latest_comment_content` (with sorting)
- **list**: `comment_authors`

#### Calculations Coverage
- Expression calculations (boolean, date)
- Module calculations (complex logic with arguments)
- Self-referencing (struct calculations)
- Argument support (optional with defaults)

#### Actions Coverage
- CRUD operations (create, read, update, destroy)
- Custom updates (`complete`, `set_priority`)
- Generic actions (`bulk_complete`, `get_statistics`, `search`)
- Argument handling (required/optional with validation)

### RPC Action Configuration

Domain configured with comprehensive RPC actions:

```elixir
# Todo resource - 10 RPC actions covering all patterns
rpc_action :list_todos, :read
rpc_action :get_todo, :get
rpc_action :create_todo, :create
rpc_action :update_todo, :update
rpc_action :complete_todo, :complete
rpc_action :set_priority_todo, :set_priority
rpc_action :bulk_complete_todo, :bulk_complete
rpc_action :get_statistics_todo, :get_statistics
rpc_action :search_todos, :search
rpc_action :destroy_todo, :destroy
```

## Test File Organization

Tests organized by functional area in `test/ash_typescript/rpc/`:

- **`rpc_read_test.exs`** - Read operations, filtering, field selection
- **`rpc_create_test.exs`** - Creation with arguments and relationships
- **`rpc_update_test.exs`** - Updates including custom update actions
- **`rpc_destroy_test.exs`** - Deletion operations
- **`rpc_filtering_test.exs`** - Complex filtering scenarios
- **`rpc_calcs_test.exs`** - Calculation loading and arguments
- **`rpc_parsing_test.exs`** - Input parsing and validation
- **`rpc_error_handling_test.exs`** - Error scenarios and edge cases
- **`rpc_context_test.exs`** - Context handling (actor, tenant, etc.)
- **`rpc_codegen_test.exs`** - TypeScript code generation testing

### Supporting Modules

Calculation modules in `test/support/resources/`:
- **`calculations/self_calculation.ex`** - Struct testing
- **`todo/date_calculations.ex`** - Date manipulation
- **`todo/owner_calculation.ex`** - Relationship-based
- **`todo/status.ex`** - Custom enum type

### TypeScript Integration

- **Location**: `test/ts/` directory
- **Generated Output**: `generated.ts` and `generated.js`
- **Validation**: `npm run compile` verifies compilation
- **Type Tests**: `typeTests.ts` for additional checking

## Development Workflows

### Essential Test Commands
```bash
mix test                        # Run all tests
mix test.codegen               # Generate types (alias)
mix test.ts # Compile & test generated TypeScript files.
```

### When Adding Features
1. **Extend Todo Resource**: Add new attribute/relationship/action types
2. **Create Specialized Resources**: For edge cases
3. **Update RPC Configuration**: Add actions to domain RPC block
4. **Organize by Function**: Add tests to appropriate test file
5. **Verify TypeScript**: Ensure generated code compiles

### When Testing Edge Cases
1. **Use Empty/NoRelationships Resources**: Minimal testing
2. **Use NotExposed Resource**: Visibility/access control
3. **Create Focused Resources**: Specific scenarios

### Test Data Setup
All resources use `Ash.DataLayer.Ets` with `private? true`:
- Fast in-memory storage
- Test isolation
- No external dependencies

## Verification Patterns

### Type Generation Testing
```elixir
test "generates correct TypeScript types" do
  typescript_content = generate_typescript_types()
  assert typescript_content =~ "type TodoSchema = {"
  assert typescript_content =~ "title: string"
  assert typescript_content =~ "completed?: boolean"
end
```

### RPC Client Testing
```elixir
test "generates RPC client functions" do
  assert typescript_content =~ "async createTodo("
  assert typescript_content =~ "TodoCreateInput"
  assert typescript_content =~ "Promise<TodoSchema>"
end
```

### Generated Output Structure
```typescript
// Base aliases
type UUID = string;
type DateTime = string;

// Resource schemas
type TodoSchema = { /* ... */ };

// Input types
type TodoCreateInput = { /* ... */ };

// RPC client
class AshRpc { /* ... */ }
```

### CI Verification
Tests ensure:
1. TypeScript compiles without errors
2. Correct type definitions generated
3. Expected schema structure
4. All RPC actions included

## RPC Implementation Notes

### Calculation Handling
Two approaches:
1. **Via `fields`**: Simple loading without arguments
2. **Via `calculations`**: Enhanced with arguments and field selection

### Key Implementation Details
- Uses `Ash.Type.cast_input/3` for type casting
- Field selection applied post-loading
- Separation of loading vs field selection specs

### Common Troubleshooting
- **BadMapError**: Ash validation expects different argument structure
- **KeyError :type**: Missing argument type definitions
- **Solution**: Post-processing field selection vs passing to Ash load
