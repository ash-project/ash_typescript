# AshTypescript

A library for generating TypeScript types from Ash resources and actions. AshTypescript provides automatic TypeScript type generation for your Ash APIs, ensuring type safety between your Elixir backend and TypeScript frontend.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `ash_typescript` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ash_typescript, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/ash_typescript>.

## Features

- Automatic TypeScript type generation from Ash resources
- Support for all Ash action types (read, create, update, destroy, action)
- Type-safe RPC call generation
- Support for complex return types with field constraints
- Relationship and aggregate type generation

## Usage

See test/support/todo.ex for an example setup.

### Creating RPC Specifications

Create JSON files in your `assets/js/ash_rpc/` folder to specify which actions you want to generate TypeScript types for and which fields to select. Here are examples based on common Todo resource operations:

**Todo Actions (`assets/js/ash_rpc/todo_crud.json`):**
```json
[
  {
    "action": "read_todo",
    "select": ["id", "title", "description", "completed", "status", "priority", "due_date", "tags", "created_at"]
  },
  {
    "action": "get_todo",
    "select": ["id", "title", "description", "completed", "status", "priority", "due_date", "tags", "metadata", "created_at", "updated_at", "is_overdue", "days_until_due"]
  },
  {
    "action": "create_todo",
    "select": ["id", "title", "description", "completed", "status", "priority", "due_date", "tags", "created_at"]
  },
  {
    "action": "update_todo",
    "select": ["id", "title", "description", "completed", "status", "priority", "due_date", "tags", "updated_at"],
    "load": [{"comments": ["id", "content"]}]
  },
  {
    "action": "destroy_todo",
    "select": []
  }
]
```


### Running the Code Generator

Once you have your RPC specification files, run the mix task to generate TypeScript types:

```bash
# Generate from all JSON files in the default directory
mix ash_typescript.codegen

# Generate from specific files
mix ash_typescript.codegen --files "assets/js/ash_rpc/todo_crud.json,assets/js/ash_rpc/todo_actions.json" --output "assets/js/generated_types.ts"

# Specify custom RPC endpoints
mix ash_typescript.codegen --process_endpoint "/api/rpc/run" --validate_endpoint "/api/rpc/validate"
```

This will generate TypeScript interfaces, zod schemas, and RPC call functions for type-safe communication with your Ash backend.
