# Architecture Decisions and Core Insights

## Overview

This guide captures critical architecture decisions and core insights that shape AshTypescript's design and implementation patterns.

## 🚨 CRITICAL: Environment Architecture 

**CORE INSIGHT**: AshTypescript has strict environment dependency - all development must happen in `:test` environment where test resources are available.

### Why Test Environment Architecture

The decision to mandate test environment usage solves several critical problems:

1. **Resource Availability**: Test resources (`AshTypescript.Test.*`) only exist in `:test` environment
2. **Domain Configuration**: Configuration in `config/config.exs` only applies to `:test` environment  
3. **Type Generation**: TypeScript generation depends on test resources being available
4. **Consistent Development**: All developers work in the same environment with the same resources

### Implementation Pattern

```elixir
# config/config.exs
if Mix.env() == :test do
  config :ash_typescript, :domains, [AshTypescript.Test.Domain]
end
```

**Key Commands**: Always use `mix test.codegen` instead of `mix ash_typescript.codegen`

## Revolutionary Context Struct Pattern

**ARCHITECTURAL INSIGHT**: Replace scattered parameter passing with unified context structure.

### The Problem

Original code had massive parameter threading:
- `(resource, formatter)` passed through every function
- 50+ function signatures requiring both parameters
- Difficult to extend with new context data
- Code duplication across similar functions

### The Solution

**PATTERN**: Context struct eliminates parameter passing chaos.

```elixir
# ✅ NEW PATTERN: Context struct eliminates parameter passing
defmodule AshTypescript.Rpc.FieldParser.Context do
  defstruct [:resource, :formatter, :parent_resource]
  
  def new(resource, formatter, parent_resource \\ nil) do
    %__MODULE__{resource: resource, formatter: formatter, parent_resource: parent_resource}
  end
  
  def child(%__MODULE__{} = context, new_resource) do
    %__MODULE__{resource: new_resource, formatter: context.formatter, parent_resource: context.resource}
  end
end

# Usage throughout pipeline
context = Context.new(resource, formatter)
{field_atom, field_spec} = normalize_field(field, context)
classify_and_process(field_atom, field_spec, context)
```

### Benefits Achieved

1. **Cleaner Signatures**: Functions take single `%Context{}` parameter
2. **Easier Extension**: Add new context data without changing all signatures
3. **Better Maintenance**: Single point of context definition
4. **Reduced Errors**: No more missing parameter bugs

## Pipeline Architecture Pattern

**BREAKTHROUGH INSIGHT**: Normalize → Classify → Process pipeline creates consistent field handling.

### The Architecture

```elixir
# ✅ UNIFIED PIPELINE: Clear data flow
def process_field(field, %Context{} = context) do
  field |> normalize_field(context) |> classify_and_process(context)
end

# Normalize: Convert any field input to consistent {field_atom, field_spec} format
def normalize_field(field, context)

# Classify: Determine field type within resource context  
def classify_and_process(field_atom, field_spec, context)
```

### Key Stages

1. **Normalize**: Convert diverse input formats to consistent internal format
2. **Classify**: Determine field type (attribute, relationship, calculation, etc.)
3. **Process**: Handle field according to its type and generate appropriate outputs

### Benefits

- **Consistent Processing**: All fields follow the same pipeline
- **Predictable Behavior**: Easy to understand and debug
- **Extensible**: Easy to add new field types
- **Maintainable**: Clear separation of concerns

## Utility Module Extraction Pattern

**PATTERN**: Extract duplicate logic into focused utility modules.

### Before: Massive Duplication

- **180+ lines of duplicate load building logic**
- **Repetitive calc args processing** across multiple functions
- **Similar field processing patterns** everywhere

### After: Focused Utilities

```elixir
# ✅ CalcArgsProcessor - Consolidates calc args processing (was duplicated 3+ times)
CalcArgsProcessor.process_calc_args(calc_spec, formatter)

# ✅ LoadBuilder - Unifies load entry building (was ~180 lines of duplication)  
{load_entry, field_specs} = LoadBuilder.build_calculation_load_entry(calc_atom, calc_spec, context)
```

### Architectural Benefits

1. **Single Responsibility**: Each utility has one clear purpose
2. **Reusability**: Utilities used across multiple contexts
3. **Testability**: Small, focused modules easier to test
4. **Maintainability**: Changes isolated to specific utilities

## Schema Key-Based Classification

**REVOLUTIONARY INSIGHT**: Use schema keys as authoritative field classifiers instead of structural guessing.

### The Problem

Previous type inference used structural detection:
- Complex conditional types with `never` fallbacks
- Ambiguous field type determination
- TypeScript returning `unknown` instead of proper types

### The Solution

**PATTERN**: Schema keys provide authoritative classification.

```typescript
// ✅ CORRECT: Schema keys determine field classification
type ProcessField<Resource extends ResourceBase, Field> = 
  Field extends string 
    ? Field extends keyof Resource["fields"]
      ? { [K in Field]: Resource["fields"][K] }
      : {}
    : Field extends Record<string, any>
      ? {
          [K in keyof Field]: K extends keyof Resource["complexCalculations"]
            ? // Complex calculation detected by schema key
              Resource["__complexCalculationsInternal"][K] extends { __returnType: infer ReturnType }
                ? ReturnType extends ResourceBase
                  ? InferResourceResult<ReturnType, Field[K]>
                  : ReturnType
                : any
            : any
        }
      : any;
```

### Benefits

1. **Authoritative Classification**: Schema keys eliminate ambiguity
2. **Better Performance**: Direct key lookup vs complex type analysis
3. **Type Safety**: Proper TypeScript inference without `unknown` fallbacks
4. **Maintainable**: Works with naming collisions and edge cases

## Three-Stage Processing Pipeline

**ARCHITECTURAL INSIGHT**: Separate concerns into three distinct stages for complex operations.

### The Pattern

```elixir
# Stage 1: Field Parser - Generate dual statements
{select, load} = FieldParser.parse_requested_fields(client_fields, resource, formatter)

# Stage 2: Ash Query - Execute both select and load
query
|> Ash.Query.select(select)
|> Ash.Query.load(load)

# Stage 3: Result Processor - Filter and format response
ResultProcessor.process_action_result(result, original_client_fields, resource, formatter)
```

### Why Three Stages

1. **Separation of Concerns**: Each stage has clear responsibility
2. **Testability**: Each stage can be tested independently
3. **Flexibility**: Different processing paths for different field types
4. **Performance**: Optimized for different operation types

## Unified Field Format Architecture

**BREAKTHROUGH INSIGHT**: Single field format eliminates dual processing complexity.

### The Problem

Previous system supported two formats:
- ~300 lines of backwards compatibility code
- Dual processing paths for same functionality
- Format conversion overhead
- Maintenance complexity

### The Solution

**BREAKING CHANGE**: Complete removal of separate `calculations` parameter.

```typescript
// ✅ CORRECT - Unified format (required)
const result = await getTodo({
  fields: [
    "id", "title",
    {
      "self": {
        "calcArgs": {"prefix": "test"},
        "fields": ["id", "title"]
      }
    }
  ]
});
```

### Benefits

1. **Single Processing Path**: No dual format handling needed
2. **Better Performance**: No format conversion overhead
3. **Cleaner API**: One way to specify calculations
4. **Maintainable**: Easier to extend with new features

## Dead Code Elimination Philosophy

**CRITICAL DISCOVERY**: Aggressively remove unused code patterns.

### Example: Unused "calculations" Field

```typescript
// ❌ DEAD CODE: This pattern was never implemented and always returned []
{
  "myCalc": {
    "calcArgs": { "arg1": "value" },
    "fields": ["id", "name"],
    "calculations": {  // <- DEAD CODE: Never worked, always empty
      "nestedCalc": { "calcArgs": { "arg2": "value" } }
    }
  }
}
```

### Elimination Strategy

1. **Identify Dead Code**: Look for always-empty patterns
2. **Trace Usage**: Verify code is truly unused
3. **Remove Aggressively**: Don't keep "just in case" code
4. **Simplify**: Use existing patterns instead of creating new ones

## Performance-First Architecture

**PRINCIPLE**: Consider performance implications at architecture level.

### Key Decisions

1. **Schema Key Lookup**: O(1) vs O(n) structural analysis
2. **Post-Query Filtering**: Minimize database queries
3. **Caching**: Resource detection cached per calculation
4. **TypeScript Optimization**: Simple types over complex ones

### Performance Patterns

- **Direct Schema Access**: Use schema keys for classification
- **Minimal Database Queries**: Filter results post-query
- **Efficient Type Generation**: Cache expensive operations
- **Simple TypeScript**: Avoid complex conditional types

## Critical Success Factors

1. **Environment Discipline**: Strict test environment usage
2. **Context Pattern**: Unified parameter passing
3. **Pipeline Architecture**: Clear processing stages
4. **Utility Extraction**: Eliminate code duplication
5. **Schema Authority**: Use schema keys for classification
6. **Performance Awareness**: Consider performance at architecture level

---

**See Also**:
- [Field Processing Insights](field-processing-insights.md) - For field processing implementation details
- [Refactoring Patterns](refactoring-patterns.md) - For major refactoring achievements
- [Advanced Features](advanced-features.md) - For complex feature implementations