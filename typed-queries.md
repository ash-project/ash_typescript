# Typed Queries Implementation Plan

## Overview

Typed queries are server-side queries designed for SSR (Server-Side Rendering) in frameworks like SvelteKit, Next.js, and Nuxt. They provide:
1. Type-safe initial data hydration for SSR pages
2. Automatic TypeScript type generation matching the exact shape of fetched data
3. Export const field selections for easy client-side re-fetching

## Architecture Analysis

### Current System Understanding

1. **RPC Pipeline**: Four-stage processing (parse → execute → process → format)
2. **Field Processing**: `RequestedFieldsProcessor` handles field selection/validation
3. **Type Generation**: Schema-based system in `codegen.ex` and `rpc/codegen.ex`
4. **Field Formatting**: Configurable formatter for client/server field name conversion

### Key Components to Leverage

1. **RequestedFieldsProcessor**: Already handles the exact field format we need
2. **Type Inference System**: Existing schema generation and InferResourceResult type
3. **Field Formatter**: Ensures consistent field naming between server and client

## Implementation Strategy

### Phase 1: DSL and Data Extraction

#### 1.1 Extract Typed Queries from Domain
- Modify `get_rpc_resources_and_actions` in `rpc/codegen.ex`
- Add parallel function `get_typed_queries` to extract typed query configurations
- Structure: `[{resource, typed_query_config}, ...]`

#### 1.2 Process Field Definitions
- Use `RequestedFieldsProcessor.atomize_requested_fields` on typed query fields
- Use `RequestedFieldsProcessor.process` to get select/load/template
- This ensures consistency with RPC field processing

### Phase 2: Type Generation

#### 2.1 Generate TypeScript Types
- Create `generate_typed_query_types` function
- For each typed query:
  ```typescript
  // Example output
  export type ListTodosUserPageResult = InferResourceResult<
    TodoResourceSchema,
    [
      "id",
      "title", 
      "description",
      "priority",
      "commentCount",
      { comments: ["id", "content"] },
      { self: { args: { prefix: "some prefix" }, fields: ["id", "title", "isOverdue"] } }
    ]
  >;
  ```

#### 2.2 Handle Complex Cases
- **Pagination**: Check if action has pagination, wrap in pagination result type
- **Arrays**: Read actions without `get?` return arrays
- **Nested Resources**: Leverage existing InferResourceResult recursive typing

### Phase 3: Field Selection Constants

#### 3.1 Generate Export Constants
- Transform atomized fields back to client format using output formatter
- Preserve exact structure for calculations with args
- Example output:
  ```typescript
  export const listTodosUserPageFields = [
    "id",
    "title",
    "description", 
    "priority",
    "commentCount",
    { comments: ["id", "content"] },
    { self: { args: { prefix: "some prefix" }, fields: ["id", "title", "isOverdue"] } }
  ] as const;
  ```

#### 3.2 Type the Constants
- Use `as const` for literal type inference
- Ensure TypeScript preserves the exact structure

### Phase 4: Integration

#### 4.1 Update Main Generation Flow
- Add typed query generation to `generate_full_typescript`
- Place after resource schemas but before RPC functions
- Group all typed queries in a dedicated section

#### 4.2 Documentation Comments
- Add JSDoc comments explaining usage
- Include example of SSR usage and client refetch

## Implementation Details

### File Structure Changes

1. **lib/ash_typescript/rpc/codegen.ex**
   - Add `get_typed_queries/1`
   - Add `generate_typed_query_section/2`
   - Add `generate_typed_query_type/3`
   - Add `generate_typed_query_fields_const/3`
   - Update `generate_full_typescript/4`

### Key Functions to Implement

```elixir
defp get_typed_queries(otp_app) do
  otp_app
  |> Ash.Info.domains()
  |> Enum.flat_map(fn domain ->
    rpc_config = AshTypescript.Rpc.Info.rpc(domain)
    
    Enum.flat_map(rpc_config, fn %{resource: resource, typed_queries: typed_queries} ->
      Enum.map(typed_queries, fn typed_query ->
        action = Ash.Resource.Info.action(resource, typed_query.action)
        {resource, action, typed_query}
      end)
    end)
  end)
end

defp generate_typed_query_section(typed_queries, all_resources) do
  # Group by resource for better organization
  # Generate types and constants
  # Add section header and documentation
end
```

### Field Format Transformation

The critical transformation flow:
1. DSL fields → `atomize_requested_fields` → internal format
2. Internal format → `RequestedFieldsProcessor.process` → select/load/template
3. Template → `format_extraction_template` → client format for const

### Special Considerations

1. **Multitenancy**: Typed queries don't need tenant params (server-side only)
2. **Error Handling**: Use same validation as RPC actions
3. **Performance**: Reuse existing processing pipelines
4. **Type Safety**: Leverage existing InferResourceResult infrastructure

## Testing Strategy

1. **Unit Tests**
   - Field processing for typed queries
   - Type generation accuracy
   - Field constant generation

2. **Integration Tests**
   - Generate types for test domain
   - Compile TypeScript to verify type correctness
   - Test complex scenarios (nested calculations, unions, etc.)

3. **Usage Tests**
   - Create example SSR usage in shouldPass
   - Verify refetch pattern works correctly

## Benefits of This Approach

1. **Minimal New Code**: Leverages existing field processing and type generation
2. **Consistency**: Uses same field format and processing as RPC actions
3. **Type Safety**: Reuses proven InferResourceResult type system
4. **Clean Integration**: Fits naturally into existing generation pipeline
5. **No Breaking Changes**: Purely additive feature

## Next Steps

1. Implement Phase 1: Extract typed queries from DSL
2. Implement Phase 2: Generate TypeScript types
3. Implement Phase 3: Generate field selection constants
4. Implement Phase 4: Integration and testing
5. Add comprehensive test coverage
6. Update documentation