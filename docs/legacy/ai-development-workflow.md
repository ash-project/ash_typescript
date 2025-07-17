# AI Development Workflow

This guide provides step-by-step workflows for common development tasks that AI assistants need to perform when working with AshTypescript.

## 🚨 CRITICAL: Environment-First Workflow

### RULE: Always Use Test Environment

**Before ANY AshTypescript work, ensure you're using the test environment:**

```bash
# ✅ CORRECT - All AshTypescript commands
mix test.codegen                    # Generate TypeScript types
mix test                           # Run Elixir tests  
mix test path/to/specific_test.exs  # Run specific test
MIX_ENV=test iex -S mix             # Interactive debugging (if needed)

# ❌ WRONG - Will fail with "No domains found"  
mix ash_typescript.codegen         # Wrong environment
iex -S mix                         # Wrong environment
```

**Why This Matters:**
- Test resources (`AshTypescript.Test.*`) only exist in `:test` environment
- Domain configuration (`config/config.exs`) only active in `:test` environment
- Type generation depends on test resources being available

### Anti-Pattern: One-Off Debugging Commands

**❌ NEVER DO:**
```bash
echo "Code.ensure_loaded(AshTypescript.Test.Todo)" | iex -S mix
echo "AshTypescript.Test.Todo.__info__(:attributes)" | iex -S mix
```

**✅ ALWAYS DO:**
Write a proper test in `test/ash_typescript/` to investigate the issue:

```elixir
test "debug embedded resource detection" do
  resource = AshTypescript.Test.Todo
  attributes = Ash.Resource.Info.public_attributes(resource)
  
  embedded_attrs = Enum.filter(attributes, fn attr ->
    AshTypescript.Codegen.is_embedded_resource_attribute?(attr)
  end)
  
  assert length(embedded_attrs) > 0, "Should find embedded attributes"
end
```

## Advanced Debugging Workflow: Embedded Resource Issues

### Pattern: Experimental Test-First Debugging

**When to Use**: Complex Ash query behavior that's hard to understand through code reading alone.

**WORKFLOW**:

1. **Create Experimental Test File**:
```elixir
# test/ash_typescript/ash_embedded_experiment_test.exs
defmodule AshTypescript.AshEmbeddedExperimentTest do
  use ExUnit.Case, async: true
  
  @moduletag :focus  # Only run this test during debugging
  
  describe "Ash Embedded Resource Query Experiments" do
    test "experiment 1: basic embedded resource selection" do
      # Direct Ash queries to understand behavior
      {:ok, result} = AshTypescript.Test.Todo
        |> Ash.Query.for_read(:read)
        |> Ash.Query.filter(id == ^todo_id)
        |> Ash.Query.select([:metadata])
        |> Ash.Query.load([metadata: [:display_category]])
        |> Ash.read()
        
      IO.inspect(result, label: "Direct Ash result")
    end
  end
end
```

2. **Run Focused Experiments**:
```bash
mix test test/ash_typescript/ash_embedded_experiment_test.exs --trace
```

3. **Compare with RPC System**:
```elixir
# Compare direct Ash approach with RPC system approach
{select, load} = AshTypescript.Rpc.FieldParser.parse_requested_fields(
  client_fields, 
  AshTypescript.Test.Todo, 
  :camel_case
)

IO.inspect({select, load}, label: "RPC FieldParser output")
```

### Pattern: Strategic Debug Outputs

**When to Use**: Complex field processing issues where you need visibility into each stage.

**IMPLEMENTATION**:

```elixir
# In lib/ash_typescript/rpc.ex - Add strategic debug outputs
def run_action(otp_app, conn, params) do
  # ... field processing ...
  
  # 🔍 DEBUG: Load statement analysis
  IO.puts("\n" <> String.duplicate("=", 60))
  IO.puts("🔍 DEBUG: Field processing analysis for action: #{params["action"]}")
  IO.puts(String.duplicate("=", 60))
  IO.inspect(client_fields, label: "📥 Client field specification")
  IO.inspect({select, load}, label: "🌳 Full field parser output (select, load)")
  IO.inspect(ash_load, label: "🔧 Filtered load for Ash (calculations only)")
  IO.inspect(combined_ash_load, label: "📋 Final combined_ash_load sent to Ash")
  IO.puts(String.duplicate("=", 60) <> "\n")
  
  # ... query execution ...
  
  # 🔍 DEBUG: Raw action result analysis
  |> tap(fn result ->
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("🔍 DEBUG: Raw Ash action result")
    IO.puts(String.duplicate("=", 60))
    case result do
      {:ok, data} ->
        IO.inspect(data, label: "✅ Raw action success data", limit: :infinity)
      {:error, error} ->
        IO.inspect(error, label: "❌ Raw action error")
    end
    IO.puts(String.duplicate("=", 60) <> "\n")
  end)
end
```

**CLEANUP**: Comment out debug outputs after issue is resolved:
```elixir
# DEBUG: Uncomment these lines to debug field processing issues
# IO.inspect({select, load}, label: "🌳 Full field parser output")
# IO.inspect(ash_load, label: "🔧 Filtered load for Ash")
```

### Pattern: Comprehensive Integration Testing

**When to Use**: After implementing new field processing features.

**WORKFLOW**:

1. **Create Comprehensive Test Suite**:
```elixir
# test/ash_typescript/rpc_embedded_calculations_test.exs
describe "RPC Embedded Resource Calculations" do
  test "embedded resource with simple calculation" do
    # Test basic calculation loading
  end
  
  test "embedded resource with multiple calculations" do
    # Test multiple calculation loading
  end
  
  test "embedded resource with only calculations (no attributes)" do
    # Test calculation-only requests
  end
  
  test "mixed embedded attributes and calculations" do
    # Test combination requests
  end
end
```

2. **Run Progressive Testing**:
```bash
# Test specific functionality
mix test test/ash_typescript/rpc_embedded_calculations_test.exs --trace

# Test integration with existing system
mix test test/ash_typescript/rpc_integration_test.exs

# Test complete system
mix test test/ash_typescript/rpc_integration_test.exs test/ash_typescript/rpc_embedded_calculations_test.exs
```

3. **Validate TypeScript Generation**:
```bash
# Ensure TypeScript types are still valid
mix test.codegen
cd test/ts && npm run compileGenerated
```

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
   # Run tests to ensure everything works (ALWAYS use test environment)
   mix test
   
   # Generate current TypeScript types
   mix test.codegen
   
   # Validate TypeScript compilation
   cd test/ts && npm run compileGenerated
   ```

3. **Explore the test domain**:

## TDD Workflow for Complex Features

### Test-Driven Development Pattern

**Pattern**: Create comprehensive test cases first, then implement support.

**Why This Works**:
- Creates concrete debugging targets
- Reveals exact failure points immediately  
- Provides measurable progress indicators
- Prevents over-engineering

**Steps**:
1. Create comprehensive test resource with ALL possible features
2. Create supporting modules (calculations, formatters, etc.)
3. Integrate with existing resources
4. Create targeted test suite showing gaps
5. Run tests to see specific failures
6. Implement features to make tests pass

**Success Criteria**: All tests pass and TypeScript compilation succeeds.

**See `docs/ai-embedded-resources.md` for detailed embedded resource implementation example.**

3. **Explore the test domain**:
   ```bash
   # See the comprehensive test setup
   cat test/support/domain.ex
   cat test/support/resources/todo.ex
   ```

## Debugging Workflows (Critical)

### Debug Workflow: Test Module Approach ✅ PROVEN EFFECTIVE

**When to Use**: 
- Resource recognition issues
- Type detection problems  
- Compilation failures
- Function visibility issues
- Environment context problems

**Why This Works**:
- Isolates the problem from complex domain setup
- Provides immediate feedback 
- Tests exact scenarios in controlled environment
- Eliminates external dependencies

#### Step 1: Create Minimal Debug Test

```bash
# Create test/debug_issue_test.exs
```

```elixir
defmodule DebugIssueTest do
  use ExUnit.Case

  # Minimal resource for testing specific issue
  defmodule TestResource do
    use Ash.Resource, domain: nil  # or data_layer: :embedded for embedded resources
    
    attributes do
      uuid_primary_key :id  # ALWAYS include for proper compilation
      attribute :test_field, :string, public?: true
      # Add specific problematic attribute here
    end
    
    actions do
      defaults [:create, :read, :update, :destroy]
    end
  end

  test "debug specific issue" do
    IO.puts "\n=== Debug Output ==="
    
    # Add specific debugging checks here
    IO.puts "Resource recognition: #{Ash.Resource.Info.resource?(TestResource)}"
    IO.puts "Data layer: #{inspect(Ash.Resource.Info.data_layer(TestResource))}"
    
    # Test the problematic function directly
    # IO.puts "Function result: #{MyModule.problematic_function(TestResource)}"
    
    assert true  # Just to make test pass while debugging
  end
end
```

#### Step 2: Run Debug Test

```bash
mix test test/debug_issue_test.exs
```

#### Step 3: Iterate Based on Output

- Add more debugging statements
- Test different variations
- Compare with working examples
- Test environment dependencies

#### Step 4: Clean Up

```bash
rm test/debug_issue_test.exs  # Remove when issue is resolved
```

### Environment Debugging Workflow

**Problem**: Functions work in some contexts but fail in others (especially resource recognition)

**Solution**: Always verify environment context

```bash
# ❌ WRONG - May use wrong environment
iex -S mix
mix run -e 'test code'

# ✅ CORRECT - Explicit test environment  
MIX_ENV=test iex -S mix
MIX_ENV=test mix run -e 'test code'
MIX_ENV=test mix test
```

**Test Environment Recognition**:
```bash
# Quick test to verify resources are loaded
MIX_ENV=test mix run -e 'IO.puts Ash.Resource.Info.resource?(AshTypescript.Test.Todo)'
# Should output: true
```

### Function Visibility Debugging Workflow

**Problem**: Function works in manual testing but fails in pattern matching

**Symptoms**: `UndefinedFunctionError` in contexts where function should be accessible

**Debugging Steps**:

1. **Test function accessibility**:
   ```bash
   MIX_ENV=test mix run -e 'IO.puts MyModule.function_name(test_arg)'
   ```

2. **Check function definition**:
   ```elixir
   # ❌ Private function - not accessible everywhere
   defp function_name(arg), do: ...
   
   # ✅ Public function - accessible in all contexts  
   def function_name(arg), do: ...
   ```

3. **Test in pattern matching context**:
   ```elixir
   # Create test that uses function in pattern matching
   def test_pattern_matching(%{type: type}) do
     cond do
       function_name(type) -> "works"
       true -> "fails"
     end
   end
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
           "args" => %{"your_arg" => "value"},
           "fields" => ["id", "other_field"],
           "calculations" => %{
             "your_calc" => %{
               "args" => %{"your_arg" => "nested"},
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
         args: { arg: "value" },
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