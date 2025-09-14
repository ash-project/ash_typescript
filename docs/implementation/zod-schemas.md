# Zod Schema Generation for AshTypescript

## Executive Summary

Adding Zod schema generation to AshTypescript is highly feasible and would provide significant value for runtime validation. The current system already generates comprehensive TypeScript input types for create/update/destroy actions, making it straightforward to parallelize Zod schema generation.

## Current System Analysis

**Strengths for Zod Integration:**
1. **Existing Type Generation**: `generate_input_type/3` in `lib/ash_typescript/rpc/codegen.ex:573-714` already processes all action types and generates TypeScript input types
2. **Type Mapping**: `get_ts_type/2` in `lib/ash_typescript/codegen.ex` provides robust Ash → TypeScript type mapping
3. **Action Processing**: The system already handles create/update/destroy actions with their accepted fields and arguments
4. **Field Formatting**: Consistent field name formatting using `AshTypescript.FieldFormatter`

**Key Input Type Patterns Identified:**
- **Create Actions**: Generate types from `accept` fields + `arguments`
- **Update Actions**: Same as create but with optional primary key handling
- **Destroy Actions**: Minimal input (usually just primary key)
- **Read Actions**: Primarily arguments for filtering/searching

## Implementation Plan

### Phase 1: Core Zod Schema Generation Foundation

**1.1 Add Zod Schema Generation Function**
- Location: `lib/ash_typescript/rpc/codegen.ex`
- New function: `generate_zod_schema/3` (parallel to `generate_input_type/3`)
- Map Ash types to Zod schema constructors

**1.2 Ash Type → Zod Schema Mapping**
```elixir
# Core type mappings
:string -> "z.string()"
:integer -> "z.number().int()"
:boolean -> "z.boolean()"
:uuid -> "z.string().uuid()"
:date -> "z.string().datetime()" # or custom date validation
{:array, inner_type} -> "z.array(#{map_type(inner_type)})"

# Advanced mappings
:atom with constraints -> z.enum(["low", "medium", "high"])
:union -> z.discriminatedUnion() or z.union()
:map -> z.object() with field definitions
custom types -> leverage existing get_ts_type logic
```

**1.3 Schema Configuration Options**
```elixir
# Configuration in application config
config :ash_typescript,
  generate_zod_schemas: true,
  zod_import_path: "zod",  # Allow custom import
  zod_schema_suffix: "Schema"  # e.g., createTodoSchema
```

### Phase 2: Integration with Existing Generation Pipeline

**2.1 Extend `generate_rpc_function/5`**
- Add Zod schema generation alongside input type generation
- Generate schemas for create/update/destroy actions specifically
- Export both TypeScript types and Zod schemas

**2.2 Generated Output Structure**
```typescript
// Input TypeScript type (existing)
export type CreateTodoInput = {
  title: string;
  description?: string;
  priority?: "low" | "medium" | "high" | "urgent";
  autoComplete?: boolean;
  userId: string;
};

// NEW: Zod schema for runtime validation
export const CreateTodoZodSchema = z.object({
  title: z.string(),
  description: z.string().optional(),
  priority: z.enum(["low", "medium", "high", "urgent"]).optional(),
  autoComplete: z.boolean().optional(),
  userId: z.string().uuid(),
});

// Helper function for validation
export function validateCreateTodo(input: unknown): CreateTodoInput {
  return createTodoSchema.parse(input);
}
```

### Phase 3: Advanced Type Support

**3.1 Union Type Support**
- Map Ash union types to `z.discriminatedUnion()` when tagged
- Use `z.union()` for untagged unions
- Handle complex nested union structures

**3.2 Embedded Resource Support**
- Generate schemas for embedded resources (TodoMetadata, etc.)
- Reference embedded schemas in parent schemas
- Handle array of embedded resources

**3.3 Custom Type Integration**
- Extend existing custom type system to include Zod mappings
- Support for custom validation rules and refinements
- Integration with AshTypescript's constraint system

### Phase 4: Testing and Validation

**4.1 Test Structure**
```bash
test/ts/zod/
├── shouldPass/           # Valid Zod usage patterns
├── shouldFail/           # Invalid patterns that should fail validation
└── schemas/              # Generated Zod schemas for testing
```

**4.2 Testing Workflow**
```bash
# Generate types and schemas
mix test.codegen

# Test Zod compilation
cd test/ts && npm run compileZodSchemas

# Test validation (new)
cd test/ts && npm run testZodValidation
```

### Phase 5: Configuration and Customization

**5.1 Granular Control**
```elixir
# In domain configuration
typescript_rpc do
  resource MyApp.Todo do
    rpc_action :create_todo, :create do
      generate_zod_schema? true  # Override global setting
      zod_refinements [:custom_title_validation]
    end
  end
end
```

**5.2 Custom Validation Rules**
- Support for `.refine()` and `.transform()` through configuration
- Custom error messages
- Integration with Ash validation constraints

## Technical Implementation Details

### Type Mapping Strategy
```elixir
defp get_zod_type(%{type: type, constraints: constraints}, context) do
  case type do
    Ash.Type.String ->
      case constraints[:one_of] do
        values when is_list(values) ->
          enum_values = Enum.map(values, &~s["#{&1}"]) |> Enum.join(", ")
          "z.enum([#{enum_values}])"
        _ -> "z.string()"
      end

    Ash.Type.Integer ->
      constraints_str = build_number_constraints(constraints)
      "z.number().int()#{constraints_str}"

    {:array, inner_type} ->
      inner_schema = get_zod_type(%{type: inner_type, constraints: []}, context)
      "z.array(#{inner_schema})"

    # ... more mappings
  end
end

defp build_number_constraints(constraints) do
  constraints
  |> Enum.reduce("", fn
    {:min, value}, acc -> acc <> ".min(#{value})"
    {:max, value}, acc -> acc <> ".max(#{value})"
    _, acc -> acc
  end)
end
```

### Integration Points
1. **Import Generation**: Add Zod import to generated TypeScript
2. **Schema Export**: Export schemas alongside types
3. **Validation Helpers**: Generate validation functions
4. **Error Handling**: Map Zod errors to consistent format

## Benefits and Use Cases

**Primary Benefits:**
1. **Runtime Type Safety**: Validate API inputs at runtime
2. **Form Validation**: Direct integration with React Hook Form, Formik
3. **API Boundary Protection**: Validate data from untrusted sources
4. **Developer Experience**: Type-safe validation with excellent error messages

**Use Cases:**
```typescript
// Form validation
const createTodoForm = useForm<CreateTodoInput>({
  resolver: zodResolver(createTodoSchema),
});

// API validation
export async function createTodo(input: unknown) {
  const validInput = createTodoSchema.parse(input);
  return apiCall(validInput);
}

// Data transformation
const processed = createTodoSchema.transform((data) => ({
  ...data,
  priority: data.priority || "medium"
})).parse(rawInput);
```

## Migration Strategy

**Phase 1**: Opt-in feature with configuration flag
**Phase 2**: Generate schemas alongside existing types
**Phase 3**: Add validation helpers and utilities
**Phase 4**: Full documentation and examples

## Risk Assessment

**Low Risk Factors:**
- Non-breaking addition to existing system
- Leverages proven type mapping logic
- Optional feature that doesn't affect current users

**Medium Risk Factors:**
- Bundle size increase (Zod dependency)
- Complex type mapping edge cases
- Maintenance overhead for new type mappings

## Conclusion

Adding Zod schema generation to AshTypescript is a natural evolution that leverages existing infrastructure. The implementation can be done incrementally without breaking changes, providing immediate value for runtime validation while maintaining the excellent compile-time type safety already provided.

**Recommended Next Steps:**
1. Implement core Zod schema generation for basic types
2. Add configuration options and testing infrastructure
3. Extend to complex types (unions, embedded resources)
4. Document patterns and best practices

## Implementation References

- **Primary File**: `lib/ash_typescript/rpc/codegen.ex`
- **Type Mapping**: `lib/ash_typescript/codegen.ex:get_ts_type/2`
- **Input Generation**: `lib/ash_typescript/rpc/codegen.ex:573-714`
- **Test Resources**: `test/support/resources/todo.ex`
- **Domain Config**: `test/support/domain.ex`

---

**Last Updated**: 2025-08-20
**Status**: Planning Complete - Ready for Implementation
