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
| **Custom Types** | [implementation/custom-types.md](implementation/custom-types.md) | [quick-guides/adding-new-types.md](quick-guides/adding-new-types.md), [test/ash_typescript/custom_types_test.exs](../test/ash_typescript/custom_types_test.exs) |
| **RPC Features** | [implementation/rpc-pipeline.md](implementation/rpc-pipeline.md), [implementation/environment-setup.md](implementation/environment-setup.md), [implementation/development-workflows.md](implementation/development-workflows.md) | [test/ash_typescript/rpc/](../test/ash_typescript/rpc/), [ai-quick-reference.md](ai-quick-reference.md) |
| **Field Selection** | [implementation/field-processing.md](implementation/field-processing.md) | [ai-quick-reference.md](ai-quick-reference.md) |
| **Embedded Resources** | [implementation/embedded-resources.md](implementation/embedded-resources.md) | [test/support/resources/embedded/](../test/support/resources/embedded/) |
| **Union Types** | [implementation/union-systems-core.md](implementation/union-systems-core.md), [implementation/union-systems-advanced.md](implementation/union-systems-advanced.md) | [test/ash_typescript/rpc/rpc_union_*_test.exs](../test/ash_typescript/rpc/) |
| **Multitenancy** | [implementation/development-workflows.md](implementation/development-workflows.md) | [test/ash_typescript/rpc/rpc_multitenancy_*_test.exs](../test/ash_typescript/rpc/) |
| **Environment Setup** | [implementation/environment-setup.md](implementation/environment-setup.md) | [CLAUDE.md](../CLAUDE.md) |
| **Test Organization** | [quick-guides/test-organization.md](quick-guides/test-organization.md) | [test/ts/shouldPass/](../test/ts/shouldPass/), [test/ts/shouldFail/](../test/ts/shouldFail/) |

### Documentation Tasks
| Task | Primary Documentation | Supporting Files |
|------|----------------------|------------------|
| **Creating Usage Rules** | [ai-usage-rules-update-guide.md](ai-usage-rules-update-guide.md) | [README.md](../README.md), [CLAUDE.md](../CLAUDE.md) |
| **Updating README** | [ai-readme-update-guide.md](ai-readme-update-guide.md) | [README.md](../README.md), [CLAUDE.md](../CLAUDE.md) |

### Troubleshooting
| Issue Type | Primary Documentation | Emergency Reference |
|------------|----------------------|-------------------|
| **Environment Issues** | [troubleshooting/environment-issues.md](troubleshooting/environment-issues.md) | [implementation/environment-setup.md](implementation/environment-setup.md), [CLAUDE.md](../CLAUDE.md) (Critical Rules) |
| **Type Generation Issues** | [troubleshooting/type-generation-issues.md](troubleshooting/type-generation-issues.md) | [implementation/type-system.md](implementation/type-system.md), [ai-quick-reference.md](ai-quick-reference.md) |
| **Field Parser Issues** | [troubleshooting/environment-issues.md](troubleshooting/environment-issues.md) | [implementation/field-processing.md](implementation/field-processing.md) |
| **Runtime Issues** | [troubleshooting/runtime-processing-issues.md](troubleshooting/runtime-processing-issues.md) | [ai-validation-safety.md](ai-validation-safety.md) |

### Deep Dives and Insights
| Topic | Primary Documentation | When to Read |
|-------|----------------------|--------------|
| **Architecture Decisions** | [ai-implementation-insights.md](ai-implementation-insights.md) | Understanding design choices |
| **Context and Evolution** | [ai-changelog.md](ai-changelog.md) | Understanding why current patterns exist |
| **Performance Patterns** | [ai-implementation-insights.md](ai-implementation-insights.md) | Optimizing implementations |

## File Size Reference (Context Window Planning)

### Small Files (< 500 lines) - Efficient for AI
- [ai-quick-reference.md](ai-quick-reference.md) (356 lines)
- [ai-usage-rules-update-guide.md](ai-usage-rules-update-guide.md) (323 lines)
- [ai-readme-update-guide.md](ai-readme-update-guide.md) (420 lines)
- [ai-changelog.md](ai-changelog.md) (150 lines)
- [quick-guides/adding-new-types.md](quick-guides/adding-new-types.md) (400 lines)
- [quick-guides/test-organization.md](quick-guides/test-organization.md) (200 lines)
- [implementation/environment-setup.md](implementation/environment-setup.md) (230 lines)
- [implementation/type-system.md](implementation/type-system.md) (289 lines)
- [implementation/field-processing.md](implementation/field-processing.md) (311 lines)
- [implementation/rpc-pipeline.md](implementation/rpc-pipeline.md) (~250 lines)
- [implementation/union-systems-core.md](implementation/union-systems-core.md) (323 lines)
- [implementation/custom-types.md](implementation/custom-types.md) (330 lines)
- [implementation/embedded-resources.md](implementation/embedded-resources.md) (392 lines)
- [implementation/development-workflows.md](implementation/development-workflows.md) (403 lines)
- [troubleshooting/quick-reference.md](troubleshooting/quick-reference.md) (175 lines)
- [troubleshooting/environment-issues.md](troubleshooting/environment-issues.md) (299 lines)
- [troubleshooting/type-generation-issues.md](troubleshooting/type-generation-issues.md) (364 lines)
- [troubleshooting/embedded-resources-issues.md](troubleshooting/embedded-resources-issues.md) (310 lines)
- [troubleshooting/runtime-processing-issues.md](troubleshooting/runtime-processing-issues.md) (350 lines)
- [troubleshooting/multitenancy-issues.md](troubleshooting/multitenancy-issues.md) (240 lines)
- [troubleshooting/testing-performance-issues.md](troubleshooting/testing-performance-issues.md) (420 lines)
- [troubleshooting/union-types-issues.md](troubleshooting/union-types-issues.md) (280 lines)
- [ai-validation-safety.md](ai-validation-safety.md) (506 lines)

### Medium Files (500-800 lines) - Manageable
- [implementation/union-systems-advanced.md](implementation/union-systems-advanced.md) (509 lines)
- [CLAUDE.md](../CLAUDE.md) (~400 lines after achievement removal)

### Large Files (> 1000 lines) - Use Sparingly
⚠️ **Context Window Warning**: These files consume significant context space
- [ai-implementation-insights.md](ai-implementation-insights.md) (1,924 lines)

## Legacy Documentation (Archived)

The following files have been moved to `docs/legacy/` and should not be read:
- `ai-architecture-patterns.md` → Use [implementation/type-system.md](implementation/type-system.md) and [implementation/development-workflows.md](implementation/development-workflows.md)
- `ai-development-workflow.md` → Use [implementation/development-workflows.md](implementation/development-workflows.md) and [implementation/environment-setup.md](implementation/environment-setup.md)
- `ai-domain-knowledge.md` → Use [implementation/](implementation/) files specific to your task
- `ai-embedded-resources.md` → Use [implementation/embedded-resources.md](implementation/embedded-resources.md)
- `ai-implementation-guide.md` → Content moved to [implementation/](implementation/) directory files

## Recommended Reading Patterns

### For Quick Tasks (1-2 steps)
1. [ai-quick-reference.md](ai-quick-reference.md)
2. [CLAUDE.md](../CLAUDE.md) (if needed)

### For Implementation Tasks (3+ steps)
1. [CLAUDE.md](../CLAUDE.md) (Critical Rules)
2. Task-specific [implementation/](implementation/) files (Primary)
3. [ai-validation-safety.md](ai-validation-safety.md) (Testing)

### For Troubleshooting
1. [CLAUDE.md](../CLAUDE.md) (Environment rules)
2. [troubleshooting/quick-reference.md](troubleshooting/quick-reference.md) (Rapid problem identification and triage)
3. Issue-specific guides in [troubleshooting/](troubleshooting/) directory
4. [ai-validation-safety.md](ai-validation-safety.md) (Validation)

### For Understanding Context
1. [ai-changelog.md](ai-changelog.md) (Why current patterns exist)
2. [ai-implementation-insights.md](ai-implementation-insights.md) (Deep architectural insights)

### For Deep Understanding
1. [implementation/](implementation/) files for specific areas
2. [ai-implementation-insights.md](ai-implementation-insights.md)

## Current Structure (Post-Restructuring)

The documentation has been successfully restructured with:
- `docs/implementation/` - Focused implementation guides (230-509 lines each)
- `docs/quick-guides/` - Task-specific guides (200-400 lines each)
- `docs/reference/` - Quick reference cards and patterns
- Legacy large files archived and content distributed to focused guides

---

**Last Updated**: 2025-07-20
**Documentation Restructuring**: Complete - Implementation files integrated