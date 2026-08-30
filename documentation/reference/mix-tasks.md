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
# Basic installation (prompts for frontend framework)
mix igniter.install ash_typescript

# Full-stack React + TypeScript setup
mix igniter.install ash_typescript --framework react

# Vite bundler, or Inertia.js SSR setup
mix igniter.install ash_typescript --framework react --bundler vite
mix igniter.install ash_typescript --framework svelte --inertia
```

#### What It Does

The installer performs the following tasks:

1. **Dependency Setup**
   - Adds AshTypescript to your `mix.exs` dependencies
   - Runs `mix deps.get` to install the package

2. **Configuration**
   - Configures AshTypescript settings in `config/config.exs`
   - Sets default output paths and RPC endpoints

3. **Manifest Module** (required since 0.18)
   - Creates the app-wide manifest module (`lib/my_app/ash_typescript_manifest.ex` with `use AshTypescript.Manifest, otp_app: :my_app`)
   - Registers it via `config :ash_typescript, manifest: MyApp.AshTypescriptManifest`

4. **RPC Controller**
   - Creates RPC controller at `lib/*_web/controllers/ash_typescript_rpc_controller.ex`
   - Implements handlers for run and validate endpoints

5. **Phoenix Router**
   - Adds RPC routes to your Phoenix router
   - Configures `/rpc/run` and `/rpc/validate` endpoints

6. **Frontend Setup** (with `--framework`)
   - Sets up a complete TypeScript environment for the chosen framework
   - Configures esbuild or Vite for frontend builds
   - Creates welcome page with getting started guide
   - Installs necessary npm packages

#### Options

| Option | Description |
|--------|-------------|
| `--framework` | Frontend framework to set up: `react`, `vue`, `svelte`, or `solid` (prompts interactively when omitted) |
| `--bundler` | Bundler to use: `esbuild` (default) or `vite` |
| `--bun` | Use Bun instead of npm for package management |
| `--inertia` | Install with Inertia.js support for SSR (requires a framework and `--bundler esbuild`) |

#### When to Use

- ✅ New projects starting with AshTypescript
- ✅ Adding AshTypescript to existing Phoenix projects
- ✅ Setting up frontend with React integration
- ❌ Projects that already have AshTypescript installed

**This is the recommended approach for initial setup.**

## Code Generation Commands

### `mix ash.codegen`

**Recommended approach** for most projects. This command runs code generation for all Ash extensions in your project, including AshTypescript.

```bash
# Generate types for all Ash extensions including AshTypescript
mix ash.codegen --dev
```

For detailed information about `mix ash.codegen`, see the [Ash documentation](https://hexdocs.pm/ash/Mix.Tasks.Ash.Codegen.html).

### `mix ash_typescript.codegen`

Generate TypeScript types, RPC clients, Zod schemas, and validation functions **only for AshTypescript**.

#### Usage

```bash
# Basic generation (AshTypescript only)
mix ash_typescript.codegen

# Custom RPC endpoints
mix ash_typescript.codegen \
  --run-endpoint "/api/rpc/run" \
  --validate-endpoint "/api/rpc/validate"

# Check if generated code is up to date (CI usage)
mix ash_typescript.codegen --check

# Preview generated code without writing to file
mix ash_typescript.codegen --dry-run

# Override the configured output location for a single run
mix ash_typescript.codegen --output assets/js
mix ash_typescript.codegen --output myfolder/client.ts
```

#### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `--run-endpoint PATH` | `string` | `/rpc/run` | RPC run endpoint path (alias: `-r`) |
| `--validate-endpoint PATH` | `string` | `/rpc/validate` | RPC validate endpoint path (alias: `-v`) |
| `--check` | `boolean` | `false` | Raise `Ash.Error.Framework.PendingCodegen` if generated code is out of date. Covers every generated artifact, including the Markdown and JSON manifests (the JSON manifest's `generatedAt` stamp is ignored, so a date-only difference is not a diff). Only bypassed when `--dev` is also passed and `always_regenerate: true` is configured. |
| `--dev` | `boolean` | `false` | Marks a development-plug invocation (`AshPhoenix.Plug.CheckCodegenStatus` passes `--dev --check`); combined with `always_regenerate: true`, files are written instead of raising |
| `--dry-run` | `boolean` | `false` | Print files that would change to stdout (with `# <path>` headers) without writing them — manifests included |
| `--output PATH` | `string` | — | Override the `output_file` config for this run (alias: `-o`). See [Overriding the output location](#overriding-the-output-location) |

Output file locations are otherwise controlled by configuration (`output_file` and friends) — see the [Configuration Reference](configuration.md#multi-file-output).

#### Overriding the output location

`--output` overrides the `output_file` config, which is the path every other
generated file auto-derives from. A path ending in `.ts` is used verbatim as the
RPC functions file; anything else is treated as a directory and gets
`ash_rpc.ts` appended.

```bash
# both write assets/js/ash_rpc.ts + assets/js/ash_types.ts (+ ash_zod.ts / ash_valibot.ts when enabled)
mix ash_typescript.codegen --output assets/js
mix ash_typescript.codegen --output assets/js/ash_rpc.ts

# writes myfolder/client.ts + myfolder/ash_types.ts (+ ash_zod.ts / ash_valibot.ts when enabled)
mix ash_typescript.codegen --output myfolder/client.ts
```

Paths set **explicitly** via `types_output_file`, `zod_output_file`,
`valibot_output_file`, `routes_output_file` or `typed_channels_output_file` still
win over the derived location — `--output` only moves the paths that were left to
auto-derive. To relocate everything, either leave those keys unset or override
them in config as well.

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

4. **Zod / Valibot Validation Schemas** (if enabled)
   - Runtime type validation (into `ash_zod.ts` / `ash_valibot.ts`)
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

8. **Typed Controller Route Helpers** (if configured)
   - Path helpers for all routes
   - Typed async fetch functions for mutation routes
   - Input types from route arguments
   - See [Typed Controllers](../guides/typed-controllers.md) for details

#### Examples

**Basic Generation:**
```bash
mix ash_typescript.codegen
```

**Custom RPC Endpoints:**
```bash
mix ash_typescript.codegen \
  --run-endpoint "/api/rpc/run" \
  --validate-endpoint "/api/rpc/validate"
```

**CI Check:**
```bash
# In CI pipeline - fails if generated code is out of date
mix ash_typescript.codegen --check
```

**Preview Without Writing:**
```bash
# See what would be generated
mix ash_typescript.codegen --dry-run | less
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
# In your project/0 function, add preferred_envs to cli/0:
def cli do
  [
    preferred_envs: [
      "test.codegen": :test
    ]
  ]
end

# In your aliases:
defp aliases do
  [
    "test.codegen": "ash_typescript.codegen",
    # ... other aliases
  ]
end
```

This ensures `mix test.codegen` always runs in the test environment without needing `MIX_ENV=test`.

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

# If out of date, the task raises Ash.Error.Framework.PendingCodegen,
# listing the files whose generated content differs from disk
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
  git add assets/js/ash_*.ts
}
```

## Troubleshooting

### Common Issues

#### "No `:manifest` module configured for AshTypescript"

**Problem:** The task raises because no manifest module is registered — either the config is missing, or the module (and the config that points at it) only exists in another Mix environment.

**Solution:** Ensure `config :ash_typescript, manifest: MyApp.AshTypescriptManifest` is set and the module exists (see [Configuration Reference](configuration.md#manifest-module-required)). For projects with test-only resources, run in the correct MIX_ENV:

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
- [Installation](../getting-started/installation.md) - Initial setup guide
- [Troubleshooting Reference](troubleshooting.md) - Common problems and solutions
