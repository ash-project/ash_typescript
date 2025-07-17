# AshTypescript AI Assistant Documentation Index

## Quick Access Guide

This index helps AI assistants quickly find the most relevant documentation for specific tasks, optimizing context window usage.

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
| **Type Generation/Inference** | [ai-implementation-guide.md](ai-implementation-guide.md) | [test/ash_typescript/](../test/ash_typescript/) |
| **Custom Types** | [quick-guides/adding-new-types.md](quick-guides/adding-new-types.md) | [implementation/custom-types.md](implementation/custom-types.md), [test/ash_typescript/custom_types_test.exs](../test/ash_typescript/custom_types_test.exs) |
| **RPC Features** | [ai-implementation-guide.md](ai-implementation-guide.md) | [test/ash_typescript/rpc/](../test/ash_typescript/rpc/), [ai-quick-reference.md](ai-quick-reference.md) |
| **Field Selection** | [ai-implementation-guide.md](ai-implementation-guide.md) | [ai-quick-reference.md](ai-quick-reference.md) |
| **Embedded Resources** | [ai-implementation-guide.md](ai-implementation-guide.md) | [test/support/resources/embedded/](../test/support/resources/embedded/) |
| **Union Types** | [ai-implementation-guide.md](ai-implementation-guide.md) | [test/ash_typescript/rpc/rpc_union_*_test.exs](../test/ash_typescript/rpc/) |
| **Multitenancy** | [ai-implementation-guide.md](ai-implementation-guide.md) | [test/ash_typescript/rpc/rpc_multitenancy_*_test.exs](../test/ash_typescript/rpc/) |
| **Test Organization** | [quick-guides/test-organization.md](quick-guides/test-organization.md) | [test/ts/shouldPass/](../test/ts/shouldPass/), [test/ts/shouldFail/](../test/ts/shouldFail/) |

### Documentation Tasks
| Task | Primary Documentation | Supporting Files |
|------|----------------------|------------------|
| **Creating Usage Rules** | [ai-usage-rules-update-guide.md](ai-usage-rules-update-guide.md) | [README.md](../README.md), [CLAUDE.md](../CLAUDE.md) |
| **Updating README** | [ai-readme-update-guide.md](ai-readme-update-guide.md) | [README.md](../README.md), [CLAUDE.md](../CLAUDE.md) |

### Troubleshooting
| Issue Type | Primary Documentation | Emergency Reference |
|------------|----------------------|-------------------|
| **Environment Issues** | [ai-troubleshooting.md](ai-troubleshooting.md) | [CLAUDE.md](../CLAUDE.md) (Critical Rules) |
| **Type Generation Issues** | [ai-troubleshooting.md](ai-troubleshooting.md) | [ai-quick-reference.md](ai-quick-reference.md) |
| **Field Parser Issues** | [ai-troubleshooting.md](ai-troubleshooting.md) | [ai-implementation-guide.md](ai-implementation-guide.md) |
| **Runtime Issues** | [ai-troubleshooting.md](ai-troubleshooting.md) | [ai-validation-safety.md](ai-validation-safety.md) |

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
- [implementation/custom-types.md](implementation/custom-types.md) (350 lines)
- [ai-validation-safety.md](ai-validation-safety.md) (506 lines)

### Medium Files (500-800 lines) - Manageable
- [CLAUDE.md](../CLAUDE.md) (~400 lines after achievement removal)

### Large Files (> 1000 lines) - Use Sparingly
⚠️ **Context Window Warning**: These files consume significant context space
- [ai-implementation-guide.md](ai-implementation-guide.md) (1,390 lines)
- [ai-troubleshooting.md](ai-troubleshooting.md) (1,127 lines)
- [ai-implementation-insights.md](ai-implementation-insights.md) (1,924 lines)

## Legacy Documentation (Archived)

The following files have been moved to `docs/legacy/` and should not be read:
- `ai-architecture-patterns.md` → Use [ai-implementation-guide.md](ai-implementation-guide.md)
- `ai-development-workflow.md` → Use [ai-implementation-guide.md](ai-implementation-guide.md)
- `ai-domain-knowledge.md` → Use [ai-implementation-guide.md](ai-implementation-guide.md)
- `ai-embedded-resources.md` → Use [ai-implementation-guide.md](ai-implementation-guide.md)

## Recommended Reading Patterns

### For Quick Tasks (1-2 steps)
1. [ai-quick-reference.md](ai-quick-reference.md)
2. [CLAUDE.md](../CLAUDE.md) (if needed)

### For Implementation Tasks (3+ steps)
1. [CLAUDE.md](../CLAUDE.md) (Critical Rules)
2. [ai-implementation-guide.md](ai-implementation-guide.md) (Primary)
3. [ai-validation-safety.md](ai-validation-safety.md) (Testing)

### For Troubleshooting
1. [CLAUDE.md](../CLAUDE.md) (Environment rules)
2. [ai-troubleshooting.md](ai-troubleshooting.md) (Issue-specific)
3. [ai-validation-safety.md](ai-validation-safety.md) (Validation)

### For Understanding Context
1. [ai-changelog.md](ai-changelog.md) (Why current patterns exist)
2. [ai-implementation-insights.md](ai-implementation-insights.md) (Deep architectural insights)

### For Deep Understanding
1. [ai-implementation-guide.md](ai-implementation-guide.md)
2. [ai-implementation-insights.md](ai-implementation-insights.md)

## Future Structure (Post-Restructuring)

After Phase 2-4 implementation, this index will reference:
- `docs/implementation/` - Focused implementation guides (200-250 lines each)
- `docs/troubleshooting/` - Focused troubleshooting guides (200-250 lines each)  
- `docs/insights/` - Focused insight documents (300-400 lines each)
- `docs/quick-guides/` - Task-specific guides (100-150 lines each)
- `docs/reference/` - Quick reference cards (50-150 lines each)

---

**Last Updated**: 2025-07-17
**Documentation Restructuring**: Phase 1 Complete