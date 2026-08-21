<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik

SPDX-License-Identifier: MIT
-->

# TypeScript Testing and Validation

Comprehensive guide for testing organization and validation procedures for maintaining system stability.

## Test Structure

`test/ts/` holds four kinds of file. Don't rely on a hand-maintained tree —
list them (`ls test/ts/shouldPass/*.ts`); the set grows regularly.

| Kind | Files |
|------|-------|
| **Type-level entry points** | `shouldPass.ts` (~38 files in `shouldPass/`), `shouldFail.ts` (~15 files in `shouldFail/`) |
| **Runtime entry points** | `runZodTests.ts`, `runValibotTests.ts` (compiled *and executed*) |
| **Generated artifacts** | `generated.ts`, `ash_types.ts`, `ash_zod.ts`, `ash_valibot.ts`, `generated_routes.ts`, `generated_typed_channels.ts`, `MANIFEST.md`, `ash_rpc_manifest.json`, `namespace/`, `account.ts`, `auth.ts` |
| **Hand-written support** | `customTypes.ts`, `rpcHooks.ts`, `channelHooks.ts`, `routeHooks.ts` |

`shouldPass/` covers CRUD, calculations, relationships, custom types, embedded
resources, unions, typed maps/structs, keyword/tuple, aggregates, pagination,
sorting, load restrictions, metadata, identities, channels, and lifecycle hooks.
`shouldFail/` mirrors these with `@ts-expect-error` negative cases.

## Testing Commands

```bash
# Generate and validate TypeScript
mix test.codegen
cd test/ts && npm run compileGenerated

# Test usage patterns (type-level only)
npm run compileShouldPass     # Valid patterns (must pass)
npm run compileShouldFail     # Invalid patterns (must fail)

# Execute generated validation schemas against fixture data
npm run testZod
npm run testValibot

# Run Elixir tests (do NOT prefix with MIX_ENV=test)
mix test
```

`testZod`/`testValibot` are the **only** path that exercises schema runtime
behavior. Always run them after touching `third_party_types`, constraint
generation, or any other validation codegen. Root-level equivalents:
`mix test.test_zod`, `mix test.test_valibot`.

## Test Categories

Representative files (not exhaustive — `ls` the directories for the full set):

### Valid Usage Tests (shouldPass/)
- **operations.ts**: Basic CRUD with field selection
- **calculations.ts**: Self calculations with arguments and nesting
- **relationships.ts**: Calculation field selection with relationships
- **customTypes.ts**: Custom type field selection and input validation
- **embeddedResources.ts**: Embedded resource field selection and calculations
- **unionTypes.ts**: Union field selection and array unions
- **typedMaps.ts** / **typedStructs.ts**: Typed-container nested selection
- **complexScenarios.ts**: Multi-feature combination tests

### Invalid Usage Tests (shouldFail/)
- **invalidFields.ts**: Non-existent fields and invalid relationships
- **invalidCalcArgs.ts**: Wrong argument types and missing required args
- **invalidStructure.ts**: Invalid nesting and missing properties
- **typeMismatches.ts**: Wrong type assignments and invalid field access
- **unionValidation.ts**: Invalid union field syntax
- **loadRestrictions.ts**: Fields excluded by `allowed_loads`/`denied_loads`

## Critical Safety Principles

1. **Never Skip TypeScript Validation** - Always run TypeScript compilation after changes
2. **Test Multi-Layered System** - Validate Elixir backend, TypeScript frontend, and type inference
3. **Classify Every Behavior Change** - Deltas not listed in
   `agent-plans/release-0.18-intentional-changes.md` are regressions

## Pre-Change Baseline Checks

Run these before making changes to establish working baseline:

```bash
mix test                              # All Elixir tests passing
mix test.codegen                      # TypeScript generation successful
cd test/ts && npm run compileGenerated # Generated TypeScript compiles
cd test/ts && npm run compileShouldPass # Valid patterns work
cd test/ts && npm run compileShouldFail # Invalid patterns rejected
cd test/ts && npm run testZod          # Zod schemas execute against fixtures
cd test/ts && npm run testValibot      # Valibot schemas execute against fixtures
```

**If any baseline check fails, STOP and fix before proceeding.**

## Change-Specific Validations

### Typed Controller Changes
When modifying `lib/ash_typescript/typed_controller/` modules:

```bash
# Codegen output validation
mix test test/ash_typescript/typed_controller/codegen_test.exs

# Request handler (argument extraction, casting, validation, dispatch)
mix test test/ash_typescript/typed_controller/request_handler_test.exs

# Router matching and multi-mount
mix test test/ash_typescript/typed_controller/router_introspection_test.exs

# Compile-time verification (unique names, valid types, TS name validation)
mix test test/ash_typescript/typed_controller/verify_typed_controller_test.exs

# Namespace grouping and re-exports
mix test test/ash_typescript/typed_controller/namespace_test.exs

# Base path prefixing
mix test test/ash_typescript/typed_controller/base_path_test.exs

# Full typed controller test suite
mix test test/ash_typescript/typed_controller/

# Validate generated routes compile
mix test.codegen
cd test/ts && npm run compileGenerated
```

**Key test fixtures:**
- `test/support/resources/session.ex` — test typed controller module
- `test/support/routes_test_router.ex` — single-mount and multi-mount test routers
- `test/ts/generated_routes.ts` — generated output for TS compilation validation

**Argument semantics (0.18 / B11):** route arguments follow Ash action-argument
semantics end to end. Constraints are validated and folded at compile time by
`typed_controller/transformers/fold_argument_constraints.ex` (invalid constraints
are now compile errors), the handler runs `cast_input` → `apply_constraints` →
`allow_nil?` recheck, and route Zod fields compose through the same
`SchemaCore.compose_input_field/5` as RPC action inputs. When changing any of
these, also run `npm run testZod` / `npm run testValibot`.

### Type System Changes
When modifying `lib/ash_typescript/codegen/` modules (type_mapper.ex, resource_schemas.ex, etc.) or `lib/ash_typescript/rpc/codegen.ex`:

```bash
# Full type generation testing
mix test test/ash_typescript/typescript_codegen_test.exs
mix test test/ash_typescript/codegen/
mix test test/ash_typescript/manifest/
mix test test/ash_typescript/rpc/codegen_determinism_test.exs
```

**Unmapped types are a compile-time error now** — don't grep generated output
for `any`. The `VerifyMappableTypes` manifest verifier
(`lib/ash_typescript/manifest/verifiers/verify_mappable_types.ex`) aggregates
every unmappable reachable type into one `DslError`, and `TypeMapper` raises
`unsupported type ... AshTypescript cannot map it to a TypeScript type.` as a
backstop. Remaining `any`s are deliberate (`:term`, File/Function, module-less
unknowns). To audit them: `grep -c ': any' test/ts/ash_types.ts`.

Note `mix test.codegen --dry-run` only prints files whose content **differs**
from disk — it is silent when generated output is already current, so it is not
a usable inspection tool on a clean tree.

### Runtime Logic Changes
When modifying RPC pipeline modules:

```bash
# Field selection validation
mix test test/ash_typescript/rpc/calculation_field_selection_test.exs

# Core RPC functionality (critical)
mix test test/ash_typescript/rpc/rpc_run_action_*_test.exs
```

### Calculation System Changes
When modifying calculation parsing or field selection:

```bash
# Test all calculation scenarios
mix test test/ash_typescript/rpc/calculations_test.exs
```

## Breaking Change Detection

Codegen emits ~10 artifacts, so a `generated.ts`-only diff misses most changes
(`ash_types.ts`, `ash_zod.ts`, `ash_valibot.ts`, `ash_rpc_manifest.json`, …).
Snapshot the whole tree to a scratch dir **outside the repo** — a stray `.ts`
inside `test/ts/` fails the reuse lint.

```bash
# Before changes
mix test.codegen
cp -r test/ts /tmp/ts_before

# After changes
mix test.codegen
diff -ru /tmp/ts_before test/ts --exclude=node_modules --exclude='*.js'
```

Look for: removed properties, changed types, new required properties.
Expect benign noise — field order is alphabetical and manifest-derived
(see `agent-plans/release-0.18-intentional-changes.md` §4) — and classify every
remaining hunk against that ledger before calling it a regression.

## Adding New Tests

1. **For valid patterns**: Add to appropriate shouldPass/ file
2. **For invalid patterns**: Add to appropriate shouldFail/ file with `@ts-expect-error`
3. **New categories**: Create new files and update entry points
4. **Include comments**: Explain what should pass/fail and why

**Use regex for structure validation, not String.contains?**

No ExUnit tag exclusions are configured (`test/test_helper.exs` has no
`ExUnit.configure(exclude: ...)`) — tests that trigger compile-time warnings run
in CI and assert on warning bodies.

### Tests That Define Their Own Domain

Codegen and the runtime pipeline read everything from a manifest module, so a
test that defines an inline domain needs a scoped manifest rather than the
app-wide `AshTypescript.Test.Manifest`:

```elixir
defmodule MyTest.InlineManifest do
  use AshTypescript.Manifest, domains: [MyTest.InlineDomain]
end
```

Pass it explicitly where an API accepts one — e.g.
`RequestedFieldsProcessor.process/4`'s 4th argument (defaults to the configured
production manifest module) or `AshTypescript.Manifest.verify_for_domains/1`.
See `test/ash_typescript/manifest/` for worked examples.

## Asserting on Generated TypeScript in Elixir Tests

**CRITICAL: Never read from `test/ts/generated.ts` in tests.** This file may be stale or out of sync with the current codebase. Instead, generate the TypeScript programmatically and assert on the resulting string.

### Correct Pattern — CodegenTestHelper

Use `AshTypescript.Test.CodegenTestHelper` which wraps the multi-file `Orchestrator`:

```elixir
defmodule AshTypescript.Rpc.MyFeatureTest do
  use ExUnit.Case, async: true

  setup_all do
    # Generate all files and concatenate — ensures fresh output through Orchestrator
    {:ok, generated_content} =
      AshTypescript.Test.CodegenTestHelper.generate_all_content()

    {:ok, generated: generated_content}
  end

  describe "TypeScript codegen" do
    test "generates correct type for my feature", %{generated: generated} do
      assert generated =~ ~r/function myAction.*input: MyInput/s
    end
  end
end
```

### When to Use `generate_files/0` Instead

Use `generate_files/0` when you need to inspect specific files (e.g., check that a type lands in the correct output file):

```elixir
setup_all do
  {:ok, files} = AshTypescript.Test.CodegenTestHelper.generate_files()
  {:ok, files: files}
end

test "routes go to routes file", %{files: files} do
  routes = AshTypescript.Test.CodegenTestHelper.routes_content(files)
  assert routes =~ "authPath"
end
```

Helper extractors: `rpc_content/1`, `types_content/1`, `zod_content/1`, `routes_content/1`.

For typed controller tests that need custom router options, use `generate_controller_content/1`:

```elixir
{:ok, content} =
  AshTypescript.Test.CodegenTestHelper.generate_controller_content(
    router: MyCustomRouter
  )
```

### Why This Matters

1. **Test Isolation**: Tests don't depend on external file state
2. **Reproducibility**: Tests always use freshly generated output via the Orchestrator
3. **CI Reliability**: No need to ensure generated files are up-to-date before running tests
4. **Multi-file Aware**: Tests work with the orchestrated multi-file output, not a single monolithic file
5. **Accurate Results**: Assertions reflect current codegen behavior, not cached output

### Anti-Pattern (Do NOT Do This)

```elixir
# BAD - Reading from file that may be stale
test "my feature generates correctly" do
  generated = File.read!("test/ts/generated.ts")  # WRONG!
  assert generated =~ "myFunction"
end
```

### Reference Examples

See these test files for the correct pattern:
- `test/ash_typescript/rpc/rpc_function_generation_mapped_fields_test.exs`
- `test/ash_typescript/rpc/rpc_identities_test.exs`
- `test/ash_typescript/rpc/rpc_composite_primary_key_test.exs`
- `test/ash_typescript/typed_controller/namespace_test.exs` (file-level assertions)

## Testing Unconstrained Maps

When testing actions with unconstrained map inputs or outputs, follow these specific patterns.
The TypeScript below is illustrative shape-only pseudo-code — for real, compiling
cases see `test/ts/shouldPass/untypedMaps.ts`.

### Valid Patterns (shouldPass/)
```typescript
// Test unconstrained map input - any structure allowed
const result = await processRawData({
  input: {
    rawData: {
      user_name: "john",        // snake_case preserved
      created_at: "2024-01-01", // No camelCase conversion
      nested_data: { arbitrary: "structure" },
      arrays: [1, 2, 3],
      booleans: true
    } as Record<string, any>
  }
  // Note: no fields parameter for unconstrained outputs
});

// Verify result structure - result.data is Record<string, any>
if (result.success) {
  // Field names should be preserved as-is from Elixir
  const userData = result.data.user_name;  // snake_case access
  const createdAt = result.data.created_at;
}
```

### Testing Guidelines for Unconstrained Maps

1. **Input Validation**: Test with various arbitrary map structures
   - Nested objects with mixed field name conventions
   - Arrays, primitives, and complex structures
   - Snake_case and camelCase field names

2. **Output Validation**: Verify entire map is returned
   - No field selection processing applied
   - Original field names preserved from Elixir
   - Complete data structure returned

3. **Type Safety**: Ensure TypeScript compilation
   - `Record<string, any>` types used for unconstrained maps
   - No type errors for arbitrary structures
   - Proper function signature (no fields parameter for outputs)

4. **Field Name Preservation**: Critical test case
   - Input: snake_case field names passed through unchanged
   - Output: Elixir field names returned without camelCase conversion

### Elixir Test Patterns

Two things to get right in RPC-level tests:

- **There is no `"resource"` param.** `Pipeline.discover_action/2` dispatches on
  `params["action"]` (or `params["typed_query_action"]`) alone — RPC action
  names are globally unique entrypoints resolved through
  `AshTypescript.rpc_action_lookup/0`.
- **The second argument must be a `%Plug.Conn{}` or `%Phoenix.Socket{}.`**
  Passing a bare `%{}` raises `CaseClauseError`.

```elixir
test "runs an action through the full pipeline" do
  conn = %Plug.Conn{} |> Plug.Conn.put_private(:ash, %{actor: nil, tenant: nil})

  params = %{
    "action" => "list_todos",
    "fields" => ["id", "title"]
  }

  result = AshTypescript.Rpc.run_action(:ash_typescript, conn, params)

  assert result["success"] == true
  assert is_list(result["data"])
end

# Inspecting a single stage instead of the whole pipeline
{:ok, request} =
  AshTypescript.Rpc.Pipeline.parse_request(:ash_typescript, %Plug.Conn{}, params)
```

For unconstrained/untyped map coverage, follow the existing suites rather than
inventing fixtures:
- `test/ash_typescript/rpc/rpc_run_action_untyped_maps_test.exs`
- `test/ts/shouldPass/untypedMaps.ts`

## Final Validation Checklist

- [ ] `mix test` - All Elixir tests pass
- [ ] `mix test.codegen` - TypeScript generates without errors
- [ ] `cd test/ts && npm run compileGenerated` - Generated TypeScript compiles
- [ ] `cd test/ts && npm run compileShouldPass` - Valid patterns work
- [ ] `cd test/ts && npm run compileShouldFail` - Invalid patterns fail correctly
- [ ] `cd test/ts && npm run testZod` - Zod schemas execute against fixtures
- [ ] `cd test/ts && npm run testValibot` - Valibot schemas execute against fixtures
- [ ] `mix format --check-formatted` - Code formatting maintained
- [ ] `mix credo --strict` - No linting issues
- [ ] Every generated-output delta classified against `agent-plans/release-0.18-intentional-changes.md`