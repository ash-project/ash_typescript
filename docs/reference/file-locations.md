# File Locations Reference Card

## Core Library Files (lib/)

### Main Generation Files
- `lib/ash_typescript/codegen.ex` - Core TypeScript type generation
- `lib/ash_typescript/rpc/codegen.ex` - Advanced type inference, RPC client generation
- `lib/ash_typescript/rpc/helpers.ex` - Runtime parsing and processing utilities
- `lib/ash_typescript/field_formatter.ex` - Field selection and formatting logic
- `lib/ash_typescript/rpc.ex` - Main RPC processing with debug outputs

### FieldParser Architecture (Post-Refactoring)
- `lib/ash_typescript/rpc/field_parser.ex` - Main field parser (434 lines)
- `lib/ash_typescript/rpc/field_parser/context.ex` - Context struct (35 lines)
- `lib/ash_typescript/rpc/field_parser/calc_args_processor.ex` - Args processing (55 lines)
- `lib/ash_typescript/rpc/field_parser/load_builder.ex` - Load building utilities (165 lines)
- `lib/ash_typescript/rpc/result_processor.ex` - Result filtering and formatting

## Test Resources (test/support/)

### Domain Configuration
- `test/support/domain.ex` - Comprehensive test domain with RPC configuration
- `test/support/resources/todo.ex` - Primary test resource (full Ash feature coverage)
- `test/support/resources/user.ex` - User resource for relationship testing

### Embedded Resources
- `test/support/resources/embedded/` - Embedded resource definitions
- `test/support/resources/embedded/todo_metadata.ex` - Embedded resource with calculations
- `test/support/resources/embedded/attachment.ex` - File attachment embedded resource

## Generated Output Validation (test/ts/)

### Generated Files
- `test/ts/generated.ts` - Generated TypeScript output
- `test/ts/shouldPass.ts` - Valid usage patterns that must compile
- `test/ts/shouldFail.ts` - Invalid patterns that must fail compilation

### Package Configuration
- `test/ts/package.json` - npm scripts for TypeScript compilation validation
- `test/ts/tsconfig.json` - TypeScript configuration for validation

## Test Files (test/)

### Core Testing
- `test/ash_typescript/codegen_test.exs` - Type generation tests
- `test/ash_typescript/field_parser_comprehensive_test.exs` - Field parser tests
- `test/ash_typescript/embedded_resources_test.exs` - Embedded resource tests

### RPC Testing
- `test/ash_typescript/rpc/rpc_actions_test.exs` - Basic RPC action tests
- `test/ash_typescript/rpc/rpc_field_selection_test.exs` - Field selection tests
- `test/ash_typescript/rpc/rpc_union_field_selection_test.exs` - Union field selection tests
- `test/ash_typescript/rpc/rpc_embedded_calculations_test.exs` - Embedded calculations tests
- `test/ash_typescript/rpc/rpc_multitenancy_*_test.exs` - Multitenancy tests
- `test/ash_typescript/rpc/rpc_union_storage_modes_test.exs` - Union storage mode tests

## Configuration Files

### Environment Configuration
- `config/config.exs` - Main configuration (test environment domain setup)
- `config/test.exs` - Test environment specific configuration
- `mix.exs` - Project dependencies and configuration

### Task Configuration
- `lib/mix/tasks/ash_typescript.ex` - Mix task implementations
- `lib/mix/tasks/ash_typescript/codegen.ex` - Codegen task implementation

## Documentation Files

### AI Assistant Documentation
- `CLAUDE.md` - Main AI assistant guide
- `docs/ai-quick-reference.md` - Quick reference for common tasks
- `docs/ai-implementation-guide.md` - Comprehensive implementation patterns
- `docs/ai-troubleshooting.md` - Debugging and troubleshooting guide
- `docs/ai-validation-safety.md` - Testing and validation procedures

### Organized Documentation (Post-Restructuring)
- `docs/implementation/` - Implementation-specific guides
- `docs/troubleshooting/` - Troubleshooting guides by category
- `docs/insights/` - Implementation insights and patterns
- `docs/quick-guides/` - Task-specific quick guides
- `docs/reference/` - Reference cards and lookup tables
- `docs/legacy/` - Archived legacy documentation

### Generated Documentation
- `documentation/dsls/DSL-AshTypescript.RPC.md` - Auto-generated DSL reference

## Mix Tasks

### Custom Tasks
- `mix test.codegen` - Generate types using test environment (most important)
- `mix ash_typescript.codegen` - Standard codegen task (don't use in dev)

### Standard Tasks
- `mix test` - Run Elixir tests
- `mix format` - Format code
- `mix credo` - Linting
- `mix dialyzer` - Type checking
- `mix docs` - Generate documentation

## Common File Patterns

### When Adding New Type Support
1. Add type mapping to `lib/ash_typescript/codegen.ex:generate_ash_type_alias/1`
2. Add test cases to `test/ash_typescript/codegen_test.exs`
3. Add TypeScript validation to `test/ts/shouldPass.ts`

### When Adding New RPC Features
1. Implement in `lib/ash_typescript/rpc/codegen.ex`
2. Add field processing to `lib/ash_typescript/rpc/field_parser.ex`
3. Add result processing to `lib/ash_typescript/rpc/result_processor.ex`
4. Add tests to `test/ash_typescript/rpc/rpc_*_test.exs`

### When Adding New Embedded Resource Support
1. Update discovery in `lib/ash_typescript/codegen.ex`
2. Add processing in `lib/ash_typescript/rpc/field_parser.ex`
3. Add test resource to `test/support/resources/embedded/`
4. Add test cases to `test/ash_typescript/embedded_resources_test.exs`

## File Search Patterns

### Find Type Generation Logic
```bash
find lib -name "*.ex" -exec grep -l "generate_ash_type_alias" {} \;
find lib -name "*.ex" -exec grep -l "get_ts_type" {} \;
```

### Find RPC Processing Logic
```bash
find lib -name "*.ex" -exec grep -l "process_rpc_action" {} \;
find lib -name "*.ex" -exec grep -l "parse_requested_fields" {} \;
```

### Find Test Examples
```bash
find test -name "*.exs" -exec grep -l "test.codegen" {} \;
find test -name "*.exs" -exec grep -l "RPC" {} \;
```

### Find TypeScript Validation
```bash
find test/ts -name "*.ts" -exec grep -l "shouldPass\|shouldFail" {} \;
```

## Development Hotspots

### Most Modified Files
- `lib/ash_typescript/rpc/field_parser.ex` - Field processing logic
- `lib/ash_typescript/codegen.ex` - Type generation core
- `test/ash_typescript/rpc/rpc_*_test.exs` - RPC functionality tests
- `test/ts/shouldPass.ts` - Type validation patterns

### Files to Check When Things Break
1. `test/support/domain.ex` - Domain configuration
2. `config/config.exs` - Environment setup
3. `lib/ash_typescript/rpc/field_parser.ex` - Field processing
4. `test/ts/generated.ts` - Generated output validation