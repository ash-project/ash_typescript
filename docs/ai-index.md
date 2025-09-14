# AshTypescript AI Assistant Documentation Index

## Quick Access Guide

This index helps AI assistants quickly find the most relevant documentation for specific tasks, optimizing context window usage.

**🆕 TIDEWAVE MCP ENABLED**: This project now has runtime introspection capabilities. Use `mcp__tidewave__project_eval` and other tidewave tools for debugging instead of shell commands.

## Core Files (Always Start Here)

| File | Purpose | When to Use |
|------|---------|-------------|
| [CLAUDE.md](../CLAUDE.md) | Main AI assistant guide | Start here for project overview, critical rules, and workflows |
| [ai-quick-reference.md](ai-quick-reference.md) | Quick commands and patterns | Need immediate help with common tasks |
| [ai-validation-safety.md](ai-validation-safety.md) | Testing and safety procedures | Before making any changes or troubleshooting |
| [ai-changelog.md](ai-changelog.md) | Context and evolution | Understanding why current patterns exist and architectural decisions |

## Task-Specific Documentation

### Implementation Tasks
| Task | Primary Documentation | Supporting Files |
|------|----------------------|------------------|
| **Type Generation/Inference** | [implementation/type-system.md](implementation/type-system.md) | [test/ash_typescript/](../test/ash_typescript/) |
| **Custom Types** | [implementation/custom-types.md](implementation/custom-types.md) | [guides.md](guides.md), [test/ash_typescript/custom_types_test.exs](../test/ash_typescript/custom_types_test.exs) |
| **RPC Features** | [implementation/rpc-pipeline.md](implementation/rpc-pipeline.md), [implementation/environment-setup.md](implementation/environment-setup.md), [implementation/development-workflows.md](implementation/development-workflows.md) | [test/ash_typescript/rpc/](../test/ash_typescript/rpc/), [ai-quick-reference.md](ai-quick-reference.md) |
| **Field Selection** | [implementation/field-processing.md](implementation/field-processing.md) | [ai-quick-reference.md](ai-quick-reference.md) |
| **Embedded Resources** | [implementation/embedded-resources.md](implementation/embedded-resources.md) | [test/support/resources/embedded/](../test/support/resources/embedded/) |
| **Union Types** | [implementation/union-systems-core.md](implementation/union-systems-core.md), [implementation/union-systems-advanced.md](implementation/union-systems-advanced.md) | [test/ash_typescript/rpc/rpc_union_*_test.exs](../test/ash_typescript/rpc/) |
| **Multitenancy** | [implementation/development-workflows.md](implementation/development-workflows.md) | [test/ash_typescript/rpc/rpc_multitenancy_*_test.exs](../test/ash_typescript/rpc/) |
| **Environment Setup** | [implementation/environment-setup.md](implementation/environment-setup.md) | [CLAUDE.md](../CLAUDE.md) |
| **Test Organization** | [testing.md](testing.md) | [test/ts/shouldPass/](../test/ts/shouldPass/), [test/ts/shouldFail/](../test/ts/shouldFail/) |

### Documentation Maintenance (Infrequent)
| Task | Primary Documentation | When Needed |
|------|----------------------|-------------|
| **Documentation Updates** | [ai-maintenance.md](ai-maintenance.md) | Rare - only for significant changes |

### Troubleshooting
| Issue Type | Primary Documentation | Emergency Reference |
|------------|----------------------|-------------------|
| **All Issues** | [troubleshooting.md](troubleshooting.md) | [CLAUDE.md](../CLAUDE.md) (Environment rules), [ai-validation-safety.md](ai-validation-safety.md) (Testing procedures) |

### Deep Dives and Insights
| Topic | Primary Documentation | When to Read |
|-------|----------------------|--------------|
| **Architecture Decisions** | [ai-changelog.md](ai-changelog.md) | Understanding design choices and current patterns |
| **Context and Evolution** | [ai-changelog.md](ai-changelog.md) | Understanding why current patterns exist |
| **Performance Patterns** | [implementation/](implementation/) guides | Optimizing specific implementations |

## File Size Reference (Context Window Planning)

### Core AI Documentation (Optimized)
- **[CLAUDE.md](../CLAUDE.md)** (~160 lines) - Main AI guide, ultra-optimized
- **[ai-changelog.md](ai-changelog.md)** (~200 lines) - Context and evolution
- **[ai-validation-safety.md](ai-validation-safety.md)** (~600 lines) - Testing procedures
- **[ai-quick-reference.md](ai-quick-reference.md)** (~400 lines) - Commands and patterns

### Implementation Guides (Focused)
- **[implementation/type-system.md](implementation/type-system.md)** - Type generation and inference
- **[implementation/rpc-pipeline.md](implementation/rpc-pipeline.md)** - RPC architecture
- **[implementation/field-processing.md](implementation/field-processing.md)** - Field selection system
- **[implementation/embedded-resources.md](implementation/embedded-resources.md)** - Embedded resource support
- **[implementation/union-systems-core.md](implementation/union-systems-core.md)** - Union type handling
- **[implementation/custom-types.md](implementation/custom-types.md)** - Custom type implementation

### Compact Guides
- **[guides.md](guides.md)** - Task-specific implementation patterns
- **[troubleshooting.md](troubleshooting.md)** - Issue diagnosis and resolution
- **[testing.md](testing.md)** - TypeScript test organization

## Recommended Reading Patterns

### For Quick Tasks (1-2 steps)
1. **[CLAUDE.md](../CLAUDE.md)** - Start here for commands and critical rules
2. **[ai-quick-reference.md](ai-quick-reference.md)** - Quick commands if needed

### For Implementation Tasks (3+ steps)  
1. **[CLAUDE.md](../CLAUDE.md)** - Critical rules and overview
2. **Task-specific [implementation/](implementation/) files** - Primary implementation guidance
3. **[ai-validation-safety.md](ai-validation-safety.md)** - Testing and validation procedures

### For Troubleshooting
1. **[CLAUDE.md](../CLAUDE.md)** - Environment rules and Tidewave debugging
2. **[troubleshooting.md](troubleshooting.md)** - Rapid diagnosis and solutions
3. **[ai-validation-safety.md](ai-validation-safety.md)** - Validation procedures

### For Understanding Context
1. **[ai-changelog.md](ai-changelog.md)** - Why current patterns exist and architectural decisions
2. **[implementation/](implementation/) guides** - Deep dives into specific areas

## Optimized Structure (2025-09-14)

**Documentation refactoring completed:**
- **Consolidated from 41 files (14,201 lines) to 12 files (~6,000 lines)**
- **Eliminated redundancy** - merged overlapping troubleshooting and guide content
- **Streamlined structure** - removed excessive subdirectories
- **Preserved essential information** while maximizing AI efficiency
- **Maintained Tidewave MCP integration** for runtime debugging

---
**Last Updated**: 2025-08-19  
**Major Refactoring**: Complete - Legacy waste eliminated, core guides optimized