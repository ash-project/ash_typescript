<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik

SPDX-License-Identifier: MIT
-->

# Development Workflows

Essential development workflows and patterns for AshTypescript development.

## Prerequisite: the manifest module

Every AshTypescript project must declare a manifest module — codegen and the
runtime RPC pipeline both read all action/resource/type shape from it.

- This repo: `AshTypescript.Test.Manifest`, wired via `config :ash_typescript, manifest: ...`
  in the `Mix.env() == :test` block of `config/config.exs`. This is why dev-env
  codegen fails (see `troubleshooting.md`).
- Tests that define an inline domain need their own scoped manifest:
  `use AshTypescript.Manifest, domains: [MyTest.InlineDomain]`.
- Lookups: `AshTypescript.action_lookup/0`, `resource_lookup/0`, `type_lookup/0`,
  `rpc_action_lookup/0`, `typed_query_lookup/0`. ash_typescript-owned decoration
  lives under `custom.ash_typescript`, read via `AshTypescript.Manifest.Custom`.

## Runtime Introspection with Tidewave MCP

**Use `mcp__tidewave__project_eval` for interactive debugging:**

**Recompile first.** `project_eval` runs against loaded beams — after editing
`lib/`, recompile or you will evaluate stale code.

```elixir
# Explore module exports
mcp__tidewave__project_eval("AshTypescript.Rpc.Pipeline.__info__(:functions)")

# Test functions in context
mcp__tidewave__project_eval("""
fields = ["id", %{"user" => ["name"]}]
AshTypescript.Rpc.RequestedFieldsProcessor.process(
  AshTypescript.Test.Todo, :read, fields
)
""")

# Check configuration
mcp__tidewave__project_eval("Application.get_all_env(:ash_typescript)")
```

Note the `%{...}` map literal — `{"user" => ["name"]}` (no `%`) is a syntax error.
`process/3` still works: its optional 4th argument defaults to the configured
manifest module.

## Development Patterns

### Test-Driven Development
1. Create test showing desired behavior
2. Run test to see failure
3. Implement minimum code to make test pass
4. Refactor if needed

### Type System Changes
1. Write TypeScript validation tests first
2. Generate via `CodegenTestHelper.generate_all_content/0` or `generate_files/0` in test `setup_all`
3. Modify codegen logic
4. Validate generated TypeScript compiles
5. Run full test suite

### RPC Pipeline Changes
1. Test field processing with Tidewave
2. Write integration tests
3. Modify pipeline modules
4. Validate with real data

## Critical Anti-Patterns

- **Don't** use dev environment for AshTypescript commands
- **Don't** skip TypeScript compilation validation
- **Don't** modify multiple stages simultaneously without testing
- **Don't** ignore failing tests in unrelated areas

## Debugging Patterns

### Field Selection Issues
Use Tidewave to test field processing step by step

### Type Generation Issues
Check schema generation with Tidewave before running full codegen

### Performance Issues
Profile specific pipeline stages, not entire system

## Testing Strategies

### Unit Tests
Test individual modules in isolation

### Integration Tests
Test complete pipeline with real data. Use `CodegenTestHelper` to generate through the Orchestrator:
- `generate_all_content/0` — concatenated string for regex assertions
- `generate_files/0` — `%{path => content}` map for file-level assertions
- `generate_controller_content/1` — direct controller codegen with custom options (e.g. specific router)

### TypeScript Tests
Both positive (shouldPass) and negative (shouldFail) patterns.
Ensure we test both http/fetch and channel functions.

These are **type-level only**. After any change to validation-schema codegen,
constraint handling, or `third_party_types`, also run the runtime suites —
they compile *and execute* the generated schemas against fixture inputs and are
the only path that catches runtime schema bugs:

```bash
cd test/ts && npm run testZod && npm run testValibot
# or from the repo root: mix test.test_zod && mix test.test_valibot
```

### Multi-File Codegen Tests
The Orchestrator generates multiple files (types, Zod, RPC, routes, namespace re-exports). When testing:
- Use `generate_files/0` + extractors (`rpc_content/1`, `types_content/1`, etc.) to verify content lands in the correct file
- Use `generate_all_content/0` when you only care that something is generated, not which file it's in

## Extension Points

- **Custom types**: Implement `typescript_type_name/0` callback
- **Field formatters**: Custom formatting in result processor
- **Calculation handlers**: Extend complex calculation support
- **Error handlers**: Custom error formatting
- **Custom fetch functions**: Client-side HTTP customization via `customFetch` parameter
- **Request options**: Client-side request customization via `fetchOptions` parameter

## Documentation Files

### usage-rules.md

**Purpose**: Consumed by AI assistants working in projects that use ash_typescript as a dependency. This file is loaded into their context window to help them understand how to use the library.

**Key Principles**:
- **Compactness is critical** - Every line consumes context window tokens
- Use tables over prose where possible
- Use short code snippets, not full examples
- Avoid redundancy - don't explain the same thing twice
- Use consistent formatting for quick scanning

**Structure**:
| Section | Purpose |
|---------|---------|
| Quick Reference | One-liners for most critical info |
| Essential Syntax Table | Pattern → Syntax → Example (scannable) |
| Action Feature Matrix | Quick lookup table |
| Core Patterns | Minimal code examples |
| Common Gotchas | Error → Fix mappings |
| Error Message Quick Reference | Error text → Solution |
| Configuration Reference | All config options |

**When updating**:
1. Prefer adding to existing tables over new sections
2. Keep code examples minimal (3-10 lines)
3. Remove outdated patterns when adding new ones
4. Test that the file remains under ~500 lines

### agent-docs/ (Internal)

Internal documentation for AI assistants working **on** ash_typescript itself (not consumers). Can be more verbose since it's only loaded when needed.

### documentation/ (User-Facing)

HexDocs documentation for end users. Can include full tutorials, explanations, and comprehensive examples.

## Key Success Factors

1. Always use the test-env aliases (`mix test.codegen`, `mix test`) — do **not**
   prefix with `MIX_ENV=test`; `mix.exs` `preferred_envs` already handles it
2. Validate TypeScript compilation after changes, plus `testZod`/`testValibot`
   when validation schemas are involved
3. Use Tidewave for interactive debugging (recompile first)
4. Write comprehensive tests before implementation
5. Classify every behavior change against
   `agent-plans/release-0.18-intentional-changes.md` — deltas not listed there
   are regressions
