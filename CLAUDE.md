# AshTypescript Project Information

## Project Overview
AshTypescript is a library for generating TypeScript types and RPC clients from Ash resources and actions. It provides automatic TypeScript type generation for Ash APIs, ensuring type safety between Elixir backend and TypeScript frontend.

## Key Commands
- `mix ash_typescript.codegen` - Generate TypeScript types and RPC clients
- `mix test.codegen` - Alias for running codegen (defined in mix.exs)
- `mix docs` - Generate documentation with Spark integration
- `mix sync_usage_rules` - Sync usage rules to CLAUDE.md

## Project Structure
- `lib/ash_typescript/` - Core library modules
  - `codegen.ex` - Main code generation logic
  - `rpc.ex` - RPC extension for Ash domains
  - `rpc/codegen.ex` - RPC-specific code generation
  - `filter.ex` - Filter handling utilities
  - `helpers.ex` - Utility functions
- `lib/mix/tasks/` - Mix tasks
  - `ash_typescript.codegen.ex` - Main codegen task
  - `ash_typescript.install.ex` - Installation task
- `test/support/todo.ex` - Comprehensive test resource with examples of:
  - Resource definitions with various attribute types
  - Relationships and aggregates
  - Custom actions and calculations
  - RPC configuration

## Testing
- Main test files: `rpc_test.exs`, `ts_codegen_test.exs`, `ts_filter_test.exs`
- TypeScript tests in `test/ts/` with generated output verification
- To check for errors in the generated typescript file, run `npm run compile` from the `test/ts`-folder
- Test resources include Todo, User, Comment with full CRUD and custom actions

## Configuration
Default config locations:
- Output file: `assets/js/ash_rpc.ts`
- RPC endpoints: `/rpc/run`, `/rpc/validate`

## Dependencies
- Ash ~> 3.5 (core framework)
- AshPhoenix ~> 2.0 (for RPC endpoints)
- Sourceror (for AST manipulation)
- Igniter (for code generation tooling)

<!-- usage-rules-start -->
<!-- igniter-start -->
## igniter usage
@deps/igniter/usage-rules.md
<!-- igniter-end -->
<!-- ash-start -->
## ash usage
@deps/ash/usage-rules.md
<!-- ash-end -->
<!-- ash_phoenix-start -->
## ash_phoenix usage
@deps/ash_phoenix/usage-rules.md
<!-- ash_phoenix-end -->
<!-- usage-rules-end -->
