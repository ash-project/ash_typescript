<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>

SPDX-License-Identifier: MIT
-->

# Configuration Reference

This document provides a comprehensive reference for all AshTypescript configuration options.

## Application Configuration

Configure AshTypescript in your `config/config.exs` file:

```elixir
# config/config.exs
config :ash_typescript,
  # File generation
  output_file: "assets/js/ash_rpc.ts",

  # RPC endpoints
  run_endpoint: "/rpc/run",
  validate_endpoint: "/rpc/validate",

  # Dynamic endpoints (for separate frontend projects)
  # run_endpoint: {:runtime_expr, "CustomTypes.getRunEndpoint()"},
  # validate_endpoint: {:runtime_expr, "process.env.RPC_VALIDATE_ENDPOINT"},

  # Custom error response handling
  # rpc_error_response_handler: "MyAppConfig.handleRpcResponseError",

  # Field formatting
  input_field_formatter: :camel_case,
  output_field_formatter: :camel_case,

  # Multitenancy
  require_tenant_parameters: false,

  # Zod schema generation
  generate_zod_schemas: true,
  zod_import_path: "zod",
  zod_schema_suffix: "ZodSchema",

  # Validation functions
  generate_validation_functions: true,

  # Phoenix channel-based RPC actions
  generate_phx_channel_rpc_actions: false,
  phoenix_import_path: "phoenix",

  # Custom type imports
  import_into_generated: [
    %{
      import_name: "CustomTypes",
      file: "./customTypes"
    }
  ],

  # Type mapping overrides for dependency types
  type_mapping_overrides: [
    {AshUUID.UUID, "string"},
    {SomeComplex.Custom.Type, "CustomTypes.MyCustomType"}
  ],

  # TypeScript type for untyped maps
  # untyped_map_type: "Record<string, any>"      # Default - allows any value type
  # untyped_map_type: "Record<string, unknown>"  # Stricter - requires type checking
```

### Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `output_file` | `string` | `"assets/js/ash_rpc.ts"` | Path where generated TypeScript code will be written |
| `run_endpoint` | `string \| {:runtime_expr, string}` | `"/rpc/run"` | Endpoint for executing RPC actions |
| `validate_endpoint` | `string \| {:runtime_expr, string}` | `"/rpc/validate"` | Endpoint for validating RPC requests |
| `rpc_error_response_handler` | `string \| nil` | `nil` | Custom function for handling HTTP error responses |
| `input_field_formatter` | `:camel_case \| :snake_case` | `:camel_case` | How to format field names in request inputs |
| `output_field_formatter` | `:camel_case \| :snake_case` | `:camel_case` | How to format field names in response outputs |
| `require_tenant_parameters` | `boolean` | `false` | Whether to require tenant parameters in RPC calls |
| `generate_zod_schemas` | `boolean` | `true` | Whether to generate Zod validation schemas |
| `zod_import_path` | `string` | `"zod"` | Import path for Zod library |
| `zod_schema_suffix` | `string` | `"ZodSchema"` | Suffix for generated Zod schema names |
| `generate_validation_functions` | `boolean` | `true` | Whether to generate form validation functions |
| `generate_phx_channel_rpc_actions` | `boolean` | `false` | Whether to generate Phoenix channel-based RPC functions |
| `phoenix_import_path` | `string` | `"phoenix"` | Import path for Phoenix library |
| `import_into_generated` | `list` | `[]` | List of custom modules to import |
| `type_mapping_overrides` | `list` | `[]` | Override TypeScript types for Ash types |
| `untyped_map_type` | `string` | `"Record<string, any>"` | TypeScript type for untyped maps |

## Domain Configuration

Configure RPC actions and typed queries in your domain modules:

```elixir
defmodule MyApp.Domain do
  use Ash.Domain, extensions: [AshTypescript.Rpc]

  typescript_rpc do
    resource MyApp.Todo do
      # Standard CRUD actions
      rpc_action :list_todos, :read
      rpc_action :get_todo, :get
      rpc_action :create_todo, :create
      rpc_action :update_todo, :update
      rpc_action :destroy_todo, :destroy

      # Custom actions
      rpc_action :complete_todo, :complete
      rpc_action :archive_todo, :archive

      # Typed queries for SSR and optimized data fetching
      typed_query :dashboard_todos, :read do
        ts_result_type_name "DashboardTodosResult"
        ts_fields_const_name "dashboardTodosFields"

        fields [
          :id, :title, :priority, :status,
          %{
            user: [:name, :email],
            comments: [:id, :content]
          },
        ]
      end
    end

    resource MyApp.User do
      rpc_action :list_users, :read
      rpc_action :get_user, :get
    end
  end
end
```

### RPC Action Configuration

Each `rpc_action` can be configured with:

- **First argument** - Name of the generated TypeScript function (e.g., `:list_todos`)
- **Second argument** - Name of the Ash action to execute (e.g., `:read`)

### Typed Query Configuration

Typed queries allow you to define pre-configured field selections with generated TypeScript types:

```elixir
typed_query :dashboard_todos, :read do
  ts_result_type_name "DashboardTodosResult"
  ts_fields_const_name "dashboardTodosFields"

  fields [
    :id, :title, :priority, :status,
    %{
      user: [:name, :email],
      comments: [:id, :content]
    },
  ]
end
```

**Options:**
- `ts_result_type_name` - Name for the generated result type
- `ts_fields_const_name` - Name for the generated fields constant
- `fields` - Pre-configured field selection array

## Field Formatting

AshTypescript automatically converts field names between Elixir's `snake_case` convention and TypeScript's `camelCase` convention.

### Default Behavior

```elixir
# Default: snake_case → camelCase
# user_name → userName
# created_at → createdAt
```

### Configuration Options

```elixir
config :ash_typescript,
  input_field_formatter: :camel_case,   # How inputs are formatted
  output_field_formatter: :camel_case   # How outputs are formatted
```

**Available formatters:**
- `:camel_case` - Converts to camelCase (e.g., `user_name` → `userName`)
- `:snake_case` - Keeps snake_case (e.g., `user_name` → `user_name`)

## Dynamic RPC Endpoints

For separate frontend projects or different deployment environments, AshTypescript supports dynamic endpoint configuration through runtime TypeScript expressions.

### Why Use Dynamic Endpoints?

When building a separate frontend project (not embedded in your Phoenix app), you may need different backend endpoint URLs for:
- **Development**: `http://localhost:4000/rpc/run`
- **Staging**: `https://staging-api.myapp.com/rpc/run`
- **Production**: `https://api.myapp.com/rpc/run`

Instead of hardcoding the endpoint in your Elixir config, you can use runtime expressions that will be evaluated at runtime in your TypeScript code.

### Configuration Options

You can use various runtime expressions depending on your needs:

```elixir
# config/config.exs
config :ash_typescript,
  # Option 1: Use environment variables directly (Node.js)
  run_endpoint: {:runtime_expr, "process.env.RPC_RUN_ENDPOINT || '/rpc/run'"},
  validate_endpoint: {:runtime_expr, "process.env.RPC_VALIDATE_ENDPOINT || '/rpc/validate'"},

  # Option 2: Use Vite environment variables
  # run_endpoint: {:runtime_expr, "import.meta.env.VITE_RPC_RUN_ENDPOINT || '/rpc/run'"},
  # validate_endpoint: {:runtime_expr, "import.meta.env.VITE_RPC_VALIDATE_ENDPOINT || '/rpc/validate'"},

  # Option 3: Use custom functions from imported modules
  # run_endpoint: {:runtime_expr, "MyAppConfig.getRunEndpoint()"},
  # validate_endpoint: {:runtime_expr, "MyAppConfig.getValidateEndpoint()"},

  # Option 4: Use complex expressions with conditionals
  # run_endpoint: {:runtime_expr, "window.location.hostname === 'localhost' ? 'http://localhost:4000/rpc/run' : '/rpc/run'"},

  # Import modules if needed for custom functions (Option 3)
  # import_into_generated: [
  #   %{
  #     import_name: "MyAppConfig",
  #     file: "./myAppConfig"
  #   }
  # ]
```

### Usage Examples

#### Option 1: Environment Variables (Node.js/Next.js)

```bash
# .env.local
RPC_RUN_ENDPOINT=http://localhost:4000/rpc/run
RPC_VALIDATE_ENDPOINT=http://localhost:4000/rpc/validate

# .env.production
RPC_RUN_ENDPOINT=https://api.myapp.com/rpc/run
RPC_VALIDATE_ENDPOINT=https://api.myapp.com/rpc/validate
```

Generated TypeScript will use the environment variables directly:
```typescript
const response = await fetchFunction(process.env.RPC_RUN_ENDPOINT || '/rpc/run', fetchOptions);
```

#### Option 2: Vite Environment Variables

```bash
# .env.development
VITE_RPC_RUN_ENDPOINT=http://localhost:4000/rpc/run

# .env.production
VITE_RPC_RUN_ENDPOINT=https://api.myapp.com/rpc/run
```

Generated TypeScript:
```typescript
const response = await fetchFunction(import.meta.env.VITE_RPC_RUN_ENDPOINT || '/rpc/run', fetchOptions);
```

#### Option 3: Custom Functions

Create a TypeScript file with functions that return the appropriate endpoints:

```typescript
// myAppConfig.ts
export function getRunEndpoint(): string {
  // Use environment variables from your frontend build system
  const baseUrl = import.meta.env.VITE_API_URL || "http://localhost:4000";
  return `${baseUrl}/rpc/run`;
}

export function getValidateEndpoint(): string {
  const baseUrl = import.meta.env.VITE_API_URL || "http://localhost:4000";
  return `${baseUrl}/rpc/validate`;
}

// For different environments:
// Development: VITE_API_URL=http://localhost:4000
// Staging: VITE_API_URL=https://staging-api.myapp.com
// Production: VITE_API_URL=https://api.myapp.com
```

#### Option 4: Complex Conditional Expressions

For browser-based applications that need different endpoints based on hostname:

```elixir
config :ash_typescript,
  run_endpoint: {:runtime_expr, """
  (window.location.hostname === 'localhost'
    ? 'http://localhost:4000/rpc/run'
    : `https://${window.location.hostname}/rpc/run`)
  """}
```

This allows dynamic endpoint resolution based on the current page's hostname.

### Generated Code

The generated RPC functions will use your runtime expressions directly in the code:

```typescript
// Example 1: With environment variables
// config: run_endpoint: {:runtime_expr, "process.env.RPC_RUN_ENDPOINT || '/rpc/run'"}

export async function createTodo<Fields extends CreateTodoFields>(
  config: CreateTodoConfig<Fields>
): Promise<CreateTodoResult<Fields>> {
  // Runtime expression is embedded directly
  const response = await fetchFunction(
    process.env.RPC_RUN_ENDPOINT || '/rpc/run',
    fetchOptions
  );
  // ... rest of implementation
}
```

```typescript
// Example 2: With custom function
// config: run_endpoint: {:runtime_expr, "MyAppConfig.getRunEndpoint()"}

import * as MyAppConfig from "./myAppConfig";

export async function createTodo<Fields extends CreateTodoFields>(
  config: CreateTodoConfig<Fields>
): Promise<CreateTodoResult<Fields>> {
  // Custom function is called at runtime
  const response = await fetchFunction(
    MyAppConfig.getRunEndpoint(),
    fetchOptions
  );
  // ... rest of implementation
}
```

## Custom Error Response Handling

For applications that need custom error handling when HTTP requests fail (e.g., enhanced logging, user notifications, retry logic), AshTypescript supports custom error response functions.

### Why Use Custom Error Handlers?

The default error handling returns a simple network error when a response is not OK:

```typescript
// Default behavior
if (!response.ok) {
  return {
    success: false,
    errors: [{ type: "network", message: response.statusText, details: {} }]
  };
}
```

Custom error handlers allow you to:
- **Log errors** to external services (Sentry, Datadog, etc.)
- **Parse server error responses** for more detailed error information
- **Add retry logic** or circuit breaker patterns
- **Display user-friendly error messages** based on HTTP status codes
- **Track metrics** around API failures

### Configuration

Configure a custom error handler function that will be called when responses are not OK:

```elixir
# config/config.exs
config :ash_typescript,
  # Reference a TypeScript function to handle non-OK responses
  rpc_error_response_handler: "MyAppConfig.handleRpcResponseError",

  # Import the module containing your error handler
  import_into_generated: [
    %{
      import_name: "MyAppConfig",
      file: "./myAppConfig"
    }
  ]
```

### TypeScript Implementation

Create a TypeScript file with your custom error handler function:

```typescript
// myAppConfig.ts

// Custom error handler with enhanced error details
export function handleRpcResponseError(response: Response) {
  // Log error to monitoring service
  console.error(`RPC Error: ${response.status} ${response.statusText}`, {
    url: response.url,
    status: response.status,
    statusText: response.statusText,
    timestamp: new Date().toISOString()
  });

  // You could also send to external error tracking:
  // Sentry.captureMessage(`RPC Error: ${response.status}`);

  // Return enhanced error details
  return {
    success: false as const,
    errors: [
      {
        type: "network" as const,
        message: `HTTP ${response.status}: ${response.statusText}`,
        details: {
          url: response.url,
          status: String(response.status)
        }
      }
    ]
  };
}
```

### Generated Code

The generated RPC functions will call your custom error handler instead of the default error handling:

```typescript
// Generated in ash_rpc.ts
import * as MyAppConfig from "./myAppConfig";

export async function createTodo<Fields extends CreateTodoFields>(
  config: CreateTodoConfig<Fields>
): Promise<CreateTodoResult<Fields>> {
  // ... request setup code ...

  const response = await fetchFunction(getRunEndpoint(), fetchOptions);

  if (!response.ok) {
    return MyAppConfig.handleRpcResponseError(response)  // Calls your custom handler
  }

  const result = await response.json();
  return result as CreateTodoResult<Fields>;
}
```

## Field and Argument Name Mapping

TypeScript has stricter identifier rules than Elixir. AshTypescript provides built-in verification and mapping for invalid field and argument names.

### Invalid Name Patterns

AshTypescript detects and requires mapping for these patterns:
- **Underscores before digits**: `field_1`, `address_line_2`, `item__3`
- **Question marks**: `is_active?`, `enabled?`

### Resource Field Mapping

Map invalid field names using the `field_names` option in your resource's `typescript` block:

```elixir
defmodule MyApp.User do
  use Ash.Resource,
    domain: MyApp.Domain,
    extensions: [AshTypescript.Resource]

  typescript do
    type_name "User"
    # Map invalid field names to valid TypeScript identifiers
    field_names [
      address_line_1: :address_line1,
      address_line_2: :address_line2,
      is_active?: :is_active
    ]
  end

  attributes do
    attribute :name, :string, public?: true
    attribute :address_line_1, :string, public?: true
    attribute :address_line_2, :string, public?: true
    attribute :is_active?, :boolean, public?: true
  end
end
```

**Generated TypeScript:**
```typescript
// Input (create/update)
const user = await createUser({
  input: {
    name: "John",
    addressLine1: "123 Main St",    // Mapped from address_line_1
    addressLine2: "Apt 4B",         // Mapped from address_line_2
    isActive: true                   // Mapped from is_active?
  },
  fields: ["id", "name", "addressLine1", "addressLine2", "isActive"]
});

// Output - same mapped names
if (result.success) {
  console.log(result.data.addressLine1);  // "123 Main St"
  console.log(result.data.isActive);      // true
}
```

### Action Argument Mapping

Map invalid action argument names using the `argument_names` option:

```elixir
typescript do
  type_name "Todo"
  argument_names [
    search: [query_string_1: :query_string1],
    filter_todos: [is_completed?: :is_completed]
  ]
end

actions do
  read :search do
    argument :query_string_1, :string
  end

  read :filter_todos do
    argument :is_completed?, :boolean
  end
end
```

**Generated TypeScript:**
```typescript
// Arguments use mapped names
const results = await searchTodos({
  input: { queryString1: "urgent tasks" },  // Mapped from query_string_1
  fields: ["id", "title"]
});

const filtered = await filterTodos({
  input: { isCompleted: false },  // Mapped from is_completed?
  fields: ["id", "title"]
});
```

### Map Type Field Mapping

For invalid field names in map/keyword/tuple type constraints, create a custom `Ash.Type.NewType` with the `typescript_field_names/0` callback:

```elixir
# Define custom type with field mapping
defmodule MyApp.CustomMetadata do
  use Ash.Type.NewType,
    subtype_of: :map,
    constraints: [
      fields: [
        field_1: [type: :string],
        is_active?: [type: :boolean],
        line_2: [type: :string]
      ]
    ]

  @impl true
  def typescript_field_names do
    [
      field_1: :field1,
      is_active?: :isActive,
      line_2: :line2
    ]
  end
end

# Use custom type in resource
defmodule MyApp.Resource do
  use Ash.Resource,
    domain: MyApp.Domain,
    extensions: [AshTypescript.Resource]

  typescript do
    type_name "Resource"
  end

  attributes do
    attribute :metadata, MyApp.CustomMetadata, public?: true
  end
end
```

**Generated TypeScript:**
```typescript
type Resource = {
  metadata: {
    field1: string;      // Mapped from field_1
    isActive: boolean;   // Mapped from is_active?
    line2: string;       // Mapped from line_2
  }
}
```

### Verification and Error Messages

AshTypescript includes three verifiers that check for invalid names at compile time:

**Resource field verification error:**
```
Invalid field names found that contain question marks, or numbers preceded by underscores.

Invalid field names in resource MyApp.User:
  - attribute address_line_1 → address_line1
  - attribute is_active? → is_active

You can use field_names in the typescript section to provide valid alternatives.
```

**Map constraint verification error:**
```
Invalid field names found in map/keyword/tuple type constraints.

Invalid constraint field names in attribute :metadata on resource MyApp.Resource:
    - field_1 → field1
    - is_active? → is_active

To fix this, create a custom Ash.Type.NewType using map/keyword/tuple as a subtype,
and define the `typescript_field_names/0` callback to map invalid field names to valid ones.
```

## Custom Types

Create custom Ash types with TypeScript integration:

### Basic Custom Type

```elixir
# 1. Create custom type in Elixir
defmodule MyApp.PriorityScore do
  use Ash.Type

  def storage_type(_), do: :integer
  def cast_input(value, _) when is_integer(value) and value >= 1 and value <= 100, do: {:ok, value}
  def cast_input(_, _), do: {:error, "must be integer 1-100"}
  def cast_stored(value, _), do: {:ok, value}
  def dump_to_native(value, _), do: {:ok, value}
  def apply_constraints(value, _), do: {:ok, value}

  # AshTypescript integration
  def typescript_type_name, do: "CustomTypes.PriorityScore"
end
```

```typescript
// 2. Create TypeScript type definitions in customTypes.ts
export type PriorityScore = number;

export type ColorPalette = {
  primary: string;
  secondary: string;
  accent: string;
};
```

```elixir
# 3. Use in your resources
defmodule MyApp.Todo do
  use Ash.Resource, domain: MyApp.Domain

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    attribute :priority_score, MyApp.PriorityScore, public?: true
  end
end
```

The generated TypeScript will automatically include your custom types:

```typescript
// Generated TypeScript includes imports
import * as CustomTypes from "./customTypes";

// Your resource types use the custom types
interface TodoFieldsSchema {
  id: string;
  title: string;
  priorityScore?: CustomTypes.PriorityScore | null;
}
```

## Type Mapping Overrides

When using custom Ash types from dependencies (where you can't add the `typescript_type_name/0` callback), use the `type_mapping_overrides` configuration to map them to TypeScript types.

### Configuration

```elixir
# config/config.exs
config :ash_typescript,
  type_mapping_overrides: [
    {AshUUID.UUID, "string"},
    {SomeComplex.Custom.Type, "CustomTypes.MyCustomType"}
  ]
```

### Example: Mapping Dependency Types

```elixir
# Suppose you're using a third-party library with a custom type
defmodule MyApp.Product do
  use Ash.Resource,
    domain: MyApp.Domain,
    extensions: [AshTypescript.Resource]

  typescript do
    type_name "Product"
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true

    # Type from a dependency - can't modify it to add typescript_type_name
    attribute :uuid, AshUUID.UUID, public?: true
    attribute :some_value, SomeComplex.Custom.Type, public?: true
  end
end
```

```elixir
# Configure the type mappings
config :ash_typescript,
  type_mapping_overrides: [
    # Map to built-in TypeScript type
    {AshUUID.UUID, "string"},

    # Map to custom type (requires defining the type in customTypes.ts)
    {SomeComplex.Custom.Type, "CustomTypes.MyCustomType"}
  ],

  # Import your custom types
  import_into_generated: [
    %{
      import_name: "CustomTypes",
      file: "./customTypes"
    }
  ]
```

```typescript
// customTypes.ts - Define the MyCustomType type
export type MyCustomType = {
  someField: string;
  anotherField: number;
};
```

**Generated TypeScript:**

```typescript
import * as CustomTypes from "./customTypes";

interface ProductResourceSchema {
  id: string;
  name: string;
  uuid: string;                        // Mapped to built-in string type
  someValue: CustomTypes.MyCustomType; // Mapped to custom type
}
```

### When to Use Type Mapping Overrides

- ✅ **Third-party Ash types** from dependencies you don't control
- ✅ **Library types** like `AshUUID.UUID`, etc.
- ❌ **Your own types** - prefer using `typescript_type_name/0` callback instead

## Custom Type Imports

Import custom TypeScript modules into the generated code:

```elixir
config :ash_typescript,
  import_into_generated: [
    %{
      import_name: "CustomTypes",
      file: "./customTypes"
    },
    %{
      import_name: "MyAppConfig",
      file: "./myAppConfig"
    }
  ]
```

This generates:

```typescript
import * as CustomTypes from "./customTypes";
import * as MyAppConfig from "./myAppConfig";
```

### Import Configuration Options

| Option | Type | Description |
|--------|------|-------------|
| `import_name` | `string` | Name to use for the import (e.g., `CustomTypes`) |
| `file` | `string` | Relative path to the module file (e.g., `./customTypes`) |

## Untyped Map Type Configuration

By default, AshTypescript generates `Record<string, any>` for map-like types without field constraints. You can configure this to use stricter types like `Record<string, unknown>` for better type safety.

### Configuration

```elixir
# config/config.exs
config :ash_typescript,
  # Default - allows any value type (more permissive)
  untyped_map_type: "Record<string, any>"

  # Stricter - requires type checking before use (recommended for new projects)
  # untyped_map_type: "Record<string, unknown>"

  # Custom - use your own type definition
  # untyped_map_type: "MyCustomMapType"
```

### What Gets Affected

This configuration applies to all map-like types without field constraints:

- `Ash.Type.Map` without `fields` constraint
- `Ash.Type.Keyword` without `fields` constraint
- `Ash.Type.Tuple` without `fields` constraint
- `Ash.Type.Struct` without `instance_of` or `fields` constraint

**Maps with field constraints are NOT affected** and will still generate typed objects.

### Type Safety Comparison

**With `Record<string, any>` (default):**

```typescript
// More permissive - values can be used directly
const todo = await getTodo({ fields: ["id", "customData"] });
if (todo.success && todo.data.customData) {
  const value = todo.data.customData.someField;  // OK - no error
  console.log(value.toUpperCase());              // Runtime error if not a string!
}
```

**With `Record<string, unknown>` (stricter):**

```typescript
// Stricter - requires type checking before use
const todo = await getTodo({ fields: ["id", "customData"] });
if (todo.success && todo.data.customData) {
  const value = todo.data.customData.someField;     // Type: unknown
  console.log(value.toUpperCase());                 // ❌ TypeScript error!

  // Must check type first
  if (typeof value === 'string') {
    console.log(value.toUpperCase());               // ✅ OK
  }
}
```

### Example Resources

```elixir
defmodule MyApp.Todo do
  use Ash.Resource,
    domain: MyApp.Domain,
    extensions: [AshTypescript.Resource]

  attributes do
    # Untyped map - uses configured untyped_map_type
    attribute :custom_data, :map, public?: true

    # Typed map - always generates typed object (not affected by config)
    attribute :metadata, :map, public?: true, constraints: [
      fields: [
        priority: [type: :string],
        tags: [type: {:array, :string}]
      ]
    ]
  end
end
```

**Generated TypeScript:**

```typescript
// With untyped_map_type: "Record<string, unknown>"
type TodoResourceSchema = {
  customData: Record<string, unknown> | null;  // Uses configured type
  metadata: {                                  // Typed object (not affected)
    priority: string;
    tags: Array<string>;
  } | null;
}
```

### When to Use Each Option

**Use `Record<string, any>` when:**
- You need maximum flexibility
- You're working with truly dynamic data structures
- You trust your backend data and want faster development
- Backward compatibility with existing code is important

**Use `Record<string, unknown>` when:**
- You want maximum type safety
- You're starting a new project
- You want to catch potential runtime errors at compile time
- You prefer explicit type checking over implicit assumptions

## Zod Schema Configuration

AshTypescript can generate Zod validation schemas for runtime type validation.

### Configuration

```elixir
config :ash_typescript,
  # Enable/disable Zod schema generation
  generate_zod_schemas: true,

  # Import path for Zod library
  zod_import_path: "zod",

  # Suffix for generated schema names
  zod_schema_suffix: "ZodSchema"
```

### Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `generate_zod_schemas` | `boolean` | `true` | Whether to generate Zod validation schemas |
| `zod_import_path` | `string` | `"zod"` | Import path for Zod library |
| `zod_schema_suffix` | `string` | `"ZodSchema"` | Suffix appended to schema names |

### Generated Output

When enabled, generates schemas like:

```typescript
import { z } from "zod";

export const TodoZodSchema = z.object({
  id: z.string(),
  title: z.string(),
  completed: z.boolean().nullable()
});
```

## Phoenix Channel Configuration

AshTypescript can generate Phoenix channel-based RPC functions alongside HTTP-based functions.

### Configuration

```elixir
config :ash_typescript,
  # Enable Phoenix channel RPC action generation
  generate_phx_channel_rpc_actions: true,

  # Import path for Phoenix library
  phoenix_import_path: "phoenix"
```

### Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `generate_phx_channel_rpc_actions` | `boolean` | `false` | Whether to generate channel-based RPC functions |
| `phoenix_import_path` | `string` | `"phoenix"` | Import path for Phoenix library |

### Generated Output

When enabled, generates both HTTP and channel-based functions:

```typescript
import { Channel } from "phoenix";

// HTTP-based (always available)
export async function listTodos<Fields extends ListTodosFields>(
  config: ListTodosConfig<Fields>
): Promise<ListTodosResult<Fields>> {
  // ... HTTP implementation
}

// Channel-based (when enabled)
export function listTodosChannel<Fields extends ListTodosFields>(
  config: ListTodosChannelConfig<Fields>
): void {
  // ... Channel implementation
}
```

For more details on using Phoenix channels, see the [Phoenix Channels topic documentation](../topics/phoenix-channels.md).

## See Also

- [Getting Started Tutorial](../tutorials/getting-started.md) - Initial setup and basic usage
- [Mix Tasks Reference](mix-tasks.md) - Code generation commands
- [Phoenix Channels](../topics/phoenix-channels.md) - Channel-based RPC actions
- [Troubleshooting Reference](troubleshooting.md) - Common problems and solutions
