# AI Development Workflow

This guide provides step-by-step workflows for common development tasks that AI assistants need to perform when working with AshTypescript.

## Quick Start Workflow

### For New AI Assistants

1. **Understand the project scope**:
   ```bash
   # Read the main entry point
   cat CLAUDE.md
   
   # Review the README for user perspective  
   cat README.md
   ```

2. **Check current state**:
   ```bash
   # Run tests to ensure everything works
   mix test
   
   # Generate current TypeScript types
   mix test.codegen
   
   # Validate TypeScript compilation
   cd test/ts && npm run compileGenerated
   ```

3. **Explore the test domain**:
   ```bash
   # See the comprehensive test setup
   cat test/support/domain.ex
   cat test/support/resources/todo.ex
   ```

## Core Development Workflows

### Workflow 1: Adding Support for New Ash Types

**When**: A user wants to use an Ash type that doesn't have TypeScript mapping

**Steps**:

1. **Identify the gap**:
   ```bash
   # Check current type mappings
   grep -n "def get_ts_type" lib/ash_typescript/codegen.ex
   
   # Look for failing type generation
   mix test.codegen --dry-run | grep "any"  # Look for unmapped types
   ```

2. **Add type mapping**:
   ```elixir
   # In lib/ash_typescript/codegen.ex, add before the catch-all:
   def get_ts_type(%{type: Ash.Type.YourNewType, constraints: constraints}, context) do
     # Handle constraints if any
     case Keyword.get(constraints, :specific_constraint) do
       nil -> "your_typescript_type"
       value -> "more_specific_type"
     end
   end
   ```

3. **Test the mapping**:
   ```bash
   # Add test cases
   # Edit test/ts_codegen_test.exs
   
   # Run specific tests
   mix test test/ts_codegen_test.exs
   
   # Generate and check TypeScript
   mix test.codegen
   cd test/ts && npm run compileGenerated
   ```

4. **Validate with real usage**:
   ```bash
   # Add to test resource if needed
   # Edit test/support/resources/todo.ex
   
   # Test full pipeline
   mix test
   ```

### Workflow 2: Adding New RPC Actions

**When**: Need to expose new resource actions via RPC

**Steps**:

1. **Define the action in resource** (if new):
   ```elixir
   # In resource file (e.g., test/support/resources/todo.ex)
   actions do
     action :your_new_action, :generic do
       argument :your_arg, :string
       returns :map
       run fn input, _context ->
         {:ok, %{result: "success"}}
       end
     end
   end
   ```

2. **Expose via RPC**:
   ```elixir
   # In test/support/domain.ex (or your domain)
   rpc do
     resource YourResource do
       rpc_action :your_rpc_name, :your_new_action
     end
   end
   ```

3. **Generate and test**:
   ```bash
   # Generate TypeScript
   mix test.codegen
   
   # Check the generated function
   grep -A 10 "yourRpcName" test/ts/generated.ts
   
   # Test compilation
   cd test/ts && npm run compileGenerated
   ```

4. **Add test coverage**:
   ```elixir
   # Add to appropriate test file (e.g., test/ash_typescript/rpc/rpc_<type>_test.exs)
   test "your new action works" do
     params = %{
       "action" => "your_rpc_name",
       "input" => %{"your_arg" => "test_value"}
     }
     
     result = Rpc.run_action(:ash_typescript, conn, params)
     assert %{success: true, data: data} = result
   end
   ```

### Workflow 3: Implementing Complex Calculation Support

**When**: Adding calculations that return resources or need field selection

**Steps**:

1. **Define the calculation**:
   ```elixir
   # In resource file
   calculate :your_calc, :struct, YourCalculation do
     constraints instance_of: __MODULE__  # For resource-returning calcs
     public? true
     
     argument :your_arg, :string do
       allow_nil? true
     end
   end
   ```

2. **Implement calculation module**:
   ```elixir
   defmodule YourCalculation do
     use Ash.Calculation
     
     def calculate(records, opts, context) do
       # Return actual resource instances for nested calculation support
       Enum.map(records, &transform_record/1)
     end
   end
   ```

3. **Test recursive patterns**:
   ```bash
   # Generate TypeScript
   mix test.codegen
   
   # Check for recursive type support
   grep -A 5 "calculations?" test/ts/generated.ts
   
   # Test nested usage
   cd test/ts && npm run compileShouldPass
   ```

4. **Add comprehensive tests**:
   ```elixir
   # In test/ash_typescript/rpc/rpc_calcs_test.exs
   test "nested calculation with field selection" do
     params = %{
       "action" => "get_todo",
       "fields" => ["id", "title"],
       "calculations" => %{
         "your_calc" => %{
           "calcArgs" => %{"your_arg" => "value"},
           "fields" => ["id", "other_field"],
           "calculations" => %{
             "your_calc" => %{
               "calcArgs" => %{"your_arg" => "nested"},
               "fields" => ["id"]
             }
           }
         }
       },
       "input" => %{"id" => todo.id}
     }
     
     result = Rpc.run_action(:ash_typescript, conn, params)
     assert %{success: true, data: data} = result
     
     # Verify field selection at all levels
     assert Map.keys(data) |> Enum.sort() == ["id", "title", "your_calc"]
     assert Map.keys(data["your_calc"]) |> Enum.sort() == ["id", "other_field", "your_calc"]
   end
   ```

### Workflow 4: Adding Multitenancy Support

**When**: Working with resources that need tenant isolation

**Steps**:

1. **Configure resource multitenancy**:
   ```elixir
   # In resource file
   multitenancy do
     strategy :attribute  # or :context
     attribute :tenant_id  # for attribute strategy
   end
   ```

2. **Add to test domain**:
   ```elixir
   # In test/support/domain.ex
   rpc do
     resource YourMultitenantResource do
       rpc_action :list_items, :read
       rpc_action :create_item, :create
     end
   end
   ```

3. **Create dedicated test file**:
   ```elixir
   # Create test/ash_typescript/rpc/rpc_your_resource_multitenancy_test.exs
   defmodule AshTypescript.Rpc.YourResourceMultitenancyTest do
     use ExUnit.Case, async: false  # Required for Application.put_env
     
     import Phoenix.ConnTest
     import Plug.Conn
     
     setup do
       Application.put_env(:ash_typescript, :require_tenant_parameters, true)
       on_exit(fn -> Application.delete_env(:ash_typescript, :require_tenant_parameters) end)
       
       conn = build_conn() |> put_private(:ash, %{actor: nil, tenant: nil})
       tenant1 = Ash.UUID.generate()
       tenant2 = Ash.UUID.generate()
       
       {:ok, conn: conn, tenant1: tenant1, tenant2: tenant2}
     end
     
     # Add isolation tests
   end
   ```

4. **Test tenant isolation**:
   ```bash
   # Run multitenancy tests
   mix test test/ash_typescript/rpc/rpc_*multitenancy*
   
   # Test TypeScript generation with tenant parameters
   Application.put_env(:ash_typescript, :require_tenant_parameters, true)
   mix test.codegen
   grep "tenant" test/ts/generated.ts
   ```

### Workflow 5: Debugging Type Inference Issues

**When**: TypeScript types aren't being inferred correctly

**Steps**:

1. **Generate with debug output**:
   ```bash
   # See what's being generated
   mix test.codegen --dry-run
   
   # Check specific resource types
   mix test.codegen --dry-run | grep -A 20 "YourResourceSchema"
   ```

2. **Test TypeScript compilation step by step**:
   ```bash
   cd test/ts
   
   # Test basic compilation
   npm run compileGenerated
   
   # Test positive cases
   npm run compileShouldPass
   
   # Test negative cases (should show expected errors)
   npm run compileShouldFail
   ```

3. **Debug type inference pipeline**:
   ```elixir
   # Add debug prints in lib/ash_typescript/rpc/codegen.ex
   # Around InferResourceResult generation
   
   # Check field selection logic
   # In lib/ash_typescript/rpc/helpers.ex:extract_return_value/3
   ```

4. **Create minimal reproduction**:
   ```elixir
   # Add simple test case to test/ts/shouldPass.ts
   const testResult = await getYourResource({
     fields: ["id"],
     calculations: {
       yourCalc: {
         calcArgs: { arg: "value" },
         fields: ["id"]
       }
     }
   });
   
   // This should be properly typed
   const id: string = testResult.id;
   ```

## Testing Workflows

### Complete Testing Workflow

**Before any changes**:
```bash
# Baseline check
mix test
cd test/ts && npm run compileGenerated
```

**After making changes**:
```bash
# 1. Elixir tests
mix test

# 2. Type generation
mix test.codegen

# 3. TypeScript validation  
cd test/ts
npm run compileGenerated    # Should compile cleanly
npm run compileShouldPass   # Valid patterns should work
npm run compileShouldFail   # Invalid patterns should fail

# 4. Quality checks
mix format
mix credo --strict
mix dialyzer
```

### Testing Specific Features

**Field Selection Testing**:
```bash
# Test field selection logic
mix test test/ash_typescript/rpc/rpc_calcs_test.exs -t field_selection

# Test multitenancy field selection
mix test test/ash_typescript/rpc/rpc_multitenancy_*_test.exs
```

**TypeScript Type Testing**:
```bash
# Test positive type inference
cd test/ts && npm run compileShouldPass

# Add your test to shouldPass.ts:
# - Complex nested calculations
# - Deep relationship selection  
# - Edge cases with optional fields

# Test negative type checking
cd test/ts && npm run compileShouldFail

# Add your test to shouldFail.ts:
# - Invalid field names
# - Wrong argument types
# - Missing required properties
```

## Release Workflow

### Pre-Release Checklist

1. **Complete test coverage**:
   ```bash
   mix test
   cd test/ts && npm run compileGenerated
   cd test/ts && npm run compileShouldPass
   cd test/ts && npm run compileShouldFail
   ```

2. **Quality checks**:
   ```bash
   mix format --check-formatted
   mix credo --strict
   mix dialyzer
   mix sobelow
   ```

3. **Documentation update**:
   ```bash
   mix docs
   # Update CHANGELOG.md if needed
   ```

4. **Version compatibility**:
   ```bash
   # Test with different Ash versions if applicable
   ASH_VERSION=main mix test
   ```

## Emergency Debugging Workflow

**When tests are failing unexpectedly**:

1. **Isolate the issue**:
   ```bash
   # Run failing test in isolation
   mix test path/to/failing_test.exs:line_number
   
   # Check if it's type generation related
   mix test.codegen --dry-run
   ```

2. **Check recent changes**:
   ```bash
   git diff HEAD~1 -- lib/ash_typescript/
   ```

3. **Validate against working baseline**:
   ```bash
   # Generate types and compare
   mix test.codegen
   cd test/ts && npm run compileGenerated
   
   # Check TypeScript compilation errors in detail
   cd test/ts && npx tsc generated.ts --noErrorTruncation
   ```

4. **Test in clean environment**:
   ```bash
   # Fresh dependency fetch
   mix deps.clean --all
   mix deps.get
   mix test
   ```

This workflow documentation ensures AI assistants can handle both routine development tasks and complex debugging scenarios while maintaining the code quality and type safety standards of the project.