# Development Workflows

## Essential Commands

### Code Generation
```bash
# Generate TypeScript types and clients
mix ash_typescript.codegen

# With custom output file  
mix ash_typescript.codegen --output "frontend/types.ts"

# With custom endpoints
mix ash_typescript.codegen --run-endpoint "/api/rpc" --validate-endpoint "/api/validate"

# Dry run (preview changes)
mix ash_typescript.codegen --dry-run

# Check if generated files are up-to-date
mix ash_typescript.codegen --check
```

### Testing
```bash
# Run all tests
mix test

# Run codegen as part of test suite
mix test.codegen

# Verify TypeScript compilation
cd test/ts && npm run compile

# Run specific test files
mix test test/ts_codegen_test.exs
mix test test/rpc_test.exs
```

### Quality Checks
```bash
# Code formatting
mix format

# Linting  
mix credo --strict

# Type checking
mix dialyzer

# Security scanning
mix sobelow

# Documentation generation
mix docs
```

## Development Setup

### Dependencies
- Elixir ~> 1.15
- Ash ~> 3.5
- AshPhoenix ~> 2.0 (for RPC endpoints)
- Node.js & TypeScript (for verification)

### Project Structure
```
lib/
├── ash_typescript.ex           # Main module
├── ash_typescript/
│   ├── codegen.ex             # Core type generation
│   ├── rpc.ex                 # RPC DSL extension
│   ├── rpc/codegen.ex         # RPC client generation  
│   ├── filter.ex              # Filter handling
│   └── helpers.ex             # Utility functions
└── mix/tasks/
    ├── ash_typescript.codegen.ex  # Main CLI task
    └── ash_typescript.install.ex # Installation helpers
```

## Common Development Tasks

### Adding New Type Mappings
1. Update `AshTypescript.Codegen.ash_type_to_typescript/1`
2. Add test cases in `test/ts_codegen_test.exs`  
3. Verify TypeScript compilation

### Extending RPC DSL
1. Add new DSL entities in `AshTypescript.Rpc`
2. Update code generation in `AshTypescript.Rpc.Codegen`
3. Add integration tests

### Debugging Generated Output
```bash
# Generate with verbose output
mix ash_typescript.codegen --dry-run

# Check specific test output
cat test/ts/generated.ts

# Manual TypeScript compilation
cd test/ts && npx tsc generated.ts --noEmit
```

## Configuration Options

### Application Config
```elixir
# config/config.exs
config :ash_typescript,
  output_file: "assets/js/ash_rpc.ts",
  run_endpoint: "/rpc/run", 
  validate_endpoint: "/rpc/validate"
```

### Mix Aliases
```elixir
# mix.exs
aliases: [
  "test.codegen": "ash_typescript.codegen",
  docs: ["spark.cheat_sheets", "docs", "spark.replace_doc_links"]
]
```

## Troubleshooting

### Common Issues
- **TypeScript compilation errors**: Check generated type mapping
- **Missing RPC actions**: Verify domain RPC configuration
- **Outdated types**: Run `mix ash_typescript.codegen` after resource changes
- **Test failures**: Ensure test resources match expected output

### Debug Mode
```bash
# Enable Elixir debugging
iex -S mix

# Check resource introspection
iex> Ash.Resource.Info.public_attributes(MyResource)
iex> AshTypescript.Codegen.generate_typescript_types(:my_app, [])
```

## Release Process

### Version Management
- Update version in `mix.exs`
- Run `mix docs` to update documentation
- Ensure all tests pass
- Update `CHANGELOG.md`

### Publication
```bash
# Run quality checks
mix format && mix credo && mix test

# Build documentation
mix docs

# Publish (if authorized)
mix hex.publish
```

## Architectural Decisions

### Nested Calculations Implementation

The nested calculations feature was implemented to support loading calculations on the results of other calculations when those calculations return Ash resources. This section documents key architectural decisions and lessons learned.

#### Design Approach: Recursive Simplification

**Decision**: Use direct recursion in the main parsing function instead of complex multi-phase processing.

**Rationale**: 
- Initial design involved 8 complex phases with multiple helper functions
- Simplified approach uses uniform processing regardless of calculation component combinations
- True recursion naturally handles arbitrary nesting depth
- Significantly reduced code complexity (90% less code than original plan)

**Implementation**:
```elixir
defp parse_calculations_with_fields(calculations, resource) do
  # Extract all components uniformly
  args = Map.get(calc_spec, "calcArgs", %{}) |> atomize_calc_args()
  fields = Map.get(calc_spec, "fields", []) |> parse_field_names_and_load()
  nested_calcs = Map.get(calc_spec, "calculations", %{})
  
  # Direct recursive call for nested calculations
  {nested_load, nested_specs} = 
    if map_size(nested_calcs) > 0 and is_resource_calculation?(calc_definition) do
      parse_calculations_with_fields(nested_calcs, target_resource)
    else
      {[], %{}}
    end
end
```

#### Resource Detection Pattern

**Decision**: Detect Ash resources via `Ash.Type.Struct` with `instance_of` constraints.

**Challenge**: Calculations returning Ash resources use `Ash.Type.Struct` as the type, not direct module references.

**Solution**:
```elixir
defp is_resource_calculation?(calc_definition) do
  case calc_definition.type do
    Ash.Type.Struct ->
      case Keyword.get(calc_definition.constraints || [], :instance_of) do
        module when is_atom(module) -> Ash.Resource.Info.resource?(module)
        _ -> false
      end
    _ -> false
  end
end
```

**Lesson Learned**: Always check Ash's actual data structures rather than assuming format patterns.

#### Ash Load Statement Format

**Discovery**: Ash requires specific tuple format for nested calculations with arguments.

**Correct Format**: `{:calculation, {args_map, [nested_loads]}}`
**Incorrect Format**: `{:calculation, %{args: args_map, load: [nested_loads]}}`

**Implementation**:
```elixir
defp build_ash_load_entry(calc_atom, args, fields, nested_load) do
  combined_load = fields ++ nested_load
  
  case {map_size(args), length(combined_load)} do
    {0, 0} -> calc_atom
    {0, _} -> {calc_atom, [fields: combined_load]}
    {_, 0} -> {calc_atom, args}
    {_, _} -> {calc_atom, {args, combined_load}}  # Critical tuple format
  end
end
```

**Lesson Learned**: Thoroughly validate generated Ash queries with Ash documentation and testing.

#### Field Specs Data Structure

**Decision**: Use simple tuple format `{fields, nested_specs}` instead of complex maps.

**Rationale**:
- Easier to pattern match and process
- Maintains hierarchical structure naturally  
- Backward compatible with existing list format
- Reduces complexity in extraction logic

**Trade-offs Considered**:
- Complex map: `%{fields: [...], nested_calculations: %{...}, has_args: boolean}`
- Simple tuple: `{fields, nested_specs}` (chosen)
- List format: `[field_list]` (legacy support maintained)

#### Ash Framework Integration

**Implementation**: The nested calculations feature successfully integrates with Ash's calculation loading system.

**Impact**: 
- Level 1: Regular calculations work perfectly
- Level 2: Nested calculations work correctly  
- Level 3+: RPC system generates correct load statements for any depth

**Implementation Response**:
- Generate correct load statements for any depth
- Ensure proper field selection at all nesting levels
- Handle complex nested data structures gracefully

**Lesson Learned**: Test integration boundaries thoroughly, especially with complex nested operations.

#### Error Handling Strategy

**Decision**: Fail fast for configuration errors, graceful degradation for runtime issues.

**Configuration Errors** (fail fast):
- Invalid resource detection patterns
- Malformed calculation arguments
- Missing required constraints

**Runtime Issues** (graceful degradation):
- Ash loading limitations
- Field selection on non-loaded calculations
- Circular reference detection

#### Performance Considerations

**Optimization Decisions**:
1. **Resource Detection Caching**: Resource type checking happens per calculation definition, not per instance
2. **Single-Pass Parsing**: Extract all calculation components in one iteration
3. **Recursive Field Application**: Apply field selection during extraction, not pre-processing

**Memory Usage**:
- Store minimal field specs for post-processing
- Use references instead of duplicating calculation definitions
- Clean up intermediate parsing structures

#### Testing Strategy

**Approach**: Comprehensive test coverage with incremental complexity.

**Test Levels**:
1. **Unit Tests**: Individual helper functions (resource detection, load building)
2. **Integration Tests**: Full RPC request/response cycles
3. **Edge Case Tests**: Boundary conditions and error scenarios
4. **Backward Compatibility Tests**: Ensure existing functionality preserved

**Key Test Insights**:
- Debug output was crucial for understanding Ash load statement generation
- Direct Ash query testing helped isolate RPC vs Ash issues
- Incremental test development caught architectural issues early

#### Critical Bug Fix: Nested Calculation Value Extraction

**Issue**: Nested calculation values were not being extracted properly from Ash query results when returning RPC responses to clients.

**Root Cause**: The `extract_fields_from_map` function only included simple fields (`:id`, `:title`) in recursive extraction calls, but omitted nested calculation field names (`:self`).

**Solution**: Modified extraction logic to include both simple fields AND nested calculation fields:
```elixir
{calc_fields, nested_specs} ->
  # Include both simple fields and nested calculation fields
  nested_calc_fields = Map.keys(nested_specs)
  all_fields = calc_fields ++ nested_calc_fields
  filtered_value = extract_return_value(value, all_fields, nested_specs)
```

**Lesson Learned**: When implementing recursive data extraction with field selection, ensure all relevant field types (attributes, relationships, calculations) are included in recursive calls. Test with debug output to verify complete data flow.

#### Testing Best Practices for Field Selection

**Issue**: Initial tests used many `refute` statements to verify field exclusion, making tests verbose and hard to maintain.

**Better Approach**: Use exact field assertions with count verification:
```elixir
# Verify exact field match
expected_fields = ["id", "title", "self"]
assert Map.keys(data) |> Enum.sort() == expected_fields |> Enum.sort()

# Ensure no extra fields
assert map_size(data) == 3
```

**Benefits**:
- More maintainable than multiple `refute` statements  
- Clearer intent - exactly what fields should be present
- Catches both missing fields AND unexpected extra fields
- Single assertion failure provides complete picture

**Testing Strategy for Complex Field Selection**:
1. **Test multiple field combinations** - different sets of requested fields
2. **Verify all nesting levels** - top-level, calculation, nested calculation
3. **Use `map_size()` assertions** - ensure no extra fields leak through
4. **Sort comparisons** - avoid test flakiness from field order

#### Future Considerations

**Scalability**:
- Current recursive approach handles reasonable nesting depths efficiently
- Deep nesting (5+ levels) may hit stack limits, but Ash limits prevent this

**Extensibility**:
- Pattern established supports future calculation features
- Resource detection pattern can extend to other types
- Field selection framework supports additional filtering options

**Maintainability**:
- Simplified recursive approach is easier to debug and extend
- Clear separation between parsing and extraction phases
- Comprehensive documentation prevents future confusion
- Improved testing patterns make verification more reliable

## Integration with Phoenix

### Router Setup
```elixir
scope "/rpc" do
  pipe_through :api
  post "/run", MyAppWeb.RpcController, :run  
  post "/validate", MyAppWeb.RpcController, :validate
end
```

### Frontend Integration
```typescript
// Import generated types and client
import { AshRpc, TodoSchema, TodoCreateInput } from './ash_rpc';

// Use typed client
const client = new AshRpc();
const todo: TodoSchema = await client.createTodo({
  title: "New task",
  description: "Task details"
});
```