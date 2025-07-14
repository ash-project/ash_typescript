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

## Test Connection Setup

### Proper Conn Structure (Important Migration Notes)

⚠️ **Breaking Change**: As of Ash 3.5+, storing tenant and actor information directly in `conn.assigns` is **deprecated** and will generate warnings:

```
[warning] Storing the tenant in conn assigns is deprecated.
  deps/ash/lib/ash/plug_helpers.ex:169: Ash.PlugHelpers.get_tenant/1
```

### ✅ Modern Approach (Recommended)

All test files should use proper `Plug.Conn` structs with Phoenix test helpers:

```elixir
defmodule AshTypescript.Rpc.SomeTest do
  use ExUnit.Case, async: true
  import Phoenix.ConnTest        # For build_conn/0
  import Plug.Conn              # For put_private/3, assign/3
  alias AshTypescript.Rpc

  setup do
    # Create proper Plug.Conn struct
    conn = build_conn()
    |> put_private(:ash, %{actor: nil, tenant: nil})
    |> assign(:context, %{})

    {:ok, conn: conn}
  end
  
  # For setting tenant in tests (connection mode)
  test "example with tenant", %{conn: conn} do
    conn_with_tenant = Ash.PlugHelpers.set_tenant(conn, tenant_id)
    # ... rest of test
  end
end
```

### ❌ Legacy Approach (Deprecated)

```elixir
# DON'T DO THIS - Generates deprecation warnings
setup do
  conn = %{
    assigns: %{
      actor: nil,
      tenant: nil,
      context: %{}
    }
  }
  
  # DON'T DO THIS - Manual manipulation
  conn_with_tenant = put_in(conn.assigns.tenant, tenant_id)
end
```

### Required Imports for Test Files

All RPC test files need these imports:

```elixir
import Phoenix.ConnTest    # Provides build_conn/0
import Plug.Conn          # Provides put_private/3, assign/3
```

### Tenant Assignment Best Practices

When testing connection-mode multitenancy, use the official helper:

```elixir
# ✅ Correct - Uses Ash helper function
conn_with_tenant = Ash.PlugHelpers.set_tenant(conn, tenant_id)

# ❌ Incorrect - Manual manipulation (deprecated)
conn_with_tenant = put_in(conn.assigns.private.ash.tenant, tenant_id)
```

### Migration Checklist

When updating existing test files:

1. Add `import Phoenix.ConnTest` and `import Plug.Conn`
2. Replace conn map creation with `build_conn() |> put_private(:ash, %{...})`
3. Replace manual tenant assignment with `Ash.PlugHelpers.set_tenant/2`
4. Verify tests still pass with proper Plug.Conn structs

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
- **`rpc_multitenancy_attribute_test.exs`** - Attribute-based multitenancy testing
- **`rpc_multitenancy_context_test.exs`** - Context-based multitenancy testing
- **`rpc_multitenancy_codegen_test.exs`** - Dedicated TypeScript codegen validation for multitenancy
- **`rpc_tenant_config_test.exs`** - Tenant configuration and parameter handling

## Multitenancy Testing Patterns

### Overview

Testing multitenant resources requires comprehensive coverage of both tenant parameter modes, security isolation, error scenarios, and TypeScript code generation. The test suite provides patterns for both attribute-based and context-based multitenancy strategies.

### Test Resource Architecture

#### UserSettings (Attribute-based Multitenancy)
```elixir
multitenancy do
  strategy :attribute
  attribute :user_id
end
```
- Uses User as tenant identifier
- Tests attribute-based isolation
- Validates tenant parameter handling

#### OrgTodo (Context-based Multitenancy)  
```elixir
multitenancy do
  strategy :context
end
```
- Uses organization context (no tenant stored as attribute)
- Tests context-based isolation across different organizations
- Validates tenant context handling in data layer
- More flexible tenant identification (UUID, string, etc.)

### Core Testing Strategies

#### 1. Configuration Testing
Validates multitenancy detection and parameter requirements:
```elixir
test "requires_tenant? returns true for multitenant resources" do
  assert Rpc.requires_tenant?(UserSettings) == true
  refute Rpc.requires_tenant?(Todo)  # Non-multitenant
end

test "requires_tenant_parameter? respects configuration" do
  Application.put_env(:ash_typescript, :require_tenant_parameters, true)
  assert Rpc.requires_tenant_parameter?(UserSettings) == true
  
  Application.put_env(:ash_typescript, :require_tenant_parameters, false)
  assert Rpc.requires_tenant_parameter?(UserSettings) == false
end
```

#### 2. Parameter Mode Testing (`require_tenant_parameters: true`)
Tests operations when tenant is passed as request parameter:
```elixir
test "creates resource with tenant parameter" do
  params = %{
    "action" => "create_user_settings",
    "fields" => ["id", "user_id", "theme"],
    "input" => %{
      "user_id" => user1.id,
      "theme" => "dark"
    },
    "tenant" => user1.id  # Required tenant parameter
  }

  result = Rpc.run_action(:ash_typescript, conn, params)
  assert %{success: true, data: settings} = result
  assert settings.user_id == user1.id
end

test "fails without tenant parameter" do
  params = %{
    "action" => "create_user_settings",
    "input" => %{"user_id" => user1.id, "theme" => "dark"}
    # Missing tenant parameter
  }

  assert_raise RuntimeError, ~r/Tenant parameter is required/, fn ->
    Rpc.run_action(:ash_typescript, conn, params)
  end
end
```

#### 3. Connection Mode Testing (`require_tenant_parameters: false`)
Tests operations when tenant is extracted from connection context:
```elixir
setup do
  Application.put_env(:ash_typescript, :require_tenant_parameters, false)
  on_exit(fn -> Application.delete_env(:ash_typescript, :require_tenant_parameters) end)
end

test "creates resource with tenant in connection" do
  conn_with_tenant = Ash.PlugHelpers.set_tenant(conn, user1.id)

  params = %{
    "action" => "create_user_settings",
    "input" => %{"user_id" => user1.id, "theme" => "dark"}
    # No tenant parameter needed
  }

  result = Rpc.run_action(:ash_typescript, conn_with_tenant, params)
  assert %{success: true, data: settings} = result
end
```

#### 4. Tenant Isolation Testing
Validates security isolation between tenants:
```elixir
test "tenant isolation prevents cross-tenant access" do
  # Create settings for user1
  create_user1_settings(user1.id, "dark")
  
  # Create settings for user2  
  create_user2_settings(user2.id, "light")

  # User1 should only see their settings
  user1_settings = list_user_settings(user1.id)
  assert length(user1_settings) == 1
  assert hd(user1_settings).user_id == user1.id

  # User2 should only see their settings
  user2_settings = list_user_settings(user2.id)
  assert length(user2_settings) == 1
  assert hd(user2_settings).user_id == user2.id
end
```

#### 5. Error Scenario Testing
Comprehensive error handling validation:
```elixir
test "invalid tenant parameter" do
  params = %{
    "action" => "create_user_settings",
    "input" => %{"user_id" => user1.id, "theme" => "dark"},
    "tenant" => "invalid-uuid"
  }

  result = Rpc.run_action(:ash_typescript, conn, params)
  assert %{success: false, errors: errors} = result
  assert String.contains?(errors.message, "invalid")
end

test "destroy with wrong tenant" do
  # Create with user1's tenant
  settings = create_user_settings(user1.id)
  
  # Try to destroy with user2's tenant
  params = %{
    "action" => "destroy_user_settings",
    "primary_key" => settings.id,
    "tenant" => user2.id
  }

  result = Rpc.run_action(:ash_typescript, conn, params)
  assert %{success: false, errors: _errors} = result
end
```

#### 6. Update Operation Testing
Validates correct update structure with multitenancy:
```elixir
test "updates with correct primary_key structure" do
  # Create settings
  create_result = create_user_settings(user1.id, "light")
  settings = create_result.data

  # Update using correct structure
  update_params = %{
    "action" => "update_user_settings",
    "primary_key" => settings.id,        # ✅ Correct: ID in primary_key
    "input" => %{"theme" => "dark"},     # ✅ Correct: Only changes in input
    "tenant" => user1.id,
    "fields" => ["id", "theme"]
  }

  result = Rpc.run_action(:ash_typescript, conn, update_params)
  assert %{success: true, data: updated_settings} = result
  assert updated_settings.theme == :dark
end
```

#### 7. TypeScript Codegen Testing
Validates generated TypeScript interfaces for multitenancy:
```elixir
test "generates tenant fields when require_tenant_parameters is true" do
  Application.put_env(:ash_typescript, :require_tenant_parameters, true)

  typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

  # Verify tenant fields are included in multitenant resource types
  assert String.contains?(typescript_output, "tenant")
  assert String.contains?(typescript_output, "UserSettingsResourceSchema")
end

test "omits tenant fields when require_tenant_parameters is false" do
  Application.put_env(:ash_typescript, :require_tenant_parameters, false)

  typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

  # Verify basic types are generated without tenant requirements
  assert String.contains?(typescript_output, "UserSettingsResourceSchema")
end
```

#### Dedicated TypeScript Codegen Test

The `rpc_multitenancy_codegen_test.exs` file provides comprehensive validation specifically for TypeScript code generation with multitenancy support. This dedicated test file focuses exclusively on codegen validation, separating it from functional testing:

**Coverage Areas:**
- **Resource Type Generation**: Validates TypeScript types for both attribute and context-based multitenancy strategies
- **Config Type Generation**: Tests tenant field inclusion/exclusion based on `require_tenant_parameters` setting
- **Function Interface Generation**: Verifies RPC function signatures for multitenant resources
- **Request/Response Validation**: Ensures proper input and response type generation
- **Cross-Strategy Compatibility**: Tests that both multitenancy strategies generate compatible interfaces
- **Validation Function Generation**: Confirms validation functions are generated correctly for multitenant resources
- **Non-Regression Testing**: Ensures multitenancy doesn't break non-multitenant resource codegen

**Example Test Structure:**
```elixir
describe "tenant field generation with require_tenant_parameters: true" do
  setup do
    Application.put_env(:ash_typescript, :require_tenant_parameters, true)
    on_exit(fn -> Application.delete_env(:ash_typescript, :require_tenant_parameters) end)
  end

  test "includes tenant fields in UserSettings action config types" do
    typescript_output = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)
    
    assert String.contains?(typescript_output, "tenant")
    assert String.contains?(typescript_output, "CreateUserSettingsConfig")
  end
end
```

### Error Handling Patterns

#### Exception-based Validation
The RPC system raises exceptions for missing tenant parameters:
```elixir
# ✅ Correct: Use assert_raise for tenant parameter validation
assert_raise RuntimeError, ~r/Tenant parameter is required/, fn ->
  Rpc.run_action(:ash_typescript, conn, params_without_tenant)
end

# ❌ Incorrect: Expecting error response structure
assert %{success: false, error: _} = Rpc.run_action(:ash_typescript, conn, params)
```

#### Error Response Structure
When operations fail, the system returns structured errors:
```elixir
result = Rpc.run_action(:ash_typescript, conn, invalid_params)
assert %{success: false, errors: errors} = result
assert String.contains?(errors.message, "expected_error_text")
```

### Data Layer Considerations

#### ETS Limitations
When using ETS data layer for testing:
- Tenant isolation may not be as strict as database-backed multitenancy
- Focus on testing RPC parameter handling and Ash integration
- Adjust test expectations for data layer capabilities

#### Test Setup Patterns
```elixir
setup do
  # Create test users for tenant isolation
  user1 = create_test_user("User One", "user1@example.com")
  user2 = create_test_user("User Two", "user2@example.com")
  
  # Mock connection structure
  conn = %{assigns: %{actor: nil, tenant: nil, context: %{}}}
  
  {:ok, conn: conn, user1: user1, user2: user2}
end
```

### Context-based Multitenancy Testing Patterns

#### Key Differences from Attribute-based Testing

Context-based multitenancy (like `OrgTodo`) differs from attribute-based in several important ways:

1. **Tenant Storage**: Tenant is not stored as an attribute in the record
2. **Tenant Context**: Organization IDs are passed as context, not foreign keys
3. **Isolation Mechanism**: Data layer handles tenant context rather than WHERE clauses
4. **Flexibility**: Supports various tenant identifier formats (UUID, strings, etc.)

#### Context-based Test Setup

```elixir
setup do
  # Generate organization tenant IDs for context-based multitenancy
  org1_id = Ash.UUID.generate()
  org2_id = Ash.UUID.generate()
  
  {:ok, conn: conn, user1: user1, user2: user2, org1_id: org1_id, org2_id: org2_id}
end
```

#### Parameter Mode Testing (Context Strategy)

```elixir
test "creates org todo with tenant parameter", %{conn: conn, user1: user1, org1_id: org1_id} do
  params = %{
    "action" => "create_org_todo",
    "fields" => ["id", "title", "user_id"],
    "input" => %{
      "title" => "Organization Task",
      "user_id" => user1.id
    },
    "tenant" => org1_id  # Organization context, not stored in record
  }

  result = Rpc.run_action(:ash_typescript, conn, params)
  assert %{success: true, data: todo} = result
  assert todo.title == "Organization Task"
  # Note: org1_id is NOT stored as an attribute in the todo
end
```

#### Cross-Tenant Isolation Testing

```elixir
test "organization isolation prevents cross-organization access" do
  # Create todo for org1
  create_org_todo(org1_id, "Org1 Todo", user1.id)
  
  # Create todo for org2  
  create_org_todo(org2_id, "Org2 Todo", user2.id)

  # Org1 context should only see org1 todos
  org1_todos = list_org_todos(org1_id)
  assert length(org1_todos) == 1
  assert hd(org1_todos).title == "Org1 Todo"

  # Org2 context should only see org2 todos
  org2_todos = list_org_todos(org2_id)
  assert length(org2_todos) == 1
  assert hd(org2_todos).title == "Org2 Todo"
end
```

#### Cross-Tenant Operation Errors

```elixir
test "destroy with wrong organization tenant" do
  # Create todo in org1 context
  create_result = create_org_todo(org1_id, "Destroy Test", user1.id)
  todo = create_result.data

  # Attempt to destroy using org2 context
  destroy_params = %{
    "action" => "destroy_org_todo",
    "primary_key" => todo.id,
    "tenant" => org2_id  # Wrong organization context
  }

  result = Rpc.run_action(:ash_typescript, conn, destroy_params)
  assert %{success: false, errors: _errors} = result
end
```

#### Context vs Attribute Strategy Comparison

| Aspect | Attribute Strategy (UserSettings) | Context Strategy (OrgTodo) |
|--------|-----------------------------------|----------------------------|
| **Tenant Storage** | Stored as `user_id` attribute | Not stored in record |
| **Isolation Method** | Database WHERE clauses | Data layer context |
| **Test Setup** | User records as tenants | Generated organization IDs |
| **Cross-tenant Errors** | Record not found or access denied | Context-based access denied |
| **Flexibility** | Tied to specific attribute | Any identifier format |

### Best Practices

#### Critical: Application Configuration in Tests
⚠️ **IMPORTANT**: All test modules that use `Application.put_env/3` or `Application.delete_env/2` MUST use `async: false`:

```elixir
# ✅ Correct: Tests that modify application config
defmodule AshTypescript.Rpc.MultitenancyAttributeTest do
  use ExUnit.Case, async: false  # REQUIRED for Application.put_env usage
  
  setup do
    Application.put_env(:ash_typescript, :require_tenant_parameters, true)
    on_exit(fn -> Application.delete_env(:ash_typescript, :require_tenant_parameters) end)
  end
end

# ❌ Incorrect: Race conditions will occur
defmodule AshTypescript.Rpc.MultitenancyAttributeTest do
  use ExUnit.Case, async: true  # DANGEROUS with Application.put_env
  
  setup do
    Application.put_env(:ash_typescript, :require_tenant_parameters, true)
    # This will interfere with other async tests!
  end
end
```

**Why this matters:**
- `Application.put_env/3` modifies global state shared across all test processes
- When tests run `async: true`, multiple tests can modify the same config simultaneously
- This causes unpredictable test failures and race conditions
- Multitenancy tests are particularly susceptible because they test different configuration modes

#### Test Organization
1. **Group by functionality**: Configuration, parameter mode, connection mode, errors
2. **Use descriptive setup blocks**: Configure tenant parameter mode per test group
3. **Clean up configuration**: Use `on_exit` to reset application environment
4. **Test both strategies**: Create resources for attribute and context multitenancy
5. **Strategy-specific tests**: Separate test files for different multitenancy strategies
6. **Async safety**: Always use `async: false` for tests that modify application configuration

#### Comprehensive Coverage
1. **Both tenant modes**: Test parameter and connection-based tenant handling
2. **CRUD operations**: Ensure all operations respect tenant context
3. **Error scenarios**: Invalid tenants, missing parameters, cross-tenant access
4. **TypeScript generation**: Verify correct interface generation for both modes
5. **Security validation**: Confirm tenant isolation works as expected
6. **Strategy differences**: Test attribute vs context-specific behaviors

**Multitenancy Resources** (Added for comprehensive testing):
- **`AshTypescript.Test.UserSettings`** - Attribute-based multitenancy testing
- **`AshTypescript.Test.OrgTodo`** - Context-based multitenancy testing

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
- **Type Tests**: 
  - `shouldPass.ts` - Stress tests for type inference and correct usage patterns
  - `shouldFail.ts` - Tests that incorrect usage fails TypeScript compilation

## Development Workflows

### Essential Test Commands
```bash
mix test                        # Run all tests
mix test.codegen               # Generate types (alias)

# TypeScript compilation testing (run from test/ts directory)
cd test/ts && npm run compileGenerated     # Generate TS and compile the generated output
cd test/ts && npm run compileShouldPass    # Compile shouldPass.ts (stress tests for type inference)
cd test/ts && npm run compileShouldFail    # Compile shouldFail.ts (tests that should fail compilation)
```

### TypeScript Testing Workflow

The project includes npm scripts for testing TypeScript compilation. **Important**: Run these commands from the `test/ts` directory to see the actual TypeScript compiler output.

#### `npm run compileGenerated`
- Compiles the generated `test/ts/generated.ts` file 
- Shows compilation errors for debugging type generation issues
- Run after `mix test.codegen` to validate generated TypeScript

#### `npm run compileShouldPass`
- Compiles `test/ts/shouldPass.ts`
- Used to stress test type inference and validate correct usage patterns
- Should contain complex but valid usage of generated types and functions
- Helps ensure generated types support real-world usage scenarios

#### `npm run compileShouldFail`
- Compiles `test/ts/shouldFail.ts`  
- Used to verify that incorrect usage fails TypeScript compilation
- Should contain edge cases and invalid usage patterns
- Helps ensure type safety by confirming wrong usage is rejected

**Complete Testing Workflow**:
```bash
# 1. Generate fresh TypeScript types
mix test.codegen

# 2. Navigate to TypeScript test directory  
cd test/ts

# 3. Test compilation (choose appropriate script)
npm run compileGenerated      # Test generated types compile
npm run compileShouldPass     # Test valid usage patterns  
npm run compileShouldFail     # Test invalid usage rejection
```

The npm scripts print detailed TypeScript compilation errors to the terminal for inspection and debugging.

### TypeScript Test Files

The project includes comprehensive TypeScript test files that demonstrate usage patterns:

#### `test/ts/shouldPass.ts`
Contains **valid usage patterns** that should compile successfully:
- Basic nested self calculations with field selection
- Deep nesting (3+ levels) with different fields at each level
- Self calculations with relationships in field selection
- List operations with nested calculations
- Create operations with nested calculations in response
- Edge cases with minimal fields and various calcArgs values
- Complex scenarios combining calculations, aggregates, and relationships

#### `test/ts/shouldFail.ts`  
Contains **invalid usage patterns** that should be rejected by TypeScript:
- Invalid field names in calculations
- Wrong types for calcArgs (number, boolean instead of string)
- Invalid calcArgs structure with unknown properties
- Missing required properties (fields, calcArgs)
- Invalid relationship field names
- Wrong calculation types in nested structure
- Type mismatches in variable assignments

Uses `@ts-expect-error` comments to mark lines that should fail compilation.

### When Adding Features
1. **Extend Todo Resource**: Add new attribute/relationship/action types
2. **Create Specialized Resources**: For edge cases
3. **Update RPC Configuration**: Add actions to domain RPC block
4. **Organize by Function**: Add tests to appropriate test file
5. **Verify TypeScript**: Use the npm compilation scripts from `test/ts` directory to validate generated types
6. **Update Test Files**: Add new usage patterns to `shouldPass.ts` and invalid patterns to `shouldFail.ts`

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

### Field Selection Testing Best Practices

#### ✅ Recommended: Exact Field Assertions with Count Verification

Use precise field matching with explicit count checks instead of multiple `refute` statements:

```elixir
test "field selection works correctly" do
  # Test with specific field combinations
  params = %{
    "action" => "get_todo",
    "fields" => ["id", "title"],
    "calculations" => %{
      "self" => %{
        "calcArgs" => %{"prefix" => nil},
        "fields" => ["id", "title", "completed", "dueDate"],
        "calculations" => %{
          "self" => %{
            "calcArgs" => %{"prefix" => nil},
            "fields" => ["id", "status", "metadata"]
          }
        }
      }
    }
  }

  result = Rpc.run_action(:ash_typescript, conn, params)
  assert %{success: true, data: data} = result

  # Verify exact field match at each level
  expected_top_level = ["id", "title", "self"]
  assert Map.keys(data) |> Enum.sort() == expected_top_level |> Enum.sort()
  assert map_size(data) == 3

  # Verify calculation field selection
  self_data = data["self"]
  expected_calc_fields = ["id", "title", "completed", "dueDate", "self"]
  assert Map.keys(self_data) |> Enum.sort() == expected_calc_fields |> Enum.sort()
  assert map_size(self_data) == 5

  # Verify nested calculation field selection
  nested_self = self_data["self"]
  expected_nested = ["id", "status", "metadata"]
  assert Map.keys(nested_self) |> Enum.sort() == expected_nested |> Enum.sort()
  assert map_size(nested_self) == 3
end
```

#### ❌ Avoid: Multiple Refute Statements

Don't use many `refute` statements as they're harder to maintain:

```elixir
# DON'T DO THIS - Verbose and hard to maintain
refute Map.has_key?(data, "description")
refute Map.has_key?(data, "status") 
refute Map.has_key?(data, "priority")
refute Map.has_key?(data, "tags")
refute Map.has_key?(data, "metadata")
# ... many more refute statements
```

#### Field Selection Testing Strategy

1. **Test Multiple Field Combinations**: Use different field sets to ensure flexibility
2. **Verify All Nesting Levels**: Test top-level, calculation, and nested calculation selection
3. **Use `map_size()` Assertions**: Ensure no extra fields are present
4. **Sort Comparisons**: Avoid test flakiness from field order differences

#### Testing Complex Nested Calculations

For nested calculations with field selection:

```elixir
test "nested calculation field selection" do
  # Use different fields at each level to prove selection works independently
  params = %{
    "fields" => ["id", "description", "status"],        # Different from calc fields
    "calculations" => %{
      "self" => %{
        "fields" => ["title", "priority", "tags"],       # Different from nested fields
        "calculations" => %{
          "self" => %{
            "fields" => ["id", "status", "metadata"]     # Different from parent fields
          }
        }
      }
    }
  }
  
  # Verify each level has exactly its requested fields
  # This proves field selection works independently at each nesting level
end
```

#### Benefits of This Approach

- **Maintainable**: Single assertion failure shows complete picture
- **Clear Intent**: Explicitly states what fields should be present
- **Comprehensive**: Catches both missing AND unexpected extra fields
- **Reliable**: Count verification ensures complete field control

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
