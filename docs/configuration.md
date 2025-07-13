# Configuration Guide

This guide covers all AshTypescript configuration options including field formatting, multitenancy, and system settings.

## Application Configuration

Configure AshTypescript in your `config/config.exs`:

```elixir
config :ash_typescript,
  # Basic settings
  output_file: "assets/js/ash_rpc.ts",
  run_endpoint: "/rpc/run", 
  validate_endpoint: "/rpc/validate",
  
  # Field formatting
  input_field_formatter: :camel_case,   # Parse client input
  output_field_formatter: :camel_case,  # TypeScript generation & responses
  
  # Multitenancy
  require_tenant_parameters: true       # Tenant handling mode
```

## Field Formatting

AshTypescript supports configurable field name formatting for consistent naming between Elixir and TypeScript.

### Built-in Formatters

| Formatter | Transform | Use Case |
|-----------|-----------|----------|
| `:camel_case` | `user_name` → `userName` | JavaScript/TypeScript standard |
| `:pascal_case` | `user_name` → `UserName` | Class names, enum values |
| `:snake_case` | `user_name` → `user_name` | Keep original Elixir format |

### Configuration Options

**`input_field_formatter`** - Converts client field names to internal Elixir atoms:
```typescript
// Client sends camelCase, converted to snake_case internally
await createUser({
  fields: ["userName", "emailAddress"],
  input: { userName: "John", emailAddress: "john@example.com" }
});
// Internal: %{user_name: "John", email_address: "john@example.com"}
```

**`output_field_formatter`** - Controls TypeScript generation and API response field names:
```typescript
// Generated TypeScript types (with :camel_case)
type UserSchema = {
  userName: string;
  emailAddress?: string;
  createdAt: UtcDateTime;
};

// API responses match generated types
const user = await createUser({...});
console.log(user.userName);     // "John"
console.log(user.emailAddress); // "john@example.com"
```

### Custom Formatters

For specialized requirements:

```elixir
config :ash_typescript,
  input_field_formatter: {MyApp.Formatters, :parse_input},
  output_field_formatter: {MyApp.Formatters, :format_output, ["prefix"]}
```

Custom formatter functions:
```elixir
defmodule MyApp.Formatters do
  def parse_input(field_name) when is_binary(field_name) do
    field_name |> String.to_atom()
  end
  
  def format_output(field_name, prefix) when is_binary(field_name) do
    "#{prefix}_#{field_name}"
  end
end
```

## Multitenancy Configuration

AshTypescript automatically handles multitenancy with two configurable modes.

### Tenant Parameter Modes

#### Mode 1: Tenant Parameters (Default)
```elixir
config :ash_typescript, require_tenant_parameters: true
```

**Generated TypeScript:**
```typescript
export type CreatePostConfig = {
  tenant: string;  // Required for multitenant resources
  fields: FieldSelection<PostResourceSchema>[];
  input: { title: string; };
};

// Usage
await createPost({
  tenant: "org_123",
  fields: ["id", "title"],
  input: { title: "New Post" }
});
```

#### Mode 2: Connection-based Tenant
```elixir
config :ash_typescript, require_tenant_parameters: false
```

**Generated TypeScript:**
```typescript
export type CreatePostConfig = {
  fields: FieldSelection<PostResourceSchema>[];
  input: { title: string; };
};

// Usage - tenant extracted from connection
await createPost({
  fields: ["id", "title"],
  input: { title: "New Post" }
});
```

### When to Use Connection-based Mode

Use `require_tenant_parameters: false` when your application:
- Sets tenant context in middleware using `Ash.PlugHelpers.set_tenant/2`
- Determines tenant from JWT claims, subdomain, or HTTP headers
- Centralizes tenant logic in the Phoenix pipeline

**Example Phoenix plug:**
```elixir
defmodule MyApp.TenantPlug do
  import Ash.PlugHelpers

  def call(conn, _opts) do
    tenant = extract_tenant_from_request(conn)
    set_tenant(conn, tenant)
  end
end
```

### Resource Configuration

Resources requiring tenant context:
```elixir
defmodule MyApp.Post do
  use Ash.Resource

  multitenancy do
    strategy :attribute    # or :context
    attribute :organization_id
    # global? false (default) - tenant required
  end
end
```

### Detection Logic

AshTypescript automatically detects multitenant resources based on:
- Multitenancy strategy (`:attribute` or `:context`)
- `global?` setting (`false` means tenant required)

## Mix Task Configuration

### Command-line Options

```bash
# Basic generation
mix ash_typescript.codegen

# Custom output
mix ash_typescript.codegen --output "frontend/types.ts"

# Custom endpoints  
mix ash_typescript.codegen --run_endpoint "/api/rpc"

# Check if up-to-date (CI)
mix ash_typescript.codegen --check

# Preview without writing
mix ash_typescript.codegen --dry_run
```

### Project Configuration

```elixir
# mix.exs aliases
aliases: [
  "test.codegen": "ash_typescript.codegen",
  "ci.check": "ash_typescript.codegen --check"
]
```

## Advanced Configuration

### Environment Variables

AshTypescript respects these environment variables:
- `ASH_TYPESCRIPT_OUTPUT` - Override output file path
- `ASH_TYPESCRIPT_CHECK` - Enable check mode

### Phoenix Integration

#### Router Setup
```elixir
scope "/rpc" do
  pipe_through :api
  post "/run", AshRpcWeb.RpcController, :run
  post "/validate", AshRpcWeb.RpcController, :validate
end
```

#### Controller Context
The RPC controller can access:
- Tenant context via `Ash.PlugHelpers.get_tenant/1`
- Actor context for authorization
- Custom context for domain-specific data

### Error Handling Configuration

Configure error response formatting:
```elixir
config :ash_typescript,
  error_formatter: {MyApp.ErrorFormatter, :format_error}
```

## Troubleshooting

### Configuration Issues

**Field formatting not working:**
- Verify formatter configuration matches client naming
- Check that custom formatters are properly implemented

**Tenant parameter errors:**
- Ensure `require_tenant_parameters` matches your setup
- Verify resource multitenancy configuration

**Missing generated types:**
- Run `mix ash_typescript.codegen` after configuration changes
- Check that resources are properly exposed via RPC

### Debug Configuration

```elixir
# Check current settings
iex> Application.get_env(:ash_typescript, :input_field_formatter)
iex> AshTypescript.Rpc.requires_tenant?(MyResource)
```