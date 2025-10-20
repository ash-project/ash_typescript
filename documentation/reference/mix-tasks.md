<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>

SPDX-License-Identifier: MIT
-->

# Mix Tasks Reference

This document provides a comprehensive reference for all AshTypescript Mix tasks.

## Installation Commands

### `mix igniter.install ash_typescript`

**Automated installer** that sets up everything you need to get started with AshTypescript.

#### Usage

```bash
# Basic installation (RPC setup only)
mix igniter.install ash_typescript

# Full-stack React + TypeScript setup
mix igniter.install ash_typescript --framework react
```

#### What It Does

The installer performs the following tasks:

1. **Dependency Setup**
   - Adds AshTypescript to your `mix.exs` dependencies
   - Runs `mix deps.get` to install the package

2. **Configuration**
   - Configures AshTypescript settings in `config/config.exs`
   - Sets default output paths and RPC endpoints

3. **RPC Controller**
   - Creates RPC controller at `lib/*_web/controllers/ash_typescript_rpc_controller.ex`
   - Implements handlers for run and validate endpoints

4. **Phoenix Router**
   - Adds RPC routes to your Phoenix router
   - Configures `/rpc/run` and `/rpc/validate` endpoints

5. **React Setup** (with `--framework react`)
   - Sets up complete React + TypeScript environment
   - Configures esbuild or vite for frontend builds
   - Creates welcome page with getting started guide
   - Installs necessary npm packages

#### Options

| Option | Description |
|--------|-------------|
| `--framework react` | Set up React + TypeScript environment |

#### When to Use

- ✅ New projects starting with AshTypescript
- ✅ Adding AshTypescript to existing Phoenix projects
- ✅ Setting up frontend with React integration
- ❌ Projects that already have AshTypescript installed

**This is the recommended approach for initial setup.**

## Code Generation Commands

### `mix ash.codegen`

**Preferred approach** for generating TypeScript types along with other Ash extensions in your project.

#### Usage

```bash
# Generate types for all Ash extensions including AshTypescript
mix ash.codegen --dev

# With custom output location
mix ash.codegen --dev --output "assets/js/ash_rpc.ts"
```

#### What It Does

Runs code generation for all Ash extensions in your project, including:
- AshTypescript (TypeScript types and RPC clients)
- AshPostgres (database migrations, if installed)
- AshGraphql (GraphQL schemas, if installed)
- Other Ash extensions

#### Options

| Option | Description |
|--------|-------------|
| `--dev` | Run codegen for development environment |
| `--output FILE` | Custom output file path for TypeScript |

#### When to Use

- ✅ Projects with multiple Ash extensions
- ✅ Want to run all codegen tasks together
- ✅ Standard workflow for Ash projects
- ❌ Need fine-grained control over AshTypescript only

**This is the recommended approach for most projects.**

### `mix ash_typescript.codegen`

Generate TypeScript types, RPC clients, Zod schemas, and validation functions **only for AshTypescript**.

#### Usage

```bash
# Basic generation (AshTypescript only)
mix ash_typescript.codegen

# Custom output location
mix ash_typescript.codegen --output "frontend/src/api/ash.ts"

# Custom RPC endpoints
mix ash_typescript.codegen \
  --run_endpoint "/api/rpc/run" \
  --validate_endpoint "/api/rpc/validate"

# Check if generated code is up to date (CI usage)
mix ash_typescript.codegen --check

# Preview generated code without writing to file
mix ash_typescript.codegen --dry_run
```

#### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `--output FILE` | `string` | `assets/js/ash_rpc.ts` | Output file path for generated TypeScript |
| `--run_endpoint PATH` | `string` | `/rpc/run` | RPC run endpoint path |
| `--validate_endpoint PATH` | `string` | `/rpc/validate` | RPC validate endpoint path |
| `--check` | `boolean` | `false` | Check if generated code is up to date (exit 1 if not) |
| `--dry_run` | `boolean` | `false` | Print generated code to stdout without writing file |

#### Generated Content

When run, this task generates:

1. **TypeScript Interfaces**
   - Resource types with field metadata
   - Schema types for field selection
   - Result types for each action

2. **RPC Client Functions**
   - HTTP-based RPC functions for each action
   - Channel-based RPC functions (if enabled)
   - Type-safe configuration objects

3. **Filter Input Types**
   - Comprehensive filter operators
   - Type-safe query building
   - Nested relationship filtering

4. **Zod Validation Schemas** (if enabled)
   - Runtime type validation
   - Schema for each resource
   - Nested validation support

5. **Form Validation Functions**
   - Client-side validation helpers
   - Error message handling
   - Field-level validation

6. **Typed Query Constants**
   - Pre-configured field selections
   - SSR-optimized types
   - Type-safe result extraction

7. **Custom Type Imports**
   - Imports for custom types
   - Integration with external types
   - Type mapping support

#### Examples

**Basic Generation:**
```bash
mix ash_typescript.codegen
```

**Custom Output Location:**
```bash
mix ash_typescript.codegen --output "frontend/src/api/ash.ts"
```

**Custom RPC Endpoints:**
```bash
mix ash_typescript.codegen \
  --run_endpoint "/api/rpc/run" \
  --validate_endpoint "/api/rpc/validate"
```

**CI Check:**
```bash
# In CI pipeline - fails if generated code is out of date
mix ash_typescript.codegen --check
```

**Preview Without Writing:**
```bash
# See what would be generated
mix ash_typescript.codegen --dry_run | less
```

#### When to Use

- ✅ Want to run codegen specifically for AshTypescript
- ✅ Need custom output paths or endpoints
- ✅ Debugging generated TypeScript code
- ✅ CI/CD pipelines with `--check` flag
- ❌ Have other Ash extensions that need codegen (use `mix ash.codegen`)

## Test Environment Code Generation

For projects using test-only resources (common in library development), use the test environment:

```bash
# Generate types in test environment
MIX_ENV=test mix ash_typescript.codegen

# Or use the test.codegen alias (if defined)
mix test.codegen
```

### Setting Up Test Codegen Alias

Add to your `mix.exs`:

```elixir
defp aliases do
  [
    "test.codegen": ["cmd MIX_ENV=test mix ash_typescript.codegen"],
    # ... other aliases
  ]
end
```

## Workflow Integration

### Development Workflow

```bash
# 1. Make changes to resources or domain configuration
vim lib/my_app/resources/todo.ex

# 2. Generate TypeScript types
mix ash.codegen --dev

# 3. Verify TypeScript compilation (in frontend directory)
cd assets && npm run typecheck

# 4. Run tests
mix test
```

### CI/CD Workflow

```bash
# In your CI pipeline (.github/workflows/ci.yml, etc.)

# Check generated code is up to date
mix ash_typescript.codegen --check

# If out of date, CI fails with:
# "Generated TypeScript code is out of date. Run: mix ash_typescript.codegen"
```

**Example GitHub Actions:**

```yaml
- name: Check TypeScript codegen
  run: mix ash_typescript.codegen --check

- name: Type check generated code
  run: |
    cd assets
    npm run typecheck
```

### Pre-commit Hook

Add to `.git/hooks/pre-commit`:

```bash
#!/bin/bash
# Regenerate TypeScript on commit
mix ash_typescript.codegen --check || {
  echo "TypeScript code out of date. Regenerating..."
  mix ash_typescript.codegen
  git add assets/js/ash_rpc.ts
}
```

## Troubleshooting

### Common Issues

#### "No domains found"

**Problem:** Command runs but generates empty output or reports no domains.

**Solution:** Ensure you're in the correct MIX_ENV:

```bash
# Wrong - uses dev environment
mix ash_typescript.codegen

# Correct - uses test environment for test resources
MIX_ENV=test mix ash_typescript.codegen
```

#### Generated code doesn't compile

**Problem:** TypeScript compilation fails after generation.

**Solution:** Check for:
1. Invalid field names (use field name mapping)
2. Custom types not defined in imported modules
3. Missing type mapping overrides for dependency types

See [Configuration Reference](configuration.md) for field name mapping and type overrides.

#### Changes not reflected

**Problem:** Made changes to resources but generated TypeScript unchanged.

**Solution:**
1. Recompile Elixir code: `mix compile --force`
2. Regenerate TypeScript: `mix ash_typescript.codegen`
3. Verify output file path matches configuration

#### Permission errors

**Problem:** Cannot write to output file.

**Solution:** Check file permissions and directory structure:

```bash
# Ensure directory exists
mkdir -p assets/js

# Check permissions
ls -la assets/js

# Fix if needed
chmod 755 assets/js
```

## See Also

- [Configuration Reference](configuration.md) - Configure code generation
- [Getting Started Tutorial](../tutorials/getting-started.md) - Initial setup guide
- [Troubleshooting Reference](troubleshooting.md) - Common problems and solutions
