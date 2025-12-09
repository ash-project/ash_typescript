<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik

SPDX-License-Identifier: MIT
-->

# AshTypescript Architecture Changelog

Key architectural decisions and their reasoning for AI assistant context.

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
- `InputFormatter` and `OutputFormatter` now delegate to `ValueFormatter.format/5` with `:input`/`:output` direction
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
- `lib/ash_typescript/codegen/` - 5 focused modules (embedded_scanner, type_aliases, type_mapper, resource_schemas, helpers) + filter_types
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