# File Structure Reference

## Core Library Files

### `lib/ash_typescript.ex`
- Main module entry point
- Currently minimal, just defines module

### `lib/ash_typescript/codegen.ex`
- **Key Functions**:
  - `generate_ash_type_aliases/2`: Base TypeScript type definitions
  - `generate_resource_schemas/1`: Resource interface generation
  - `ash_type_to_typescript/1`: Ash→TypeScript type mapping
- **Purpose**: Core type generation logic

### `lib/ash_typescript/rpc.ex`
- **Key Components**:
  - DSL definition for RPC configuration
  - `@rpc_action` and `@resource` entities
  - Domain extension integration
- **Purpose**: RPC exposure configuration

### `lib/ash_typescript/rpc/codegen.ex`
- **Key Functions**:
  - `generate_typescript_types/2`: Main orchestration
  - RPC client class generation
  - Action method generation
- **Purpose**: RPC client and endpoint generation

### `lib/ash_typescript/filter.ex`
- **Purpose**: Filter query handling utilities
- **Usage**: Converting Ash filters to TypeScript interfaces

### `lib/ash_typescript/helpers.ex`  
- **Purpose**: Shared utility functions
- **Usage**: Common operations across codegen modules

## Mix Tasks

### `lib/mix/tasks/ash_typescript.codegen.ex`
- **Function**: `run/1` - Main CLI entry point
- **Options**: output, check, dry_run, endpoints
- **Purpose**: Command-line interface for type generation

### `lib/mix/tasks/ash_typescript.install.ex`
- **Purpose**: Installation and setup helpers
- **Usage**: Project initialization tasks

## Test Files

### `test/ts_codegen_test.exs`
- **Tests**: Core type generation functionality
- **Resources**: Inline test resource definitions
- **Assertions**: TypeScript output verification

### `test/rpc_test.exs`
- **Tests**: RPC DSL and client generation
- **Coverage**: Domain configuration, action exposure

### `test/ts_filter_test.exs`
- **Tests**: Filter handling and conversion
- **Coverage**: Query parameter generation

### `test/support/todo.ex`
- **Resources**: Full-featured test resources
  - `AshTypescript.Test.User`: Basic user with relationships
  - `AshTypescript.Test.Todo`: Comprehensive todo with all features
  - `AshTypescript.Test.Comment`: Relationship testing
- **Features**: All Ash types, relationships, calculations, aggregates
- **RPC**: Domain with exposed actions

### `test/support/test_app.ex`
- **Purpose**: Test application setup
- **Usage**: Provides application context for tests

## TypeScript Test Files

### `test/ts/generated.ts`
- **Purpose**: Generated TypeScript output from test resources
- **Usage**: Verification of type generation correctness

### `test/ts/typeTests.ts`
- **Purpose**: TypeScript type assertion tests
- **Usage**: Compile-time type verification

### `test/ts/package.json`
- **Scripts**: `compile` - TypeScript compilation verification
- **Dependencies**: TypeScript compiler

## Configuration Files

### `mix.exs`
- **Dependencies**: Ash, AshPhoenix, development tools
- **Aliases**: test.codegen, docs generation
- **Config**: Project metadata and build settings

### `config/config.exs`
- **Purpose**: Application configuration
- **Settings**: Default endpoints, output paths

## Documentation

### `CLAUDE.md`
- **Purpose**: AI assistant instructions and project info
- **Content**: Commands, structure, testing approaches

### `README.md`
- **Purpose**: Public project documentation
- **Usage**: Installation, basic usage examples

### `CHANGELOG.md`
- **Purpose**: Version history and changes
- **Usage**: Release notes and migration info

## Key File Interactions

### Generation Flow
1. `mix ash_typescript.codegen` → `lib/mix/tasks/ash_typescript.codegen.ex`
2. Task calls → `lib/ash_typescript/rpc/codegen.ex`
3. Codegen calls → `lib/ash_typescript/codegen.ex`
4. Output written to configured file

### Test Flow  
1. Tests run → `test/ts_codegen_test.exs`
2. Uses resources from → `test/support/todo.ex`
3. Generates → `test/ts/generated.ts`
4. Verifies compilation → `test/ts/package.json` compile script

### Development Flow
1. Modify resources or codegen logic
2. Run `mix test.codegen` 
3. Verify `test/ts/generated.ts` output
4. Run TypeScript compilation check