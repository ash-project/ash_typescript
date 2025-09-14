# AshTypescript Implementation Guides

## Adding New Types

### Custom Types with TypeScript Callbacks
```elixir
defmodule MyApp.CustomType do
  use Ash.Type

  # Required Ash.Type callbacks
  def storage_type(_), do: :string
  def cast_input(value, _), do: {:ok, value}
  def cast_stored(value, _), do: {:ok, value}
  def dump_to_native(value, _), do: {:ok, value}
  def apply_constraints(value, _), do: {:ok, value}

  # AshTypescript callback
  def typescript_type_name, do: "CustomTypes.MyType"
end
```

### Configuration
```elixir
# config/config.exs
config :my_app,
  import_into_generated: [
    %{import_name: "CustomTypes", file: "./customTypes"}
  ]
```

### TypeScript Definition
```typescript
// customTypes.ts
export type PriorityScore = 1 | 2 | 3 | 4 | 5;
export type ColorPalette = "red" | "blue" | "green";
```

## Implementing Calculations

### Basic Calculation with Arguments
```elixir
defmodule MyApp.Todo do
  calculations do
    calculate :is_overdue, :boolean do
      argument :current_date, :date, allow_nil?: false
      calculation expr(due_date < ^arg(:current_date))
    end
  end
end
```

### Complex Calculation Returning Resource
```elixir
calculate :metadata, MyApp.TodoMetadata do
  argument :multiplier, :integer, default: 1
  calculation fn records, %{multiplier: multiplier} ->
    # Return TodoMetadata struct
  end
end
```

### TypeScript Usage
```typescript
const todos = await listTodos({
  fields: [
    "id", "title",
    {"is_overdue": {"args": {"current_date": "2025-01-01"}}},
    {"metadata": {"args": {"multiplier": 2}, "fields": ["category", "priority"]}}
  ]
});
```

## Multitenancy Setup

### Resource Configuration
```elixir
defmodule MyApp.OrgTodo do
  use Ash.Resource

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_primary_key :id
    attribute :organization_id, :uuid, allow_nil?: false
  end
end
```

### Domain Configuration
```elixir
defmodule MyApp.Domain do
  use Ash.Domain, extensions: [AshTypescript.Rpc]

  typescript_rpc do
    resource MyApp.OrgTodo do
      rpc_action :list_org_todos, :read
      rpc_action :create_org_todo, :create
    end
  end
end
```

### TypeScript Usage
```typescript
// Set tenant context
const todos = await listOrgTodos({
  fields: ["id", "title"],
  headers: {"tenant": "org_123"}
});
```

## Embedded Resources

### Embedded Resource Definition
```elixir
defmodule MyApp.TodoMetadata do
  use Ash.Resource, embedded?: true

  attributes do
    attribute :category, :string
    attribute :priority, :integer
    attribute :tags, {:array, :string}
  end

  calculations do
    calculate :display_name, :string do
      calculation expr(category <> " (" <> priority <> ")")
    end
  end
end
```

### Main Resource Usage
```elixir
defmodule MyApp.Todo do
  attributes do
    attribute :metadata, MyApp.TodoMetadata
  end
end
```

### TypeScript Field Selection
```typescript
const todos = await listTodos({
  fields: [
    "id", "title",
    {"metadata": ["category", "priority", {"display_name": {}}]}
  ]
});
```

## Test Organization

### Directory Structure
```
test/ts/
├── shouldPass.ts          # Valid usage patterns
├── shouldPass/
│   ├── operations.ts      # Basic CRUD operations
│   ├── calculations.ts    # Calculation field selection
│   ├── relationships.ts   # Relationship field selection
│   ├── customTypes.ts     # Custom type usage
│   └── unionTypes.ts      # Union type handling
├── shouldFail.ts          # Invalid patterns (should fail compilation)
└── shouldFail/
    ├── invalidFields.ts   # Non-existent fields
    ├── typeMismatches.ts  # Type assignment errors
    └── invalidStructure.ts # Wrong nesting/structure
```

### Testing Commands
```bash
mix test.codegen                    # Generate types
cd test/ts && npm run compileGenerated  # Test compilation
npm run compileShouldPass           # Valid patterns
npm run compileShouldFail           # Invalid patterns (should fail)
```

### Test Validation Pattern
```elixir
# ✅ CORRECT: Use regex for structure validation
list_todos_regex = ~r/export type ListTodosConfig = \{[^}]*fields: UnifiedFieldSelection<TodoResourceSchema>\[\][^}]*\};/m
assert Regex.match?(list_todos_regex, typescript_output)

# ❌ WRONG: String.contains? misses structural issues
assert String.contains?(typescript_output, "ListTodosConfig")
```

## Field Processing Debugging

### Common Issues
- **Invalid field format**: Use `["field", {"relation": ["field"]}]`
- **Missing calculations**: Verify calculation is properly defined in resource
- **Type inference failure**: Check schema key generation

### Debug with Tidewave
```elixir
# Test field processing
mcp__tidewave__project_eval("""
fields = ["id", {"user" => ["name"]}]
AshTypescript.Rpc.RequestedFieldsProcessor.process(
  AshTypescript.Test.Todo, :read, fields
)
""")

# Test full pipeline
mcp__tidewave__project_eval("""
conn = %Plug.Conn{} |> Plug.Conn.put_private(:ash, %{actor: nil, tenant: nil})
params = %{"action" => "list_todos", "fields" => ["id", "title"]}
AshTypescript.Rpc.run_action(:ash_typescript, conn, params)
""")
```

---
**For detailed implementation patterns, see the core documentation in docs/implementation/**