# Embedded Resources Issues

## Overview

This guide covers troubleshooting problems specific to embedded resources in AshTypescript, including resource discovery, type generation, and compilation issues.

## Embedded Resources Issues (Critical)

### Problem: Unknown Type Error for Embedded Resources

**Status**: ✅ **RESOLVED** - Embedded resource discovery implemented.

**Symptoms**:
```bash
mix ash_typescript.codegen
# Error: RuntimeError: Unknown type: Elixir.MyApp.EmbeddedResource
```

**Previous Failure Location**: `lib/ash_typescript/codegen.ex:108` in `generate_ash_type_alias/1`

**Root Cause (Discovered)**: 
1. Embedded resources not discovered during domain traversal
2. Missing type handling for direct embedded resource modules
3. Function visibility issues in pattern matching

**CRITICAL Discovery**: Embedded resources use `Ash.DataLayer.Simple`, NOT `Ash.DataLayer.Embedded`

**Diagnosis Steps (Updated)**:

**Write a proper test to investigate the issue:**

```elixir
# test/debug_embedded_recognition_test.exs
defmodule DebugEmbeddedRecognitionTest do
  use ExUnit.Case
  
  # Test the actual problematic embedded resource
  test "debug embedded resource recognition" do
    # 1. Verify resource compiles and is recognized
    assert Ash.Resource.Info.resource?(MyApp.EmbeddedResource) == true
    
    # 2. Check data layer (CRITICAL: should be Ash.DataLayer.Simple)
    data_layer = Ash.Resource.Info.data_layer(MyApp.EmbeddedResource)
    assert data_layer == Ash.DataLayer.Simple  # NOT Ash.DataLayer.Embedded!
    
    # 3. Test embedded resource detection function
    assert AshTypescript.Codegen.is_embedded_resource?(MyApp.EmbeddedResource) == true
    
    # 4. Check parent resource references
    attr = Ash.Resource.Info.attribute(MyApp.ParentResource, :embedded_field)
    assert attr.type == MyApp.EmbeddedResource
    assert attr.constraints[:on_update] == :update_on_match
  end
end
```

**Run the test:**
```bash
mix test test/debug_embedded_recognition_test.exs
```

**Solution (Implemented)**: 
1. ✅ Embedded resource discovery via attribute scanning
2. ✅ Direct module type handling in `get_ts_type/2`
3. ✅ Public `is_embedded_resource?/1` function
4. ✅ Schema generation integration

### Problem: "Embedded resources should not be listed in the domain"

**Symptoms**:
```bash
mix compile
# Error: Embedded resources should not be listed in the domain. Please remove [MyApp.EmbeddedResource].
```

**Root Cause**: Ash explicitly prevents embedded resources from being added to domain `resources` block.

**Solution**: Remove embedded resources from domain - they're discovered automatically through attribute scanning.

```elixir
# ❌ WRONG - Causes compilation error
defmodule MyApp.Domain do
  resources do
    resource MyApp.EmbeddedResource  # Ash will error
  end
end

# ✅ CORRECT - Embedded resources discovered via parent resource attributes
defmodule MyApp.Domain do
  resources do
    resource MyApp.ParentResource   # Contains embedded attributes
  end
end
```

### Debugging Pattern: Test Module Approach

**When to Use**: Resource recognition issues, type detection problems, or compilation failures.

**Create Debug Test**:
```elixir
# test/debug_embedded_test.exs
defmodule DebugEmbeddedTest do
  use ExUnit.Case

  # Minimal embedded resource for testing
  defmodule TestEmbedded do
    use Ash.Resource, data_layer: :embedded
    
    attributes do
      uuid_primary_key :id  # REQUIRED for compilation
      attribute :name, :string, public?: true
    end
    
    actions do
      defaults [:create, :read, :update, :destroy]
    end
  end

  # Minimal parent resource
  defmodule TestParent do
    use Ash.Resource, domain: nil
    
    attributes do
      uuid_primary_key :id
      attribute :embedded_field, TestEmbedded, public?: true
    end
    
    actions do
      defaults [:create, :read, :update, :destroy]
    end
  end

  test "debug embedded resource detection" do
    IO.puts "\n=== Embedded Resource Debug ==="
    
    # Test basic resource recognition
    IO.puts "TestEmbedded is resource?: #{Ash.Resource.Info.resource?(TestEmbedded)}"
    IO.puts "TestEmbedded data_layer: #{inspect(Ash.Resource.Info.data_layer(TestEmbedded))}"
    
    # Test attribute structure
    embedded_attr = Ash.Resource.Info.attribute(TestParent, :embedded_field)
    IO.puts "embedded_field type: #{inspect(embedded_attr.type)}"
    IO.puts "embedded_field constraints: #{inspect(embedded_attr.constraints)}"
    
    # Test detection function
    IO.puts "is_embedded_resource?(TestEmbedded): #{AshTypescript.Codegen.is_embedded_resource?(TestEmbedded)}"
    
    # Test discovery function
    discovered = AshTypescript.Codegen.find_embedded_resources([TestParent])
    IO.puts "Discovered embedded resources: #{inspect(discovered)}"
    
    assert true
  end
end
```

**Run with**: `mix test test/debug_embedded_test.exs`

**Expected Output**:
```
=== Embedded Resource Debug ===
TestEmbedded is resource?: true
TestEmbedded data_layer: Ash.DataLayer.Simple
embedded_field type: DebugEmbeddedTest.TestEmbedded
embedded_field constraints: [on_update: :update_on_match]
is_embedded_resource?(TestEmbedded): true
Discovered embedded resources: [DebugEmbeddedTest.TestEmbedded]
```

### Problem: Function Visibility in Pattern Matching

**Symptoms**: 
- Function works in manual testing but fails during type generation
- `UndefinedFunctionError` during pattern matching

**Root Cause**: Private functions cannot be accessed in all contexts.

**Solution**: Make functions used in pattern matching public:

```elixir
# ❌ WRONG - Private function fails in pattern matching contexts
defp is_embedded_resource?(module), do: ...

# ✅ CORRECT - Public function works everywhere
def is_embedded_resource?(module), do: ...
```

### Problem: Environment Context Issues

**Symptoms**:
- `Ash.Resource.Info.resource?/1` returns `false` for valid resources
- Resources not found during discovery

**Root Cause**: Domain resources not loaded in current environment.

**Solution**: Always write proper tests for debugging:

```bash
# ❌ WRONG - Interactive debugging, hard to reproduce
# Using one-off interactive commands

# ✅ CORRECT - Test-based debugging, reproducible
mix test                                    # Test environment loads all resources
mix test test/debug_specific_issue_test.exs # Test specific functionality
```

**Write proper debug tests following existing patterns:**

```elixir
# Follow patterns from test/ash_typescript/ directory
# Example: test/ash_typescript/codegen_test.exs
# Example: test/ash_typescript/embedded_resources_test.exs
```

**Implementation Status**: ✅ **COMPLETED**
- Added embedded resource discovery via attribute scanning
- Updated `get_ts_type/2` to handle embedded resource modules
- Integrated embedded resources into schema generation pipeline

### Problem: Embedded Resource Compilation Errors

**Symptoms**:
```elixir
# Compilation error in embedded resource definition
** (Spark.Error.DslError) validations -> validate:
  invalid list in :where option
```

**Common Causes & Solutions**:

1. **Calculation Syntax Error**:
   ```elixir
   # WRONG - public? outside do block
   calculate :name, :type, Module, public?: true do
     argument :arg, :type
   end
   
   # CORRECT - public? inside do block
   calculate :name, :type, Module do
     public? true
     argument :arg, :type
   end
   ```

2. **Complex Validation Where Clauses**:
   ```elixir
   # WRONG - complex where clauses fail
   validate attribute_does_not_equal(:status, :archived), 
     where: [is_urgent: true]
   
   # CORRECT - use simple validations only
   validate present(:category), message: "Category is required"
   ```

3. **Identity Configuration Error**:
   ```elixir
   # WRONG - eager_check? requires domain
   identity :unique_ref, [:field], eager_check?: true
   
   # CORRECT - no eager_check in embedded resources
   identity :unique_ref, [:field]
   ```

4. **Policies Not Supported**:
   ```elixir
   # WRONG - policies not supported
   policies do
     policy always() do
       authorize_if always()
     end
   end  # Error: undefined function policies/1
   
   # CORRECT - remove policies block entirely
   ```

**Reference**: See `docs/ai-embedded-resources.md` for complete embedded resource patterns.

### Problem: Parent Resource Update Atomicity

**Symptoms**:
```bash
# Warning during compilation
[MyApp.Todo]
actions -> update:
  `MyApp.Todo.update` cannot be done atomically, because the attributes `metadata` cannot be updated atomically
```

**Solution**:
```elixir
# In parent resource
actions do
  update :update do
    require_atomic? false  # Embedded resources can't be updated atomically
  end
end
```

## Prevention Strategies

### Best Practices

1. **Never add embedded resources to domain** - They're discovered automatically
2. **Use test-based debugging** - Create reproducible tests instead of one-off commands
3. **Make detection functions public** - Private functions fail in pattern matching contexts
4. **Keep embedded resource definitions simple** - Avoid complex validations and policies
5. **Set require_atomic? false** - For parent resource updates with embedded fields

### Validation Workflow

```bash
# Standard validation after embedded resource changes
mix test.codegen                            # Generate types with embedded resources
cd test/ts && npm run compileGenerated      # Validate TypeScript compilation
mix test test/ash_typescript/embedded_resources_test.exs  # Test embedded resource functionality
```

## Critical Success Factors

1. **Automatic Discovery**: Embedded resources are found via attribute scanning, not domain listing
2. **Test Environment**: Always use test environment for embedded resource debugging
3. **Simple Definitions**: Keep embedded resource definitions minimal and avoid complex features
4. **Public Functions**: Make resource detection functions public for pattern matching
5. **Atomicity Awareness**: Parent resources with embedded fields need require_atomic? false

---

**See Also**:
- [Environment Issues](environment-issues.md) - For setup and environment problems
- [Type Generation Issues](type-generation-issues.md) - For TypeScript generation problems
- [Quick Reference](quick-reference.md) - For rapid problem identification