# Troubleshooting Quick Reference

## Overview

This quick reference helps AI assistants rapidly identify and route AshTypescript problems to the appropriate troubleshooting resources.

## Problem Identification Index

| Problem Type | Key Symptoms | Troubleshooting Guide |
|--------------|--------------|----------------------|
| **Environment Issues** | "No domains found", "Module not loaded" | [Environment Issues](environment-issues.md) |
| **Type Generation** | Generated types contain 'any', TypeScript compilation errors | [Type Generation Issues](type-generation-issues.md) |
| **Embedded Resources** | "Unknown type", "should not be listed in domain" | [Embedded Resources Issues](embedded-resources-issues.md) |
| **Runtime Processing** | Field selection not working, calculation arguments failing | [Runtime Processing Issues](runtime-processing-issues.md) |
| **Testing & Performance** | Tests failing randomly, slow compilation | [Testing & Performance Issues](testing-performance-issues.md) |

## Symptom-Based Quick Diagnosis

### Environment & Setup Issues
- **"No domains found"** → Environment Issues - Wrong environment
- **"Module not loaded"** → Environment Issues - Test resources not available  
- **Function signature errors** → Environment Issues - FieldParser refactoring
- **Context not found** → Environment Issues - Missing Context module

### Type Generation Issues
- **Generated types contain 'any'** → Type Generation Issues - Type mapping problems
- **TypeScript compilation errors** → Type Generation Issues - Schema generation issues
- **Missing calculation types** → Type Generation Issues - Conditional fields property
- **Unknown type errors** → Type Generation Issues - Type detection problems

### Embedded Resources Issues
- **"Unknown type: EmbeddedResource"** → Embedded Resources Issues - Discovery problems
- **"Should not be listed in domain"** → Embedded Resources Issues - Domain configuration
- **Embedded resource not generating** → Embedded Resources Issues - Attribute scanning
- **Field selection not working** → Embedded Resources Issues - Dual-nature processing

### Runtime Processing Issues
- **Field selection not working** → Runtime Processing Issues - Pipeline problems
- **Calculation arguments failing** → Runtime Processing Issues - Arg processing
- **Empty response data** → Runtime Processing Issues - Result filtering
- **Load statement errors** → Runtime Processing Issues - Load building

### Testing & Performance Issues
- **Tests failing randomly** → Testing & Performance Issues - Test isolation
- **TypeScript tests not compiling** → Testing & Performance Issues - Validation workflow
- **Slow type generation** → Testing & Performance Issues - Performance optimization
- **Multitenancy issues** → Testing & Performance Issues - Tenant isolation

## Emergency Triage Procedure

### Step 1: Environment Check (Most Common)
```bash
# Quick environment verification
mix test.codegen --dry-run
```
- **Success**: Environment is correct, proceed to Step 2
- **Failure**: See [Environment Issues](environment-issues.md)

### Step 2: Basic Type Generation
```bash
# Test basic type generation
mix test.codegen
```
- **Success**: Type generation works, proceed to Step 3
- **Failure**: See [Type Generation Issues](type-generation-issues.md)

### Step 3: TypeScript Compilation
```bash
# Validate TypeScript compilation
cd test/ts && npm run compileGenerated
```
- **Success**: Types compile correctly, proceed to Step 4
- **Failure**: See [Type Generation Issues](type-generation-issues.md)

### Step 4: Runtime Testing
```bash
# Test RPC functionality
mix test test/ash_typescript/rpc/rpc_actions_test.exs
```
- **Success**: Runtime works correctly
- **Failure**: See [Runtime Processing Issues](runtime-processing-issues.md)

## Common Fix Patterns

### Environment Fixes
- **Always use test environment**: `mix test.codegen` not `mix ash_typescript.codegen`
- **Write tests for debugging**: Don't use one-off commands
- **Check Context usage**: New refactored signatures require Context

### Type Generation Fixes
- **Schema key-based classification**: Use authoritative schema keys
- **Conditional fields property**: Only complex calculations get fields
- **Resource detection**: Use `Ash.Resource.Info.*` functions

### Runtime Processing Fixes
- **Three-stage pipeline**: Field Parser → Ash Query → Result Processor
- **Unified field format**: Never use deprecated calculations parameter
- **Field classification order**: Embedded resources checked first

## Debugging Command Reference

### Environment Commands
```bash
# Environment validation - write proper tests instead of one-off commands
mix test                           # Validates environment setup

# Context creation test - write proper tests instead of one-off commands
mix test test/ash_typescript/rpc/  # Tests Context module functionality
```

### Type Generation Commands
```bash
# Type generation debugging
mix test.codegen --dry-run

# TypeScript validation
cd test/ts && npx tsc generated.ts --noEmit --strict
```

### Runtime Processing Commands
```bash
# RPC processing test
mix test test/ash_typescript/rpc/rpc_actions_test.exs --trace

# Field parser debugging
mix test test/ash_typescript/field_parser_comprehensive_test.exs
```

## Escalation Paths

### Level 1: Quick Fixes
1. **Environment Issues** → Use test environment
2. **Simple Type Issues** → Check type mapping
3. **Basic Runtime Issues** → Verify field format

### Level 2: Detailed Diagnosis
1. **Complex Type Issues** → Deep dive into schema generation
2. **Field Processing Issues** → Analyze three-stage pipeline
3. **Embedded Resource Issues** → Check discovery and integration

### Level 3: Advanced Debugging
1. **Performance Issues** → Profile generation and compilation
2. **Complex Union Issues** → Analyze transformation pipeline
3. **Multitenancy Issues** → Validate tenant isolation

## Validation Checklist

### Before Reporting Issues
- [ ] Used test environment (`mix test.codegen`)
- [ ] Checked TypeScript compilation (`cd test/ts && npm run compileGenerated`)
- [ ] Ran basic tests (`mix test test/ash_typescript/rpc/rpc_actions_test.exs`)
- [ ] Verified Context usage (post-refactoring)

### Before Making Changes
- [ ] Understood the problem domain
- [ ] Checked relevant troubleshooting guide
- [ ] Created test to reproduce issue
- [ ] Validated fix with test suite

## Critical Success Factors

1. **Environment Discipline**: Always use test environment
2. **Systematic Diagnosis**: Follow triage procedure
3. **Test-First Debugging**: Write tests to reproduce issues
4. **Context Awareness**: Understand post-refactoring architecture
5. **Validation Workflow**: Always validate TypeScript after changes

---

**Detailed Troubleshooting Guides**:
- [Environment Issues](environment-issues.md) - Setup and environment problems
- [Type Generation Issues](type-generation-issues.md) - TypeScript generation problems
- [Embedded Resources Issues](embedded-resources-issues.md) - Embedded resource problems
- [Runtime Processing Issues](runtime-processing-issues.md) - RPC runtime problems
- [Testing & Performance Issues](testing-performance-issues.md) - Testing and performance problems