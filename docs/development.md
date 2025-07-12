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