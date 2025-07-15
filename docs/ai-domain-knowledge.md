# AI Domain Knowledge

This guide explains the business logic, key abstractions, and domain-specific concepts in AshTypescript that AI assistants need to understand to work effectively with the codebase.

## 🚨 CRITICAL BUSINESS DOMAIN: Environment Separation

### Test-Driven Development Domain

**BUSINESS REALITY**: AshTypescript's primary development domain exists entirely in the `:test` environment:

- **Primary Resources**: `AshTypescript.Test.Todo`, `AshTypescript.Test.TodoMetadata`, etc.
- **Domain Configuration**: `AshTypescript.Test.Domain` with full RPC setup
- **Real-World Usage**: These test resources represent comprehensive real-world usage patterns

**This is NOT just testing infrastructure** - these are the canonical examples and primary development resources for the entire system.

**Business Impact**: Any development or debugging that doesn't use `:test` environment will fail to access the core business domain.

## Core Domain Concepts

### The Type Bridge Problem

**Problem**: Elixir/Ash backend uses dynamic typing and powerful abstractions, while TypeScript frontend needs static types and compile-time safety.

**Solution**: AshTypescript acts as a "type bridge" that:
1. Introspects Ash resource definitions at compile time
2. Generates corresponding TypeScript types and interfaces  
3. Creates RPC client functions with full type safety
4. Maintains consistency between backend changes and frontend types
5. **Embedded Resource Support**: Full schema generation for Ash embedded resources (Phase 1 complete)

### Resource-Centric Architecture

**Key Insight**: Everything revolves around Ash resources as the source of truth.

```elixir
# Ash Resource (Source of Truth)
defmodule MyApp.Todo do
  use Ash.Resource, domain: MyApp.Domain
  
  attributes do
    uuid_primary_key :id
    attribute :title, :string
    attribute :completed, :boolean
  end
  
  actions do
    defaults [:create, :read, :update, :destroy]
  end
end

# Generated TypeScript (Derived)
type TodoSchema = {
  id: string;
  title: string;
  completed?: boolean | null;
}
```

**Principle**: Any change to Ash resource should automatically flow to TypeScript via code generation.

## Key Domain Abstractions

### 1. RPC Actions vs Resource Actions

**Domain Distinction**:
- **Resource Actions**: Defined in Ash resources (`actions do ... end`)
- **RPC Actions**: Subset of resource actions exposed via RPC (`rpc_action :name, :action`)

**Business Logic**:
```elixir
# Not all resource actions should be exposed publicly
defmodule MyApp.Todo do
  actions do
    create :create, accept: [:title, :description]
    read :read
    read :admin_read, accept: [:internal_notes]  # Admin only
    update :complete, accept: [:completed]
    action :calculate_stats, :generic  # Complex business logic
  end
end

# Domain controls what's exposed via RPC
defmodule MyApp.Domain do
  rpc do
    resource MyApp.Todo do
      rpc_action :create_todo, :create        # ✓ Exposed
      rpc_action :list_todos, :read           # ✓ Exposed  
      rpc_action :complete_todo, :complete    # ✓ Exposed
      # admin_read NOT exposed - stays internal
    end
  end
end
```

### 2. Field Selection Business Logic

**Domain Problem**: Frontend often needs partial data (performance, security, UX)

**Solution**: Type-safe field selection at multiple levels

```typescript
// Business requirement: Show todo list with minimal data
const todos = await listTodos({
  fields: ["id", "title", "completed"]  // Only these fields
});

// Business requirement: Show todo details with user info  
const todoDetail = await getTodo({
  fields: ["id", "title", "description", "due_date"],
  relationships: {
    user: ["name", "email"]  // Nested field selection
  }
});
```

**Key Insight**: Field selection is both a performance optimization and a security mechanism (prevents over-fetching sensitive data).

### 3. Calculation System

**Domain Concept**: Calculations are computed fields that can be complex business logic

**Types of Calculations**:

1. **Simple Calculations** (attribute-like):
   ```elixir
   calculate :display_name, :string, expr(title <> " (" <> status <> ")")
   ```
   
2. **Complex Calculations** (with arguments):
   ```elixir
   calculate :time_estimate, :integer, TimeCalculation do
     argument :complexity_factor, :float, default: 1.0
   end
   ```

3. **Resource Calculations** (return other resources):
   ```elixir
   calculate :self, :struct, SelfCalculation do
     constraints instance_of: __MODULE__
     argument :prefix, :string, allow_nil?: true
   end
   ```

**Business Logic**: Resource calculations enable recursive data fetching patterns (e.g., "get this todo and related todos with same complexity").

### 4. Multitenancy Models

**Domain Problem**: SaaS applications need data isolation per tenant (user, organization, etc.)

**Two Strategies**:

1. **Attribute-based Multitenancy**:
   ```elixir
   # Data includes tenant identifier
   multitenancy do
     strategy :attribute
     attribute :user_id  # Every record belongs to a user
   end
   ```
   
   **Business Logic**: User can only see their own data. Tenant ID stored in database.

2. **Context-based Multitenancy**:
   ```elixir
   # Tenant determined by request context
   multitenancy do
     strategy :context  # Organization context, no attribute stored
   end
   ```
   
   **Business Logic**: Organization context determines data access. More flexible tenant identification.

**Critical Domain Rule**: Tenant isolation must be preserved at all times. Cross-tenant data access is a security violation.

### 5. Embedded Resources (Critical Gap)

**Domain Concept**: Embedded resources are full Ash resources stored as structured data within other resources.

**Key Characteristics**:
- Use `data_layer: :embedded` instead of standard data layers
- Support attributes, calculations, validations, identities, actions  
- Cannot have policies, aggregates, or complex relationships
- Stored as maps/JSON in parent resource attributes

**Business Use Cases**:
- **Structured Metadata**: Todo metadata with category, priority, tags
- **Configuration Objects**: User settings, preferences, feature flags
- **Nested Forms**: Address information, profile data, contact details
- **Audit Trails**: Historical data snapshots, change tracking

**Domain Examples**:
```elixir
# Embedded resource definition
defmodule MyApp.TodoMetadata do
  use Ash.Resource, data_layer: :embedded
  
  attributes do
    attribute :category, :string, public?: true, allow_nil?: false
    attribute :priority_score, :integer, public?: true, default: 0
    attribute :tags, {:array, :string}, public?: true, default: []
  end
  
  calculations do
    calculate :display_category, :string, expr(category || "Uncategorized")
    
    calculate :adjusted_priority, :integer, AdjustedPriorityCalculation do
      argument :urgency_multiplier, :float, default: 1.0
    end
  end
end

# Usage in parent resource
defmodule MyApp.Todo do
  use Ash.Resource, domain: MyApp.Domain
  
  attributes do
    attribute :metadata, MyApp.TodoMetadata, public?: true              # Single embed
    attribute :metadata_history, {:array, MyApp.TodoMetadata}, public?: true  # Array embed
  end
end
```

**✅ IMPLEMENTED (Phase 1 Complete)**:
- **Current Status**: Embedded resources fully supported with type generation
- **Generated Output**: 4,203 lines of TypeScript (vs 91 lines before)
- **Type Safety**: Complete embedded resource schema generation
- **Integration**: Automatic discovery and inclusion in schema generation pipeline

**Discovery Solution Implemented**:
```elixir
# Automatic discovery from attributes (no domain config needed)
embedded_resources = AshTypescript.Codegen.find_embedded_resources(rpc_resources)
all_resources_for_schemas = rpc_resources ++ embedded_resources

# Generated TypeScript includes full schemas:
# TodoMetadataResourceSchema, TodoMetadataFieldsSchema, etc.
```

**Implemented Domain Logic**:
1. ✅ **Discovery**: Automatic scanning of resource attributes for embedded types
2. ✅ **Schema Generation**: Full TypeScript schemas for embedded resources  
3. ✅ **Type Reference**: Proper references (`TodoMetadataResourceSchema | null`)
4. 🔄 **Field Selection**: Basic support (Phase 2 for advanced field selection)

**Business Impact Achieved**:
- ✅ **Structured Data**: Full type safety for complex nested data structures
- ✅ **Nested Validation**: Ash validations work in embedded contexts with TypeScript support
- **Calculation Composition**: Cannot use embedded calculations in type inference
- **Developer Experience**: Forces workarounds using generic `Record<string, any>` types

**Architecture Requirements**: See `docs/ai-embedded-resources.md` for implementation details.

## Domain-Specific Business Rules

### Type Safety Rules

1. **Progressive Type Refinement**: 
   - Start with broad Ash types
   - Refine to specific TypeScript types  
   - Maintain nullability and optionality accurately

2. **Field Selection Consistency**:
   - If a field is selected, it must be present in response
   - If a field is not selected, it must be absent from response  
   - Nested selections follow same rule recursively

3. **Calculation Field Specs**:
   - Calculations with arguments require separate field specification
   - Field specs applied post-loading to avoid Ash validation issues
   - Nested calculations inherit parent resource's field selection patterns

### RPC Communication Rules

1. **Request Structure**:
   ```typescript
   {
     action: string,           // Required: which RPC action
     fields?: string[],        // Optional: field selection
     input?: Record<string, any>, // Action-specific arguments
     calculations?: Record<string, CalcConfig>, // Complex calculations
     filter?: FilterInput,     // Query filtering
     tenant?: string          // Multitenancy parameter
   }
   ```

2. **Response Structure**:
   ```typescript
   {
     success: boolean,
     data?: any,              // Present if success: true
     errors?: ErrorDetails    // Present if success: false
   }
   ```

### Security and Authorization

1. **Tenant Parameter Handling**:
   - **Parameter Mode**: Tenant passed explicitly in request (`require_tenant_parameters: true`)
   - **Connection Mode**: Tenant extracted from connection/session (`require_tenant_parameters: false`)

2. **Field Selection Security**:
   - Private fields automatically excluded from type generation
   - Calculation visibility controlled by `public?` attribute
   - Relationship visibility controlled by resource exposure

## Domain Entity Relationships

### Primary Test Domain

The test domain (`test/support/domain.ex`) models a todo application with these entities:

```
User (1) ──────────────┐
    │                  │
    │ owns           belongs_to
    ▼                  │
UserSettings (1)       │
                       │
                       ▼
                   Todo (many)
                       │
                       │ has_many
                       ▼
                 TodoComment (many)
                       │
                       │ belongs_to
                       ▼
                   User (author)
```

**Business Logic**:
- Users own todos and have settings
- Todos can have comments from any user
- Comments have ratings (1-5 stars)
- Aggregates calculate metrics (comment counts, average ratings, etc.)

### Multitenancy Test Resources

1. **UserSettings** (Attribute-based):
   - Each user can only see their own settings
   - Tenant ID = User ID
   - Direct database-level isolation

2. **OrgTodo** (Context-based):
   - Todos belong to organization context
   - Organization ID passed as tenant parameter
   - More flexible tenant identification

## Business Domain Patterns

### Calculation Composition Patterns

**Pattern**: Nested calculations for complex business logic

```typescript
// Business case: Get todo with completion prediction
const result = await getTodo({
  fields: ["id", "title"],
  calculations: {
    completion_prediction: {
      calcArgs: { 
        user_velocity: 0.8,
        complexity_factor: 1.2
      },
      fields: ["estimated_hours", "confidence_score"],
      calculations: {
        similar_todos: {  // Find similar completed todos
          calcArgs: { similarity_threshold: 0.7 },
          fields: ["completion_time", "actual_effort"]
        }
      }
    }
  }
});
```

**Domain Logic**: Enables sophisticated business intelligence by composing calculations.

### Filtering and Querying Patterns

**Business Requirements**:
- Users need to find relevant data quickly
- Filtering should be type-safe  
- Complex queries should be supported

**Implementation**:
```typescript
const urgentTodos = await listTodos({
  fields: ["id", "title", "due_date"],
  filter: {
    and: [
      { due_date: { lt: "2024-12-31" } },
      { completed: { eq: false } },
      { priority: { in: ["high", "urgent"] } }
    ]
  },
  sort: ["due_date"]
});
```

### Error Handling Domain Logic

**Business Rule**: Distinguish between user errors and system errors

1. **User Errors** (400-level):
   - Invalid field names
   - Missing required arguments
   - Authorization failures
   - Tenant parameter issues

2. **System Errors** (500-level):
   - Type generation failures
   - Database connectivity issues
   - Calculation execution errors

**Response Pattern**:
```typescript
{
  success: false,
  errors: {
    code: "VALIDATION_ERROR",
    message: "Field 'invalid_field' does not exist on Todo",
    details: { /* specifics */ }
  }
}
```

## Domain Evolution Patterns

### Adding New Features

1. **New Resource Types**:
   - Define Ash resource with attributes, relationships, actions
   - Add to domain's `resources` block
   - Expose via RPC actions in domain's `rpc` block
   - Generate types and test TypeScript compilation

2. **New Calculation Types**:
   - Implement calculation module with business logic
   - Define calculation in resource with proper constraints
   - Test type generation handles return type correctly
   - Verify nested calculation support if applicable

3. **New Multitenancy Requirements**:
   - Choose strategy (attribute vs context) based on business model
   - Implement tenant isolation tests
   - Verify TypeScript generation includes/excludes tenant parameters correctly

### AshTypescript Library Backwards Compatibility

**Domain Constraint**: As a library, AshTypescript must not break applications that depend on it

**AshTypescript Controls (Real Backwards Compatibility Concerns)**:

**Safe Changes**:
- Adding new DSL options (with sensible defaults)
- Adding new mix task flags/options
- Improving generated TypeScript types (more specific types, better nullability)
- Adding new runtime helper functions
- Adding support for new Ash types/features

**Breaking Changes** (require major version bump):
- Changing DSL syntax (removing options, changing required parameters)
- Changing generated TypeScript API (function signatures, return types)
- Changing mix task interface (removing flags, changing behavior)
- Changing RPC communication protocol
- Requiring newer Elixir/Ash versions

**Applications Control (Not AshTypescript's Concern)**:
- Adding/removing fields from their own resources
- Adding/removing their own RPC actions  
- Changing their own calculation definitions
- Modifying their own field types

**Key Insight**: AshTypescript generates code based on application-defined resources. When applications change their resources, they regenerate types to match. AshTypescript only needs to ensure its generation logic remains stable and the generated API format doesn't break.

This domain knowledge enables AI assistants to make decisions that align with AshTypescript's role as a code generation library, not as an application that owns domain logic.