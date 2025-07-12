# AshTypescript Documentation Index

## AI Assistant Quick Reference

This documentation is designed for AI assistants working on AshTypescript tasks. Each file focuses on specific aspects to optimize context window usage.

### Task-Based Documentation Guide

#### Understanding the Project
- **[overview.md](./overview.md)** - Architecture, purpose, core concepts
- **[file-structure.md](./file-structure.md)** - Key files and their purposes

#### Working with Code Generation
- **[codegen.md](./codegen.md)** - Type generation system, mappings, workflows
- Use when: Adding type mappings, debugging generation, understanding output

#### Working with RPC System  
- **[rpc.md](./rpc.md)** - RPC DSL, client generation, endpoints
- Use when: Configuring RPC exposure, client function generation, endpoint setup

#### Testing and Verification
- **[testing.md](./testing.md)** - Test patterns, verification, TypeScript compilation
- Use when: Writing tests, debugging test failures, verifying output

#### Development Tasks
- **[development.md](./development.md)** - Commands, workflows, troubleshooting
- Use when: Running commands, setting up development, common tasks

## Documentation Principles

### Designed For AI
- **Compact**: Minimal context window usage
- **Focused**: Each file covers specific domain
- **Actionable**: Practical information for tasks
- **Scannable**: Easy to find relevant sections

### File Selection Strategy
```
Task Type → Recommended Reading
────────────────────────────────
Understanding codebase → overview.md + file-structure.md
Type generation issues → codegen.md  
RPC configuration → rpc.md
Test failures → testing.md
Development commands → development.md
```

### Quick Command Reference
```bash
# Generate types
mix ash_typescript.codegen

# Run tests  
mix test

# Verify TypeScript
cd test/ts && npm run compile
```

### Key Concepts Summary
- **AshTypescript**: Generates TypeScript types from Ash resources
- **RPC Extension**: Exposes Ash actions as typed RPC endpoints  
- **Code Generation**: Maps Ash types to TypeScript equivalents
- **Testing**: Verifies generated types compile correctly
- **Integration**: Works with Phoenix for backend connectivity

## File Usage Frequency
- **development.md**: Most common (commands, workflows)
- **codegen.md**: Type generation tasks
- **testing.md**: Debugging and verification
- **rpc.md**: RPC configuration tasks  
- **overview.md**: Initial understanding
- **file-structure.md**: Code navigation reference