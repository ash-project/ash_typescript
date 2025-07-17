# AshTypescript AI Assistant Changelog

## Overview

This changelog provides context for the current state of the project and tracks the evolution of implementation approaches. It helps AI assistants understand why certain patterns exist and the reasoning behind architectural decisions.

## Entry Format

Each entry includes:
- **Date**: When the change was made
- **Change**: What was modified/added/removed
- **Context**: Why the change was necessary
- **Files**: Which files were affected
- **Impact**: How this affects future development
- **Key Insights**: Lessons learned or patterns discovered

## Entry Guidelines

### What to Include
- **Major architectural decisions** and their reasoning
- **Pattern changes** that affect how code should be written
- **Critical bug fixes** and their root causes
- **Performance improvements** and optimization strategies
- **Breaking changes** and migration strategies
- **Documentation restructuring** and new workflows
- **Tool or dependency changes** and their impact

### What to Exclude
- **Routine maintenance** without architectural impact
- **Minor bug fixes** that don't reveal patterns
- **Cosmetic changes** without functional impact
- **Experimental changes** that were reverted
- **Personal preferences** without project-wide impact

### Writing Style
- **Be concise** but provide enough context
- **Focus on reasoning** rather than just what changed
- **Include file references** for easy navigation
- **Highlight patterns** that apply to future work
- **Use present tense** for current state descriptions
- **Use past tense** for completed changes

### Update Frequency
- **After significant changes** that affect how work is done
- **When new patterns emerge** from implementation work
- **After architectural decisions** that impact future development
- **When documentation structure changes** occur
- **After major bug fixes** that reveal important insights

---

## 2025-07-17

### RPC Headers Support Implementation
**Change**: Added optional headers parameter to all RPC config types and generated helper functions for CSRF token handling
**Context**: Hardcoded CSRF token functionality was not suitable for all authentication setups; needed flexibility for different auth patterns
**Files**: `lib/ash_typescript/rpc/codegen.ex`, `test/ash_typescript/rpc/rpc_typescript_codegen_test.exs`, `CLAUDE.md`, `docs/ai-quick-reference.md`
**Impact**: All RPC functions now accept custom headers while maintaining backward compatibility; developers can implement any authentication pattern
**Key Insights**: Generated TypeScript functions should be flexible enough to work with any authentication setup rather than assuming specific patterns like Phoenix CSRF tokens

### Documentation Framework Modernization
**Change**: Replaced achievement tracking with practical changelog system in AI documentation framework
**Context**: Achievement tracking was promotional rather than practical; changelog provides better context for current state and reasoning behind decisions
**Files**: `CLAUDE.md`, `docs/ai-index.md`, `docs/ai-documentation-update-guide.md`, `AI_DOCUMENTATION_SCAFFOLDING_GUIDE.md`
**Impact**: AI assistants now get better context about why current patterns exist rather than historical celebrations
**Key Insights**: Context about "why" decisions were made is more valuable than "what" was achieved for AI task completion

---

## 2025-07-16

### Union Storage Mode Unification
**Change**: Unified `:map_with_tag` and `:type_and_value` union storage modes with identical field selection support
**Context**: `:map_with_tag` unions were failing creation due to complex field constraints; needed both storage modes to work identically
**Files**: `test/support/resources/todo.ex`, `lib/ash_typescript/rpc/result_processor.ex`, `test/ash_typescript/rpc/rpc_union_storage_modes_test.exs`
**Impact**: Both union storage modes now work identically with proper union definitions and creation formats
**Key Insights**: Simple union definitions without complex constraints are required for `:map_with_tag` storage mode to work correctly

### Union Field Selection Implementation
**Change**: Added comprehensive union field selection system with selective member fetching
**Context**: No way to selectively fetch specific fields from union type members, always returned complete union objects
**Files**: `lib/ash_typescript/rpc/field_parser.ex`, `lib/ash_typescript/rpc/result_processor.ex`, `lib/ash_typescript/codegen.ex`, `test/ash_typescript/rpc/rpc_union_field_selection_test.exs`
**Impact**: Fine-grained field selection enables efficient data fetching with reduced bandwidth usage
**Key Insights**: Pattern matching order is critical when distinguishing union selections from regular field tuples; transformation must happen before field filtering

### FieldParser Architecture Refactoring
**Change**: Major simplification with 43% code reduction and architectural improvements
**Context**: Massive code duplication, scattered parameter passing, complex field processing needed cleanup
**Files**: `lib/ash_typescript/rpc/field_parser.ex`, `lib/ash_typescript/rpc/field_parser/context.ex`, `lib/ash_typescript/rpc/field_parser/calc_args_processor.ex`, `lib/ash_typescript/rpc/field_parser/load_builder.ex`
**Impact**: Clean utilities with unified Context pattern, single load building approach
**Key Insights**: Context struct eliminates parameter threading; pipeline pattern (Normalize → Classify → Process) provides consistent flow

---

## 2025-07-15

### Type Inference System Overhaul
**Change**: Implemented schema key-based field classification system with correct calculation type handling
**Context**: System incorrectly assumed all complex calculations return resources and need `fields` property
**Files**: `lib/ash_typescript/rpc/codegen.ex`, `lib/ash_typescript/codegen.ex`, `test/ts/shouldPass/` tests
**Impact**: System correctly detects calculation return types and only adds `fields` when needed
**Key Insights**: Schema keys eliminate field type ambiguity; authoritative classification via direct key lookup is more reliable than structural guessing

### Unified Field Format Implementation
**Change**: Removed backwards compatibility for `calculations` parameter in favor of unified field format
**Context**: Dual processing paths added complexity; needed single way to specify calculations
**Files**: `lib/ash_typescript/rpc.ex`, `lib/ash_typescript/rpc/result_processor.ex`, `lib/ash_typescript/rpc/field_parser.ex`
**Impact**: Single processing path with unified field format; enhanced field parser handles nested calculations within field lists
**Key Insights**: Single source of truth for field specifications is more maintainable than dual format support

### Embedded Resources Support (Complete)
**Change**: Complete TypeScript support for embedded resources with relationship-like architecture
**Context**: Embedded resources needed full type safety and field selection capabilities like relationships
**Files**: `lib/ash_typescript/codegen.ex`, `lib/ash_typescript/rpc/codegen.ex`, `lib/ash_typescript/rpc/field_parser.ex`, `lib/ash_typescript/rpc/result_processor.ex`
**Impact**: Embedded resources work exactly like relationships with unified object notation and full calculation support
**Key Insights**: Dual-nature processing (attributes + calculations) requires three-stage pipeline; relationship-like architecture provides consistency

---

**Last Updated**: 2025-07-17