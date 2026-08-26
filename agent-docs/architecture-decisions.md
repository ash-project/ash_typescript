<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik

SPDX-License-Identifier: MIT
-->

# AshTypescript Architecture Changelog

Key architectural decisions and their reasoning for AI assistant context.

## 2026-08: 0.18 Release Hardening

**Change**: Post-migration correctness work landed while preparing 0.18 — compile-dependency wiring for the manifest module, a compile-time unmappable-type verifier, and unification of typed-controller argument semantics with Ash.
**Why**: The manifest migration left three gaps: the manifest module had no compile dependency on domains (stale codegen on incremental compiles), unmappable types degraded to `any` instead of failing loudly, and the TypedController DSL mimicked Ash's `argument` syntax without reusing its semantics.
**Impact**:
- **Manifest compile dependencies**: `AshTypescript.Manifest.handle_opts/1` injects static stubs into the using module — `Application.compile_env(otp_app, :ash_domains, [])` (skipped for scoped `domains:` manifests) plus one `Domain.module_info(:md5)` remote call per domain. Resource edit → domain recompiles → manifest recompiles, so `mix test.codegen` and the dev-time RPC pipeline are never stale. (`__mix_recompile__?/0` was rejected: Mix evaluates it against pre-compile beams, so a module-vsn hash lags one compile behind.)
- **Unmappable types are a compile-time error again**: new `VerifyMappableTypes` manifest verifier walks every reachable type and aggregates all offenders into one `DslError`. The accept-list lives in `TypeMapper.unknown_module_mapping/1` (single source of truth shared with `map_type/3` and `TypeAliases`); `TypeMapper`'s silent `"any"` fallbacks are replaced with a backstop `raise "unsupported type ..."`.
- **Typed-controller arguments follow Ash action-argument semantics end-to-end**: `FoldArgumentConstraints` transformer validates+folds argument constraints against `Ash.Type.constraints/1` at compile time (invalid constraints are now compile errors); the request handler runs `cast_input` → `apply_constraints` → `allow_nil?` recheck; route Zod fields compose through the same shared `SchemaCore.compose_input_field/5` as RPC action inputs.
- **Non-empty string enforcement is constraint-driven**: a string gets an effective `min(1)`/`minLength(1)` iff its folded constraints carry `allow_empty?: false`, via shared `SchemaCore.effective_min_length/2` — applied uniformly, including nested typed-container fields.
- **Scoped-manifest resolution threaded through field processing**: `Custom.resolve_resource/2` plus `manifest` params on `Atomizer`/`FieldSelector`, so verifiers running against an inline test manifest resolve resources correctly.
- **Non-RPC-references warning regained attribution**: each warned module lists its one-hop referencers (`Referenced by: - MyApp.Todo (relationship :thing)`).
- **`otp_app` is no longer a discovery scope (documented, not removed)**: the manifest migration replaced `Ash.Info.domains(otp_app)` discovery with a lookup against the single configured manifest, and `Rpc.find_typed_query/2` — the last holdout still walking `Ash.Info.domains(otp_app)` — was converted too. The `otp_app` argument on `run_action/3`, `validate_action/3`, `run_typed_query/4` and `Pipeline.parse_request/4` is therefore inert for resolution; it is **retained deliberately for API compatibility** and its docs now say so. Consequence: one manifest per BEAM node, so a repo of several Elixir apps cannot yet generate independent clients (all ash_typescript config is single-valued under `:ash_typescript`). The supported multi-app shape today is one *merged* manifest via `use AshTypescript.Manifest, otp_app: :x, domains: [AppA.Domain, AppB.Domain]`. Do not reintroduce partial `otp_app` scoping — an argument that reads like a boundary but only scopes some lookups is worse than one that scopes none. If independent per-app clients are wanted, the scope key should be the manifest module with its own config namespace.
**Key Files**: `lib/ash_typescript/manifest.ex` (`handle_opts/1`), `lib/ash_typescript/manifest/verifiers/verify_mappable_types.ex`, `lib/ash_typescript/codegen/type_mapper.ex` (`unknown_module_mapping/1`), `lib/ash_typescript/typed_controller/transformers/fold_argument_constraints.ex`, `lib/ash_typescript/typed_controller/request_handler.ex`, `lib/ash_typescript/codegen/schema_core.ex` (`compose_input_field/5`, `effective_min_length/2`), `lib/ash_typescript/manifest/custom.ex` (`resolve_resource/2`)

## 2026-07: Ash.Info.Manifest as Single Source of Truth

**Change**: Migrated the codegen and runtime pipelines off ad-hoc `Ash.Resource.Info` introspection and onto a unified, precomputed `Ash.Info.Manifest` (Ash core), read through a required per-app manifest module.
**Why**: Runtime spec building walked Spark DSL state on every request and scattered `Ash.Resource.Info` calls across dozens of modules. A single manifest, built once at compile time and decorated with ash_typescript-specific data, gives O(1) map reads, one place for name-mapping/type resolution, and correct multi-domain merging (a resource in several `typescript_rpc` blocks unifies its actions instead of clobbering).
**Impact** (⚠️ **breaking** — requires consumer migration):
- **New required config + module**: every project must declare `config :ash_typescript, manifest: MyApp.AshTypescriptManifest` and define `defmodule MyApp.AshTypescriptManifest do use AshTypescript.Manifest, otp_app: :my_app end`. `AshTypescript.manifest_module/0` raises with setup instructions if unset.
- **Ash floor raised** to `~> 3.27` (lock at 3.32.0); `Ash.Info.Manifest` is the backbone. Note the new systemic coupling: filter operators, `required?`, aggregate nullability, sortable flags, and embedded-resource placement all come from ash's manifest generator — an ash bump alone can change generated TypeScript.
- **Custom decoration**: ash_typescript-owned data (name mappings, `type_name`, exposed metadata, bulk auth strategy) is persisted under `custom.ash_typescript` on the manifest and read via `AshTypescript.Manifest.Custom` accessors — runtime never re-walks DSL state.
- **O(1) entrypoint lookups**: `AshTypescript.action_lookup/0`, `resource_lookup/0`, `type_lookup/0`, `rpc_action_lookup/0`, `typed_query_lookup/0` back both codegen and the runtime pipeline.
- **Verifiers split**: RPC-extension verifiers moved to `lib/ash_typescript/manifest/verifiers/`; resource-scoped name/type verifiers remain in `lib/ash_typescript/resource/verifiers/`. They now run **when the manifest module compiles, not when the domain compiles** — error/warning site and timing changed, and the 7 old `AshTypescript.Rpc.Verifier*` modules no longer exist. RPC-config warnings likewise emit once at manifest-module compile and are no longer re-printed by `mix ash_typescript.codegen`.
- **Reachability** moved to `Ash.Info.Manifest.Generator.Reachability` (ash core).
**Behavioral notes**: generated TypeScript is **not** 1:1 with 0.17.3. The manifest now drives filter/sort operators, `required?`, aggregate nullability, and struct-calc classification, so the output changed in several places (filter operator sets, optional update `input?:`, `T | null` aggregates, `__type: "Relationship"` for struct-returning calcs, TypedMap `__primitiveFields` tightening, Zod/Valibot structural schemas). Field ordering also became alphabetical throughout. Confirm any codegen or runtime diff against these known changes before treating it as a regression.
**Key Files**: `lib/ash_typescript/manifest.ex` (Spark DSL module), `lib/ash_typescript/manifest/custom.ex` (accessors), `lib/ash_typescript/manifest/decorator.ex` + `transformers/` (decoration), `lib/ash_typescript/manifest/verifiers/`, `lib/ash_typescript/rpc/codegen/helpers/action_introspection.ex`
**Note**: The installer (`mix ash_typescript.install`) scaffolds the manifest module (`MyApp.AshTypescriptManifest` at `lib/my_app/ash_typescript_manifest.ex`) and sets the `manifest:` config automatically — see `create_manifest_module/2` and `add_ash_typescript_config/1` in `lib/mix/tasks/ash_typescript.install.ex`.

## 2026-02: Multi-File Orchestrator and DSL Enhancements

**Change**: Unified multi-file codegen orchestration, HTTP verb shortcuts for TypedController DSL, controller namespace support, and shared ImportResolver
**Why**: Simplify codegen coordination, improve DSL ergonomics, and enable route namespacing
**Impact**:
- **Orchestrator** (`codegen/orchestrator.ex`) now coordinates all file generation in a single pass, replacing the previous sequential approach in the mix task. It emits types, Zod, Valibot, RPC, routes, typed channels, the Markdown + JSON manifests, and namespace re-exports
- **HTTP verb shortcuts**: `get :auth do`, `post :login do` etc. — cleaner syntax using Spark `auto_set_fields`. Positional method arg also supported: `route :auth, :post do`. Default method is `:get` when omitted.
- **Controller namespaces**: `namespace "auth"` at controller and route level, with route-level overriding controller-level. Generates `namespace/*.ts` re-export files.
- **ImportResolver** extracted as shared utility for import path resolution and namespace re-export generation (used by both RPC and controller codegen)
- **RouteConfigCollector** discovers typed controllers from config and resolves namespace precedence
- **CodegenTestHelper** wraps orchestrator for tests — `generate_all_content/0` and `generate_files/0`
- **RPC codegen** reduced to focused content generation; no longer responsible for monolithic output
**Key Commits**:
- `0077ef2` feat: add HTTP verb shortcuts and positional method arg to typed controller DSL
- `47a14bc` feat: add controller namespace support and simplify codegen orchestration
- `5d3c885` refactor: remove monolithic codegen and reduce public API
- `c97a05d` refactor: extract namespace reexport and import helpers into ImportResolver
- `097f4e7` test: add CodegenTestHelper and update all tests for orchestrator
**Key Files**: `lib/ash_typescript/codegen/orchestrator.ex`, `lib/ash_typescript/codegen/import_resolver.ex`, `lib/ash_typescript/typed_controller/dsl.ex`, `lib/ash_typescript/typed_controller/codegen/route_config_collector.ex`, `test/support/codegen_test_helper.ex`

## 2026-02: Typed Controller Feature Completion

**Change**: Added GET query parameter support, paths-only mode, and compile-time name validation for TypedController
**Why**: Complete the TypedController feature set to match RPC pipeline maturity
**Impact**:
- GET routes with arguments now generate query parameter path helpers using `URLSearchParams`
- `typed_controller_mode: :paths_only` config option generates only path helpers (no fetch functions)
- Route and argument names validated for TypeScript compatibility at compile time (reuses `AshTypescript.NameValidation.invalid_name?/1`)
- Path parameters validated at codegen time — every `:param` in router paths must have a matching DSL argument
**Key Commits**:
- `6669e22` feat: generate query params and typed path helpers
- `f4d790b` feat: add typed_controller_mode config for paths_only generation
- `cb56218` feat: validate route and argument names for TypeScript compatibility
- `d5ff7e9` feat: validate that path params have matching DSL arguments
**Key Files**: `lib/ash_typescript/typed_controller/codegen/route_renderer.ex`, `lib/ash_typescript/typed_controller/verifiers/verify_typed_controller.ex`

## 2026-01: TypedController — Standalone Spark DSL for Controller Routes

**Change**: Added `AshTypescript.TypedController` as a standalone Spark DSL that generates Phoenix controllers and TypeScript route helpers
**Why**: Need type-safe route helpers for controller-style actions (Inertia renders, redirects, OAuth flows) that don't fit the RPC pipeline pattern
**Impact**: Three-layer architecture (DSL → Generation → Rendering), compile-time controller module generation via `Module.create/3`, runtime request handling with type casting and validation
**Key Commit**: `546a15e` feat: add TypedController as standalone Spark DSL
**Key Files**: `lib/ash_typescript/typed_controller/`, `lib/ash_typescript/typed_controller/codegen/`
**Design Decision**: Completely independent from `Ash.Resource` — uses Spark DSL directly with colocated arguments and handler functions. Generated controllers delegate to `RequestHandler.handle/4` for consistent param processing.

## 2025-12-08: Field Processing and Formatting Architecture Simplification

**Change**: Unified type-driven dispatch pattern for field processing and value formatting
**Why**: Simplify the 11-module field processing system to a cleaner 3-module architecture; eliminate formatter_core.ex duplication
**Impact**:
- Field processing: 11 modules → 3 modules (`Atomizer`, `FieldSelector`, `FieldSelector.Validation`)
- Value formatting: Merged `formatter_core.ex` into unified `ValueFormatter` with direction parameter
- Both `FieldSelector` and `ValueFormatter` now use identical `{type, constraints}` dispatch pattern
**Key Changes**:
- Deleted: `formatter_core.ex`, `field_classifier.ex`, `field_processor.ex`, `validator.ex`, `utilities.ex`, 6 type processors
- Created: `value_formatter.ex` (unified formatting), `field_selector.ex` (unified field selection)
- `InputFormatter` and `OutputFormatter` now delegate to `ValueFormatter.format/6` (`value, type, constraints, formatter, direction, resource_lookups`) with `:input`/`:output` direction; the arity-7 head adds an optional `type_index`
**Benefits**: Single dispatch pattern across codebase, easier to reason about, fewer files to maintain

## 2025-11-07: Comprehensive Codebase Refactoring

**Change**: Major refactoring to eliminate code duplication and improve organization
**Why**: Reduce maintenance burden, improve discoverability, eliminate ~300 lines of duplicate code
**Impact**:
- `codegen.ex`: 1,539 → 64 lines (96% reduction, now a delegator)
- `requested_fields_processor.ex`: 1,289 → 68 lines (95% reduction, now a delegator)
- Type introspection: 89 scattered usages → 1 centralized module
- Formatters: 626 LOC with 70% duplication → 303 LOC + 430 shared core
- Verifiers: Moved to `resource/verifiers/` for consistent directory structure
- Filter types: Moved from top-level to `codegen/filter_types.ex` for logical grouping
**Key Modules Created**:
- `lib/ash_typescript/type_system/introspection.ex` - Centralized type introspection
- `lib/ash_typescript/codegen/` - focused modules (type_discovery, type_aliases, type_mapper, resource_schemas, helpers, schema_core, schema_formatter, filter_types); reachability in `Ash.Info.Manifest.Generator.Reachability` (ash core)
- `lib/ash_typescript/rpc/value_formatter.ex` - Unified type-aware value formatting
- `lib/ash_typescript/rpc/field_processing/` - 3 specialized modules (atomizer, field_selector, field_selector/validation)
- `lib/ash_typescript/resource/verifiers/` - Organized verifier modules
**Benefits**: Single source of truth, better separation of concerns, improved maintainability, zero breaking changes

## 2025-09-16: Phoenix Channel RPC Actions

**Change**: Added Phoenix channel-based RPC action generation alongside HTTP-based functions
**Why**: Enable real-time applications to use the same type-safe RPC system over WebSocket connections
**Impact**: Optional feature that generates channel functions with identical pipeline integration and type safety
**Configuration**: `generate_phx_channel_rpc_actions: true` enables generation of functions with `Channel` suffix
**Key Files**: `lib/ash_typescript/rpc.ex` (config functions), `lib/ash_typescript/rpc/codegen.ex` (generation logic)
**Design Decision**: Additive approach - channel functions generated alongside, not instead of, HTTP functions for maximum flexibility

## 2025-08-19: Unified Schema Architecture

**Change**: Complete refactoring from multiple separate schemas to unified metadata-driven schema generation
**Why**: Previous system used separate schemas creating complex TypeScript inference and maintenance overhead
**Impact**: Single ResourceSchema per resource with `__type` metadata enables simpler, more predictable type inference
**Key Files**: `lib/ash_typescript/codegen.ex`, `lib/ash_typescript/rpc/codegen.ex`

## 2025-08-01: RPC Pipeline Complete Rewrite

**Change**: Complete rewrite from three-stage to four-stage architecture
**Why**: Performance issues, unclear separation of concerns, difficult debugging
**Impact**: 50%+ performance improvement, clean separation, fail-fast validation
**Pipeline Stages**: parse_request → execute_ash_action → process_result → format_output
**Key Files**: `lib/ash_typescript/rpc/pipeline.ex`, `lib/ash_typescript/rpc/requested_fields_processor.ex`

## 2025-08-01: Tidewave MCP Integration

**Change**: Enabled Tidewave MCP server for runtime introspection
**Why**: Traditional shell debugging was inefficient for exploring runtime behavior
**Impact**: Real-time Elixir evaluation, faster debugging, interactive development
**Tools**: Use `mcp__tidewave__project_eval` for runtime evaluation

## 2025-07-17: RPC Headers Support

**Change**: Added optional headers parameter to all RPC config types
**Why**: Hardcoded CSRF token functionality wasn't suitable for all authentication setups
**Impact**: All RPC functions accept custom headers while maintaining backward compatibility

## 2025-07-16: Union Storage Mode Unification

**Change**: Unified `:map_with_tag` and `:type_and_value` union storage modes
**Why**: `:map_with_tag` unions were failing creation due to complex field constraints
**Impact**: Both union storage modes work identically
**Insight**: Simple union definitions without complex constraints required for `:map_with_tag`

## 2025-07-15: Type Inference System Overhaul

**Change**: Implemented schema key-based field classification system
**Why**: System incorrectly assumed all complex calculations return resources
**Impact**: System correctly detects calculation return types, only adds `fields` when needed
**Insight**: Schema keys eliminate field type ambiguity through direct key lookup

## 2025-07-15: Unified Field Format

**Change**: Removed backwards compatibility for `calculations` parameter
**Why**: Dual processing paths added complexity
**Impact**: Single processing path with unified field format
**Insight**: Single source of truth for field specifications is more maintainable

## 2025-07-15: Embedded Resources Support

**Change**: Complete TypeScript support for embedded resources with relationship-like architecture
**Why**: Embedded resources needed full type safety and field selection capabilities
**Impact**: Embedded resources work exactly like relationships with unified object notation
**Insight**: Dual-nature processing (attributes + calculations) requires three-stage pipeline