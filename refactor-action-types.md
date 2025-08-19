# RPC Action Types Refactoring Plan

## Executive Summary

This document outlines the plan to refactor the TypeScript code generation for RPC actions to provide superior type safety and developer experience. The new pattern separates input types, uses direct field generics, and provides more precise type inference.

## Current vs Desired Pattern Analysis

### Current Pattern Issues
1. **Bundled Config Type**: All parameters (input, fields, headers, etc.) are bundled into a single Config type, making it harder to reuse and reason about
2. **Generic on Config**: The generic parameter is on the entire Config type, requiring type access like `Config["fields"]` 
3. **Poor Type Inference**: TypeScript has difficulty inferring the specific field types due to the indirect Config access
4. **Reusability**: Input types are buried inside Config types, making them hard to reuse in other contexts

### Desired Pattern Benefits
1. **Separated Concerns**: Input types are separate and reusable (e.g., `CreateTodoInput`)
2. **Direct Generics**: Generic parameter is directly on the fields type for better inference
3. **Better Type Safety**: TypeScript can infer exact result types based on field selection
4. **Cleaner API**: More intuitive function signatures with inline config objects

## Technical Implementation Strategy

### Phase 1: New Generation Functions (Low Risk)
Instead of modifying existing functions, create parallel functions to generate the new pattern:

- `generate_input_type/3` - Generate separate input types (e.g., `CreateTodoInput`)
- `generate_new_result_type/3` - Generate new result inference types with direct field generics
- `generate_new_payload_builder/4` - Generate payload builders with inline config objects  
- `generate_new_rpc_execution_function/4` - Generate new function signatures

### Phase 2: Configuration Flag (Safe Transition)
Add a configuration option to choose between old and new patterns:
```elixir
config :ash_typescript, :use_new_action_pattern, true
```

### Phase 3: Migration and Testing
Extensive testing with both patterns to ensure compatibility.

### Phase 4: Deprecation
Mark old pattern as deprecated and eventually remove.

## Detailed Implementation Plan

### Step 1: Create New Input Type Generator
**File**: `lib/ash_typescript/rpc/codegen.ex`
**Function**: `generate_input_type/3`

**Rationale**: Extract input type generation logic from the existing `generate_config_type/3` function to create standalone input types.

**Implementation**:
```elixir
defp generate_input_type(resource, action, rpc_action_name) do
  input_type_name = "#{snake_to_pascal_case(rpc_action_name)}Input"
  
  # Extract input field logic from existing generate_config_type/3
  # Generate only the input portion as a separate type
  
  case action.type do
    :create -> generate_create_input_fields(resource, action)
    :update -> generate_update_input_fields(resource, action) 
    :read -> generate_read_input_fields(action)
    # etc.
  end
end
```

### Step 2: Create New Result Type Generator  
**File**: `lib/ash_typescript/rpc/codegen.ex`
**Function**: `generate_new_result_type/3`

**Changes**:
- Generic parameter directly on Fields type: `<Fields extends UnifiedFieldSelection<ResourceSchema>[]>`
- Use `Fields` directly instead of `Config["fields"]`

**Example Output**:
```typescript
type InferCreateTodoResult<
  Fields extends UnifiedFieldSelection<TodoResourceSchema>[],
> = InferResult<TodoResourceSchema, Fields>;
```

### Step 3: Create New Payload Builder Generator
**File**: `lib/ash_typescript/rpc/codegen.ex` 
**Function**: `generate_new_payload_builder/4`

**Changes**:
- Accept inline config object instead of named Config type
- Parameter structure: `{input: InputType, fields: Fields, headers?: Record<string, string>}`

**Example Output**:
```typescript
export function buildCreateTodoPayload(config: {
  input: CreateTodoInput;
  fields: UnifiedFieldSelection<TodoResourceSchema>[];
}): Record<string, any>
```

### Step 4: Create New RPC Function Generator
**File**: `lib/ash_typescript/rpc/codegen.ex`
**Function**: `generate_new_rpc_execution_function/4`

**Changes**:
- Generic parameter directly on Fields: `<Fields extends UnifiedFieldSelection<ResourceSchema>[]>`
- Inline config object parameter
- Direct field type inference in return type

**Example Output**:
```typescript
export async function createTodo<
  Fields extends UnifiedFieldSelection<TodoResourceSchema>[],
>(config: {
  input: CreateTodoInput;
  fields: Fields;
  headers?: Record<string, string>;
}): Promise<CreateTodoResult<Fields>>
```

### Step 5: Create New Main Generator Function
**File**: `lib/ash_typescript/rpc/codegen.ex`
**Function**: `generate_new_rpc_function/7`

**Purpose**: Orchestrate the new generators similar to how `generate_rpc_function/5` works currently.

### Step 6: Add Configuration Flag Support
**File**: `lib/ash_typescript/rpc/codegen.ex`
**Function**: `generate_rpc_functions/4`

**Implementation**:
```elixir
defp generate_rpc_functions(resources_and_actions, endpoint_process, endpoint_validate, otp_app, _resources) do
  use_new_pattern = Application.get_env(:ash_typescript, :use_new_action_pattern, false)
  
  generator_function = if use_new_pattern do
    &generate_new_rpc_function/7
  else
    &generate_rpc_function/5
  end
  
  # Use selected generator...
end
```

### Step 7: Handle Special Cases

#### Primary Key Handling (Update/Destroy Actions)
Current pattern embeds `primaryKey` in Config. New pattern needs to handle this in the inline config object.

**Solution**: Include `primaryKey` field in the config object for update/destroy actions:
```typescript
export async function updateTodo<Fields extends UnifiedFieldSelection<TodoResourceSchema>[]>(config: {
  primaryKey: UUID;
  input: UpdateTodoInput;
  fields: Fields;
  headers?: Record<string, string>;
}): Promise<UpdateTodoResult<Fields>>
```

#### Pagination Support
Current pattern includes `page` field in Config. New pattern needs to maintain this.

**Solution**: Include pagination fields in the config object for read actions with pagination:
```typescript
export async function listTodos<Fields extends UnifiedFieldSelection<TodoResourceSchema>[]>(config: {
  input?: ListTodosInput;
  fields: Fields;
  filter?: TodoFilterInput;
  sort?: string;
  page?: { limit: number; offset?: number; };
  headers?: Record<string, string>;
}): Promise<ListTodosResult<Fields>>
```

#### Multi-tenant Support
Current pattern includes `tenant` field in Config when needed.

**Solution**: Include tenant field in config object when resource requires it:
```typescript
export async function createTodo<Fields extends UnifiedFieldSelection<TodoResourceSchema>[]>(config: {
  tenant: string;
  input: CreateTodoInput;
  fields: Fields;
  headers?: Record<string, string>;
}): Promise<CreateTodoResult<Fields>>
```

## Testing Strategy

### Phase 1: Parallel Generation Testing
1. **Generate Both Patterns**: Temporarily generate both old and new patterns side by side
2. **Type Compilation Tests**: Ensure both patterns compile successfully
3. **Manual Testing**: Test key scenarios with both patterns

### Phase 2: Integration Testing  
1. **Test All Action Types**: Create, Read, Update, Delete, Generic actions
2. **Test Special Features**: Pagination, multi-tenancy, primary keys
3. **Test Edge Cases**: Actions with no input, optional fields, complex nested types

### Phase 3: TypeScript Integration Tests
1. **Update `test/ts/shouldPass/`**: Add tests for new pattern usage
2. **Update `test/ts/shouldFail/`**: Add tests that should fail with new pattern 
3. **Compilation Tests**: Ensure `npm run compileGenerated` passes

### Phase 4: Elixir Test Updates
1. **RPC Pipeline Tests**: Ensure backend processing unchanged
2. **Integration Tests**: Test full request/response cycle
3. **Error Handling**: Verify error responses work correctly

## Risk Assessment and Mitigation

### High Risk: Breaking Changes
**Risk**: New pattern breaks existing TypeScript code using generated types.
**Mitigation**: 
- Use configuration flag for gradual migration
- Maintain backward compatibility until next major version
- Provide migration guide and tooling

### Medium Risk: Complex Type Inference
**Risk**: TypeScript's type inference might not work as expected with new pattern.
**Mitigation**:
- Extensive testing with complex field selections
- Fallback to explicit type annotations if needed
- Benchmark compilation times

### Medium Risk: Code Generation Complexity
**Risk**: Managing two patterns increases code complexity.
**Mitigation**:
- Clear separation of old and new generator functions
- Comprehensive tests for both patterns
- Plan deprecation timeline

### Low Risk: Performance Impact
**Risk**: New pattern might affect TypeScript compilation performance.
**Mitigation**:
- Monitor compilation times during testing
- Optimize type definitions if needed

## Migration Path for Users

### Immediate (v1.x)
1. Add configuration flag to enable new pattern
2. Generate both patterns for comparison
3. Update documentation with examples

### Short Term (v1.x+1)
1. Default to new pattern for new projects
2. Provide migration tooling/scripts
3. Mark old pattern as deprecated

### Long Term (v2.0)
1. Remove old pattern entirely
2. Breaking change in major version
3. Clean up generation code

## Implementation Checklist

### Core Implementation
- [ ] Create `generate_input_type/3` function
- [ ] Create `generate_new_result_type/3` function  
- [ ] Create `generate_new_payload_builder/4` function
- [ ] Create `generate_new_rpc_execution_function/4` function
- [ ] Create `generate_new_rpc_function/7` orchestrator function
- [ ] Add configuration flag support

### Special Cases  
- [ ] Handle primary key fields for update/destroy actions
- [ ] Handle pagination for read actions
- [ ] Handle multi-tenant support
- [ ] Handle generic actions with field selection
- [ ] Handle actions with no input parameters

### Testing
- [ ] Create parallel generation test
- [ ] Update TypeScript compilation tests
- [ ] Add new pattern usage examples to `test/ts/shouldPass/`
- [ ] Add failure cases to `test/ts/shouldFail/`
- [ ] Test all action types (CRUD + generic)
- [ ] Test special features (pagination, tenancy)

### Documentation
- [ ] Update code generation documentation
- [ ] Create migration guide
- [ ] Update examples in README
- [ ] Document configuration options

### Quality Assurance
- [ ] Code review of all changes
- [ ] Performance testing
- [ ] Integration testing with real projects
- [ ] Backward compatibility verification

## Success Criteria

1. **Type Safety**: New pattern provides demonstrably better type inference
2. **Compatibility**: Old pattern continues to work unchanged  
3. **Performance**: No significant impact on TypeScript compilation times
4. **Usability**: Developer experience improved with cleaner APIs
5. **Testing**: All existing tests pass, new pattern thoroughly tested

## Timeline Estimate

- **Phase 1 (Core Implementation)**: 3-5 days
- **Phase 2 (Special Cases)**: 2-3 days  
- **Phase 3 (Testing)**: 2-3 days
- **Phase 4 (Documentation)**: 1-2 days
- **Total**: 8-13 days

## Conclusion

This refactoring will significantly improve the TypeScript developer experience while maintaining backward compatibility through a configuration flag approach. The separated input types and direct field generics will provide superior type safety and cleaner APIs.

The implementation plan prioritizes safety through parallel generation and extensive testing, ensuring a smooth transition for existing users while providing immediate benefits for new users.