# Unified Field API: Type Inference and TypeScript Generation Refactoring Plan

## Executive Summary

The RPC actions have been successfully refactored to use a unified field API where calculations are embedded within the fields array, eliminating the separate `calculations` parameter. However, the TypeScript generation and type inference systems still generate code for the old dual-parameter API. This plan outlines the comprehensive refactoring needed to align the TypeScript generation with the new unified field format.

## Current State Analysis

### ✅ What's Working (Backend)
- **RPC Runtime**: Successfully processes unified field format in `lib/ash_typescript/rpc.ex`
- **Field Parser**: Handles complex calculations within field arrays via `lib/ash_typescript/rpc/field_parser.ex`
- **Result Processor**: Processes results with unified field specifications via `lib/ash_typescript/rpc/result_processor.ex`
- **Backwards Compatibility**: Completely removed (~300 lines of code) - clean architecture

### ❌ What's Broken (Frontend)
- **TypeScript Config Types**: Still generate separate `fields` and `calculations` parameters
- **Type Inference**: Still expects dual-parameter API for type inference
- **Generated Functions**: Still build payloads with separate `fields` and `calculations`
- **Test Patterns**: Test files still use old dual-parameter format

### Current API Mismatch

**Generated TypeScript (OLD)**:
```typescript
export type GetTodoConfig = {
  fields: FieldSelection<TodoResourceSchema>[];
  calculations?: Partial<TodoResourceSchema["complexCalculations"]>;
};
```

**Required TypeScript (NEW)**:
```typescript
export type GetTodoConfig = {
  fields: FieldSelection<TodoResourceSchema>[];
  // calculations parameter removed - embedded in fields
};
```

## Refactoring Plan

### Phase 1: TypeScript Config Type Generation Updates
**Files**: `lib/ash_typescript/rpc/codegen.ex`
**Priority**: High
**Estimated Effort**: 2-3 hours

#### Changes Needed:

1. **Remove calculations parameter from config types**:
   ```elixir
   # REMOVE from generate_config_type/4
   calculations_field = [
     "  #{formatted_calculations_name}?: Partial<#{resource_name}ResourceSchema[\"complexCalculations\"]>;"
   ]
   ```

2. **Update field selection to support unified format**:
   ```elixir
   # UPDATE field selection to handle calculations within fields
   fields_field = [
     "  #{formatted_fields_name}: UnifiedFieldSelection<#{resource_name}ResourceSchema>[];"
   ]
   ```

3. **Update payload builders**:
   ```elixir
   # REMOVE calculations handling from payload builders
   # All payload builders in generate_payload_builder/4 need to remove:
   if (config.#{formatted_calculations_name}) {
     payload.calculations = config.#{formatted_calculations_name};
   }
   ```

### Phase 2: Unified Field Selection Type System
**Files**: `lib/ash_typescript/rpc/codegen.ex`
**Priority**: High
**Estimated Effort**: 4-5 hours

#### New Type System Architecture:

1. **Create UnifiedFieldSelection type**:
   ```typescript
   type UnifiedFieldSelection<Resource extends ResourceBase> =
     | keyof Resource["fields"]
     | {
         [K in keyof Resource["relationships"]]?: UnifiedFieldSelection<
           Resource["relationships"][K] extends { __resource: infer R }
           ? R extends ResourceBase ? R : never : never
         >[];
       }
     | {
         [K in keyof Resource["complexCalculations"]]?: {
           calcArgs: Resource["complexCalculations"][K] extends { calcArgs: infer Args } ? Args : never;
           fields: UnifiedFieldSelection<
             Resource["complexCalculations"][K] extends { __returnType: infer ReturnType }
             ? ReturnType extends ResourceBase ? ReturnType : never : never
           >[];
           calculations?: {
             [NestedK in keyof Resource["complexCalculations"][K]]?: // recursive nesting
           };
         };
       };
   ```

2. **Update InferResourceResult type**:
   ```typescript
   type InferResourceResult<
     Resource extends ResourceBase,
     SelectedFields extends UnifiedFieldSelection<Resource>[]
   > = 
     InferPickedFields<Resource, ExtractStringFields<SelectedFields>> &
     InferRelationships<ExtractRelationshipObjects<SelectedFields>, Resource["relationships"]> &
     InferCalculations<ExtractCalculationObjects<SelectedFields>, Resource["__complexCalculationsInternal"]>;
   ```

3. **Create field extraction utilities**:
   ```typescript
   // Extract calculation objects from unified field selection
   type ExtractCalculationObjects<Fields> = Fields extends readonly (infer U)[]
     ? U extends Record<string, { calcArgs: any; fields: any }>
       ? U
       : never
     : never;
   ```

### Phase 3: Result Type Inference Updates
**Files**: `lib/ash_typescript/rpc/codegen.ex`
**Priority**: High
**Estimated Effort**: 3-4 hours

#### Changes Needed:

1. **Update generate_result_type/3**:
   ```elixir
   # CHANGE from:
   type Infer#{rpc_action_name_pascal}Result<Config extends #{rpc_action_name_pascal}Config> =
     InferResourceResult<#{resource_name}ResourceSchema, Config["fields"], Config["calculations"]>;
   
   # TO:
   type Infer#{rpc_action_name_pascal}Result<Config extends #{rpc_action_name_pascal}Config> =
     InferResourceResult<#{resource_name}ResourceSchema, Config["fields"]>;
   ```

2. **Update all result type references**:
   - Remove `Config["calculations"]` parameter from all `InferResourceResult` calls
   - Update function signatures to only use `Config["fields"]`

### Phase 4: RPC Function Generation Updates
**Files**: `lib/ash_typescript/rpc/codegen.ex`
**Priority**: High
**Estimated Effort**: 2-3 hours

#### Changes Needed:

1. **Update generate_rpc_execution_function/4**:
   ```elixir
   # REMOVE calculations parameter handling
   # Functions should only build payload with fields
   ```

2. **Update validation functions**:
   ```elixir
   # REMOVE calculations from validation function signatures
   # Only validate fields parameter
   ```

3. **Update function signatures**:
   ```typescript
   // CHANGE from:
   export async function getTodo(
     config: GetTodoConfig
   ): Promise<InferGetTodoResult<GetTodoConfig>>;
   
   // TO: (no change needed - same signature, but config type is different)
   export async function getTodo(
     config: GetTodoConfig
   ): Promise<InferGetTodoResult<GetTodoConfig>>;
   ```

### Phase 5: Test Pattern Migration
**Files**: `test/ts/shouldPass.ts`, `test/ts/shouldFail.ts`
**Priority**: Medium
**Estimated Effort**: 3-4 hours

#### Migration Strategy:

1. **Convert existing test patterns**:
   ```typescript
   // CONVERT FROM:
   const result = await getTodo({
     fields: ["id", "title"],
     calculations: {
       self: {
         calcArgs: { prefix: "test_" },
         fields: ["id", "title"]
       }
     }
   });
   
   // TO:
   const result = await getTodo({
     fields: [
       "id", "title",
       {
         self: {
           calcArgs: { prefix: "test_" },
           fields: ["id", "title"]
         }
       }
     ]
   });
   ```

2. **Update negative test cases**:
   ```typescript
   // ADD unified field validation tests
   const invalidUnifiedFields = await getTodo({
     fields: [
       "id",
       {
         // @ts-expect-error - invalid calculation structure
         invalidCalc: { wrongProperty: "bad" }
       }
     ]
   });
   ```

3. **Add new test patterns**:
   - Test complex nested calculations within fields
   - Test mixed field/calculation/relationship selections
   - Test edge cases with empty calculations

### Phase 6: Complex Nested Calculation Support
**Files**: `lib/ash_typescript/rpc/codegen.ex`
**Priority**: Medium
**Estimated Effort**: 4-5 hours

#### Advanced Type Inference:

1. **Recursive calculation nesting**:
   ```typescript
   type InferCalculations<
     CalculationObjects extends Record<string, any>,
     InternalCalculations extends Record<string, any>
   > = {
     [K in keyof CalculationObjects]?: K extends keyof InternalCalculations
       ? InternalCalculations[K] extends { __returnType: infer ReturnType; }
         ? ReturnType extends ResourceBase
           ? InferResourceResult<
               ReturnType, 
               CalculationObjects[K]["fields"],
               CalculationObjects[K]["calculations"] extends Record<string, any> 
                 ? CalculationObjects[K]["calculations"] 
                 : {}
             >
           : ReturnType
         : never
       : never;
   };
   ```

2. **Handle calculation arguments properly**:
   ```typescript
   type ValidateCalculationArgs<
     CalcConfig extends Record<string, any>,
     ExpectedArgs extends Record<string, any>
   > = CalcConfig["calcArgs"] extends ExpectedArgs ? CalcConfig : never;
   ```

### Phase 7: Embedded Resources Integration
**Files**: `lib/ash_typescript/rpc/codegen.ex`
**Priority**: Medium
**Estimated Effort**: 2-3 hours

#### Embedded Resources in Unified Fields:

1. **Update embedded resource field selection**:
   ```typescript
   // Embedded resources should work within unified field selection
   const result = await getTodo({
     fields: [
       "id",
       {
         metadata: ["category", "priority"],
         self: {
           calcArgs: { prefix: "test_" },
           fields: [
             "id",
             { metadata: ["category", "displayCategory"] }
           ]
         }
       }
     ]
   });
   ```

2. **Update embedded resource type inference**:
   - Ensure embedded resources work within calculation field selections
   - Handle embedded resource calculations properly
   - Support nested embedded resources in unified format

## Implementation Order

### Week 1: Core Type System
1. **Day 1-2**: Phase 1 - Remove calculations parameter from config types
2. **Day 3-4**: Phase 2 - Implement UnifiedFieldSelection type system
3. **Day 5**: Phase 3 - Update result type inference

### Week 2: Function Generation and Testing
1. **Day 1-2**: Phase 4 - Update RPC function generation
2. **Day 3-4**: Phase 5 - Migrate test patterns
3. **Day 5**: Testing and validation

### Week 3: Advanced Features
1. **Day 1-2**: Phase 6 - Complex nested calculation support
2. **Day 3-4**: Phase 7 - Embedded resources integration
3. **Day 5**: Final testing and documentation

## Risk Mitigation

### Breaking Changes
- **Impact**: This is a breaking change for any existing TypeScript code
- **Mitigation**: 
  - Provide migration guide in CHANGELOG.md
  - Consider providing a codemod for automated migration
  - Increment major version number

### Type Complexity
- **Risk**: Unified field selection might create overly complex types
- **Mitigation**: 
  - Use type aliases to break down complexity
  - Provide clear examples in generated comments
  - Consider type simplification for common patterns

### Performance Impact
- **Risk**: Complex recursive types might slow TypeScript compilation
- **Mitigation**: 
  - Benchmark TypeScript compilation times
  - Consider type depth limits
  - Provide opt-out mechanisms for complex inference

## Testing Strategy

### Unit Tests
- Test each phase independently
- Mock complex type scenarios
- Validate edge cases

### Integration Tests
- Test with real Ash resources
- Validate generated TypeScript compiles
- Test runtime behavior matches types

### Regression Tests
- Ensure existing functionality still works
- Test backwards compatibility removal is complete
- Validate performance improvements

## Success Criteria

### Functional
- ✅ Generated TypeScript uses unified field format
- ✅ Type inference works correctly for all field types
- ✅ Complex nested calculations type correctly
- ✅ Embedded resources work within unified format
- ✅ All tests pass with new format

### Technical
- ✅ Code reduction from removing dual-parameter support
- ✅ Improved type safety and developer experience
- ✅ Consistent API across all RPC functions
- ✅ No runtime performance degradation

### Quality
- ✅ All TypeScript test files compile successfully
- ✅ Clear error messages for invalid usage
- ✅ Comprehensive documentation and examples
- ✅ Migration guide for existing users

## Post-Implementation

### Documentation Updates
- Update README.md with new field selection examples
- Update API documentation with unified format
- Provide migration guide for existing users

### Performance Monitoring
- Monitor TypeScript compilation times
- Track any performance regressions
- Optimize complex type inference if needed

### Community Support
- Provide examples and best practices
- Address user questions and feedback
- Consider additional tooling (codemod, etc.)

This plan provides a comprehensive roadmap for updating the type inference and TypeScript generation to support the new unified field API, ensuring type safety and developer experience while maintaining the architectural improvements gained from removing the dual-parameter system.