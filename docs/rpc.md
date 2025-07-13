# RPC System

## AshTypescript.Rpc Extension

### Purpose
Provides DSL for exposing Ash resources as RPC endpoints with generated TypeScript clients.

### Domain Configuration
```elixir
defmodule MyApp.Blog do
  use Ash.Domain,
    extensions: [AshTypescript.Rpc]

  rpc do
    resource Post do
      rpc_action :create, :create
      rpc_action :update, :update
      rpc_action :list, :read
      rpc_action :get, :by_id
      rpc_action :delete, :destroy
    end

    resource Comment do
      rpc_action :create, :create
      rpc_action :moderate, :moderate
    end
  end
end
```

### DSL Elements

#### `resource` block
- Defines which resource to expose via RPC
- Contains `rpc_action` definitions

#### `rpc_action` definition
- **name**: TypeScript function name (camelCase recommended)
- **action**: Corresponding Ash resource action
- Creates type-safe client function

### Generated Client Functions

#### Function Signatures
```typescript
// For create/update actions
async createPost(params: PostCreateInput): Promise<PostSchema>

// For read actions
async listPosts(params?: PostListInput): Promise<PostSchema[]>

// For get actions
async getPost(id: string, params?: PostGetInput): Promise<PostSchema>

// For destroy actions
async deletePost(id: string): Promise<void>
```

#### Generated Input Types
- **CreateInput**: Required and optional attributes for creation
- **UpdateInput**: All attributes optional except primary key
- **ListInput**: Filter, sort, pagination, load options
- **GetInput**: Load options for relationships

### RPC Endpoint Integration

#### Phoenix Router Setup
```elixir
# router.ex
scope "/rpc" do
  pipe_through :api

  post "/run", AshRpcWeb.RpcController, :run
  post "/validate", AshRpcWeb.RpcController, :validate
end
```

#### Request Format
```typescript
{
  action: "MyApp.Blog.Post.create",
  input: { title: "New Post", body: "Content..." },
  load: ["author", "comments"],
  actor: { id: "user-123" }
}
```

#### Response Format
```typescript
// Success
{ data: PostSchema, errors: null }

// Error
{ data: null, errors: ErrorSchema[] }
```

### Generated Code Structure

#### RPC Client Class
- `AshRpc` class with methods for each exposed action
- Handles HTTP requests to Phoenix endpoints
- Type-safe parameter validation
- Error handling and response transformation

#### Action Methods
- Named according to `rpc_action` name
- Accept typed parameters
- Return typed responses
- Handle loading of relationships

### Security Considerations
- All actions go through normal Ash authorization
- Actor context passed in requests
- Policies apply to RPC calls
- No bypass of resource-level security

## Implementation Details

### Calculation Argument Processing

#### Ash Integration Format
When the RPC layer loads calculations with arguments, it must pass them to Ash in the correct format:

```elixir
# ✅ Correct format - arguments passed directly
{calculation_name, args_map}

# ❌ Incorrect format - arguments wrapped in keyword list
{calculation_name, [args: args_map]}
```

The RPC layer converts JSON calculation arguments to the proper Ash format:
```elixir
# From RPC request
"calculations" => %{
  "self" => %{
    "calcArgs" => %{"prefix" => nil},
    "fields" => ["id", "title"]
  }
}

# Converted to Ash load format
{:self, %{prefix: nil}}
```

#### Argument Name Conversion
- RPC receives string argument names from JSON
- Converts to atoms using `String.to_existing_atom/1`
- Safe because calculation arguments are pre-defined in resource

#### Field Extraction Logic
The RPC system supports field selection to return only requested fields from responses. The `extract_fields_from_map` function handles different field specification types:

**Simple Fields**: Direct atom field names like `:id`, `:title`
```elixir
field when is_atom(field) ->
  if Map.has_key?(map, field), do: Map.put(acc, field, map[field]), else: acc
```

**Relationships**: Tuples with nested field specifications like `{:comments, [:id, :body]}`
```elixir
{relation, nested_fields} when is_list(nested_fields) ->
  # Apply field selection to relationship data
```

**Calculations with Arguments**: Tuples where calculation has arguments like `{:self, %{prefix: nil}}`
```elixir
{calc_name, _args} when is_atom(calc_name) ->
  # Apply field selection to calculation result if specified
```

**Field Selection Specifications**: Stored separately for calculations that support field filtering, allowing complex calculations to return only requested fields rather than full results.

### Troubleshooting

#### BadMapError in validate_calculation_arguments
**Error**: `BadMapError: expected a map, got: nil` in `Ash.Query.validate_calculation_arguments/3`

**Cause**: Incorrect argument format passed to `Ash.Query.load/2`

**Solution**: Ensure calculation arguments are passed as `{calc_name, args_map}`, not `{calc_name, [args: args_map]}`

#### Calculation Not Appearing in Response
**Cause**: Field selection logic may not be properly handling calculations with arguments

**Debug**: Check that calculation loads correctly with `Ash.Query.load/2` directly before investigating RPC field processing

#### Field Selection Not Working with Calculations with Arguments
**Error**: Calculations with arguments (like `{:self, %{prefix: nil}}`) are loaded correctly but field selection is ignored, returning the full calculation result instead of filtered fields.

**Cause**: The `extract_fields_from_map` function in `lib/ash_typescript/rpc.ex` only handled simple atom fields and relationship tuples with lists, but not calculation tuples where the second element is an arguments map.

**Solution**: Ensure calculation tuples with arguments are handled in field extraction:
```elixir
# Handle calculation with arguments: {calculation_name, arguments}
{calc_name, _args} when is_atom(calc_name) ->
  if Map.has_key?(map, calc_name) do
    value = Map.get(map, calc_name)
    case Map.get(calculation_field_specs, calc_name) do
      nil -> Map.put(acc, calc_name, value)
      calc_fields ->
        filtered_value = extract_return_value(value, calc_fields, calculation_field_specs)
        Map.put(acc, calc_name, filtered_value)
    end
  else
    acc
  end
```

## Multitenancy Support

The RPC system provides automatic support for multitenant Ash resources, handling tenant parameters transparently in both Elixir and generated TypeScript code.

### Overview

Resources configured with multitenancy require tenant information to be passed with RPC requests. The system automatically:
- Detects which resources require tenant parameters
- Adds tenant fields to generated TypeScript config types
- Includes tenant in request payloads
- Passes tenant context to Ash operations

### Configuration

#### Tenant Parameter Mode

The RPC system supports two modes for handling tenant information, controlled by the `:require_tenant_parameters` configuration:

```elixir
# config/config.exs

# Default behavior - tenant passed as request parameter
config :ash_typescript, require_tenant_parameters: true

# Alternative - tenant extracted from connection
config :ash_typescript, require_tenant_parameters: false
```

**Mode 1: Tenant Parameters (default)**
- Multitenant resources require `tenant` field in TypeScript config
- Tenant value passed in RPC request payload
- Useful for client-driven tenant selection

**Mode 2: Connection-based Tenant**
- No tenant parameters in generated TypeScript interfaces
- Tenant extracted using `Ash.PlugHelpers.get_tenant(conn)`
- Useful when tenant is set earlier in request pipeline

#### When to Use Connection-based Mode

Use `require_tenant_parameters: false` when your application:
- Sets tenant context in middleware or plugs using `Ash.PlugHelpers.set_tenant/2`
- Determines tenant from JWT claims, subdomain, or HTTP headers
- Wants to avoid exposing tenant selection to client code
- Centralizes tenant logic in the Phoenix pipeline

```elixir
# Example: Setting tenant in a Phoenix plug
defmodule MyApp.TenantPlug do
  import Plug.Conn
  import Ash.PlugHelpers

  def init(opts), do: opts

  def call(conn, _opts) do
    tenant = extract_tenant_from_request(conn)
    set_tenant(conn, tenant)
  end

  defp extract_tenant_from_request(conn) do
    # Extract from subdomain, header, JWT, etc.
  end
end
```

### Tenant Requirements

A resource requires a tenant parameter when:
- It has multitenancy configured with strategy `:attribute` or `:context`
- The `global?` option is `false` (which is the default)

```elixir
# This resource requires tenant
multitenancy do
  strategy :attribute
  attribute :organization_id
  # global? false is the default
end

# This resource does NOT require tenant
multitenancy do
  strategy :attribute  
  attribute :organization_id
  global? true  # Allows operations without tenant
end
```

### Generated TypeScript Interface

The generated TypeScript config types depend on both the resource's multitenancy configuration and the `:require_tenant_parameters` setting:

#### With `require_tenant_parameters: true` (default)
```typescript
// Generated for multitenant resource
export type CreatePostConfig = {
  tenant: string;  // Required for multitenant resources
  fields: FieldSelection<PostResourceSchema>[];
  input: { title: string; body: string; };
};

// Generated for non-multitenant resource (no tenant field)
export type CreateUserConfig = {
  fields: FieldSelection<UserResourceSchema>[];
  input: { name: string; email: string; };
};
```

#### With `require_tenant_parameters: false`
```typescript
// Generated for multitenant resource (no tenant field - extracted from connection)
export type CreatePostConfig = {
  fields: FieldSelection<PostResourceSchema>[];
  input: { title: string; body: string; };
};

// Generated for non-multitenant resource (identical)
export type CreateUserConfig = {
  fields: FieldSelection<UserResourceSchema>[];
  input: { name: string; email: string; };
};
```

### Usage Examples

#### Client-side Usage

**With `require_tenant_parameters: true` (default)**
```typescript
// For multitenant resources
await createPost({
  tenant: "org_123",
  fields: ["id", "title", "created_at"],
  input: { title: "New Post", body: "Content..." }
});

// For non-multitenant resources (no tenant needed)
await createUser({
  fields: ["id", "name", "email"],
  input: { name: "John", email: "john@example.com" }
});
```

**With `require_tenant_parameters: false`**
```typescript
// For multitenant resources (no tenant parameter)
await createPost({
  fields: ["id", "title", "created_at"],
  input: { title: "New Post", body: "Content..." }
});

// For non-multitenant resources (identical)
await createUser({
  fields: ["id", "name", "email"],
  input: { name: "John", email: "john@example.com" }
});
```

#### Request Format

**With tenant parameters**
```json
{
  "action": "create_post",
  "tenant": "org_123",
  "input": { "title": "New Post", "body": "Content..." },
  "fields": ["id", "title", "created_at"]
}
```

**Without tenant parameters**
```json
{
  "action": "create_post",
  "input": { "title": "New Post", "body": "Content..." },
  "fields": ["id", "title", "created_at"]
}
```

### Implementation Details

#### Configuration Functions

**`AshTypescript.Rpc.require_tenant_parameters?/0`**
Returns the configured tenant parameter mode:
```elixir
def require_tenant_parameters? do
  Application.get_env(:ash_typescript, :require_tenant_parameters, true)
end
```

**`AshTypescript.Rpc.requires_tenant?/1`** 
Determines if a resource has multitenancy configured:
```elixir
def requires_tenant?(resource) do
  strategy = Ash.Resource.Info.multitenancy_strategy(resource)
  
  case strategy do
    strategy when strategy in [:attribute, :context] ->
      not Ash.Resource.Info.multitenancy_global?(resource)
    _ ->
      false
  end
end
```

**`AshTypescript.Rpc.requires_tenant_parameter?/1`**
Combines resource tenancy with configuration to determine if tenant parameters should be generated:
```elixir
def requires_tenant_parameter?(resource) do
  requires_tenant?(resource) && require_tenant_parameters?()
end
```

#### Tenant Resolution Logic
When processing RPC requests, the system determines tenant using:

```elixir
tenant = 
  if requires_tenant_parameter?(resource) do
    # Extract from request parameters
    case Map.get(params, "tenant") do
      nil -> raise "Tenant parameter is required..."
      tenant_value -> tenant_value
    end
  else
    # Extract from connection context
    Ash.PlugHelpers.get_tenant(conn)
  end
```

#### Generated Code Impact
- **Config Types**: Include `tenant: string` field only when `requires_tenant_parameter?/1` returns true
- **Payload Builders**: Conditionally include tenant in request payload
- **Validation Functions**: Accept tenant parameters based on configuration

### Error Handling

#### Missing Tenant Parameter (Parameter Mode)
When `require_tenant_parameters: true`:
```
Tenant parameter is required for resource MyApp.Post but was not provided
```

**Solution**: Ensure client code passes the `tenant` field in the config object.

#### Missing Tenant Context (Connection Mode)
When `require_tenant_parameters: false` and no tenant is set on the connection:
- The system calls `Ash.PlugHelpers.get_tenant(conn)` which may return `nil`
- Ash will handle tenant validation based on resource configuration
- Ensure tenant is set using `Ash.PlugHelpers.set_tenant/2` in your pipeline

#### Invalid Tenant
Tenant validation happens at the Ash level according to your resource's authorization policies and multitenancy configuration.

### Backward Compatibility

- **Full backward compatibility**: Default `require_tenant_parameters: true` maintains existing behavior
- Non-multitenant resources work exactly as before
- Resources with `global? true` work without tenant parameters  
- Existing TypeScript client code remains unchanged when using default configuration
- Applications can opt into connection-based mode without breaking changes to non-multitenant resources

## Field Name Formatting

The RPC system provides comprehensive field name formatting to ensure consistent naming conventions between your Elixir backend and TypeScript frontend. This system handles field name conversion at three key points: TypeScript generation, input parsing, and response formatting.

### Overview

Field formatting allows you to:
- Use camelCase field names in your TypeScript client while keeping snake_case in Elixir
- Support different naming conventions (kebab-case, PascalCase, etc.)
- Implement custom formatting logic for specialized requirements
- Maintain consistency across all API interactions

### Configuration

Field formatting is configured at the application level in your `config.exs`:

```elixir
config :ash_typescript,
  input_field_formatter: :camel_case,   # Client input → internal parsing
  output_field_formatter: :camel_case   # TypeScript generation & response formatting
```

### Built-in Formatters

AshTypescript includes four built-in formatters:

| Formatter | Example Transform | Use Case |
|-----------|------------------|----------|
| `:camel_case` | `user_name` → `userName` | JavaScript/TypeScript standard |
| `:kebab_case` | `user_name` → `user-name` | HTML attributes, CSS classes |
| `:pascal_case` | `user_name` → `UserName` | Class names, enum values |
| `:snake_case` | `user_name` → `user_name` | Keep original Elixir format |

### Custom Formatters

For specialized requirements, you can implement custom formatter functions:

```elixir
config :ash_typescript,
  input_field_formatter: {MyApp.Formatters, :parse_custom_input},
  output_field_formatter: {MyApp.Formatters, :format_output, ["api_v1"]}
```

Custom formatter function signatures:
```elixir
# Simple formatter: field_name -> formatted_name
def parse_custom_input(field_name) when is_binary(field_name)

# Formatter with extra arguments  
def format_output(field_name, prefix) when is_binary(field_name)
```

### Formatter Integration Points

#### 1. Input Parameter Parsing

The `input_field_formatter` converts client field names to internal Elixir atoms:

```elixir
# RPC request processing
def run_action(otp_app, conn, params) do
  # Client input: %{"userName" => "John", "emailAddress" => "john@example.com"}
  raw_input = Map.get(params, "input", %{})
  input = AshTypescript.FieldFormatter.parse_input_fields(raw_input, input_field_formatter())
  # Result: %{user_name: "John", email_address: "john@example.com"}
  
  # Field selection parsing
  client_fields = Map.get(params, "fields", [])
  internal_fields = Enum.map(client_fields, &AshTypescript.FieldFormatter.parse_input_field(&1, input_field_formatter()))
  # Client: ["userName", "emailAddress"] → Internal: [:user_name, :email_address]
end
```

#### 2. TypeScript Type Generation & Response Formatting

The `output_field_formatter` controls both generated TypeScript types and API response field names:

```elixir
# Configuration
config :ash_typescript, output_field_formatter: :camel_case
```

**Generated TypeScript types:**
```typescript
// Generated TypeScript (with :camel_case)
type UserFieldsSchema = {
  userName: string;
  emailAddress?: string;
  createdAt: UtcDateTime;
  updatedAt: UtcDateTime;
};

type CreateUserConfig = {
  fields: FieldSelection<UserResourceSchema>[];
  calculations?: Partial<UserResourceSchema["complexCalculations"]>;
  input: {
    userName: string;
    emailAddress?: string;
  };
};
```

**API response formatting:**
```elixir
# Response processing
def run_action(otp_app, conn, params) do
  # ... action execution ...
  
  {:ok, result} ->
    return_value = extract_return_value(result, fields_to_take, calculation_field_specs)
    formatted_return_value = format_response_fields(return_value, output_field_formatter())
    %{success: true, data: formatted_return_value}
end

# Internal result: %{user_name: "John", email_address: "john@example.com", created_at: ~U[...]}
# Formatted response: %{"userName" => "John", "emailAddress" => "john@example.com", "createdAt" => "..."}
```

This unified approach ensures that TypeScript types always match the actual API responses, eliminating potential mismatches between generated types and runtime data.

### Field Formatting Flow

Here's how field names are transformed throughout an RPC request:

```
1. Client Request (TypeScript)
   fields: ["userName", "emailAddress"]
   input: {userName: "John", emailAddress: "john@example.com"}
   
2. Input Parsing (input_field_formatter)
   fields: [:user_name, :email_address]
   input: %{user_name: "John", email_address: "john@example.com"}
   
3. Ash Processing (Internal)
   Changeset with snake_case atoms: %{user_name: "John", email_address: "john@example.com"}
   
4. Response Formatting (output_field_formatter)
   {userName: "John", emailAddress: "john@example.com", createdAt: "2023-..."}
   
5. Client Response (TypeScript) - Matches Generated Types
   user.userName        // "John" - Same format as TypeScript types
   user.emailAddress    // "john@example.com" - Same format as TypeScript types
   user.createdAt       // "2023-..." - Same format as TypeScript types
```

### Implementation Details

#### Formatter Function Interface

The `AshTypescript.FieldFormatter` module provides the core formatting functionality:

```elixir
# Format a single field name
AshTypescript.FieldFormatter.format_field(:user_name, :camel_case)
# => "userName"

# Parse input field name to internal format
AshTypescript.FieldFormatter.parse_input_field("userName", :camel_case)
# => :user_name

# Format all keys in a map
AshTypescript.FieldFormatter.format_fields(%{user_name: "John"}, :camel_case)
# => %{"userName" => "John"}

# Parse all keys in an input map
AshTypescript.FieldFormatter.parse_input_fields(%{"userName" => "John"}, :camel_case)
# => %{user_name: "John"}
```

#### Configuration Access

The RPC system provides configuration accessor functions:

```elixir
# Get current formatter configurations
AshTypescript.Rpc.input_field_formatter()    # => :camel_case
AshTypescript.Rpc.output_field_formatter()   # => :camel_case
```

#### Error Handling

The formatting system includes comprehensive error handling:

```elixir
# Invalid formatter configuration
AshTypescript.FieldFormatter.format_field(:user_name, :invalid_formatter)
# => ArgumentError: "Unsupported formatter: :invalid_formatter"

# Custom formatter function errors
AshTypescript.FieldFormatter.format_field(:user_name, {MyModule, :broken_function})
# => Propagates the original error from MyModule.broken_function/1
```

### TypeScript Payload Builder Integration

Generated payload builders use formatted field names consistently:

```typescript
// Generated with :camel_case formatter
export function buildCreateUserPayload(config: CreateUserConfig): Record<string, any> {
  const payload: Record<string, any> = {
    action: "create_user",
    fields: config.fields,  // Uses formatted "fields" name
    input: config.input
  };

  if (config.calculations) {
    payload.calculations = config.calculations;  // Uses formatted "calculations" name
  }

  return payload;
}
```

### Validation and Testing

The field formatting system includes extensive test coverage:

#### Unit Tests
- All built-in formatters with various input types
- Custom formatter integration
- Error handling for invalid configurations
- Edge cases (empty strings, special characters)

#### Integration Tests  
- End-to-end RPC calls with different formatters
- TypeScript generation with formatted field names
- Input parsing and response formatting
- Multi-action workflows with consistent formatting

#### Configuration Tests
- Dynamic configuration changes
- Default value handling
- Invalid configuration graceful degradation

### Migration Guide

#### Migrating Existing Applications

For existing applications, field formatting is backward compatible:

```elixir
# Default configuration maintains existing behavior
config :ash_typescript,
  input_field_formatter: :camel_case,   # Default - existing input parsing unchanged
  output_field_formatter: :camel_case   # Default - existing TS generation & responses unchanged
```

#### Enabling Different Formatting

To migrate to a different naming convention:

1. **Choose your formatters** based on client requirements:
   ```elixir
   config :ash_typescript,
     input_field_formatter: :kebab_case,    # Match client input naming
     output_field_formatter: :kebab_case    # HTML/CSS friendly types & responses
   ```

2. **Regenerate TypeScript types**:
   ```bash
   mix ash_typescript.codegen
   ```

3. **Update client code** to use new field naming convention:
   ```typescript
   // Before (camelCase)
   await createUser({
     fields: ["userName", "emailAddress"],
     input: {userName: "John", emailAddress: "john@example.com"}
   });

   // After (kebab-case)
   await createUser({
     fields: ["user-name", "email-address"],
     input: {"user-name": "John", "email-address": "john@example.com"}
   });
   ```

#### Gradual Migration

For gradual migration, you can use different formatters for input and output:

```elixir
config :ash_typescript,
  input_field_formatter: :camel_case,       # Still accept camelCase input
  output_field_formatter: :kebab_case     # New TS types & responses use kebab-case
```

This allows you to update your TypeScript types and API responses together while maintaining backward compatibility for client input. Since TypeScript types and API responses always match, you'll need to update both client input/output handling and regenerate types simultaneously.

### Troubleshooting

#### Common Issues

**Field Not Found Errors**
```
Error: Field 'userName' not found in resource
```
**Cause**: Input formatter not converting client field names to internal format
**Solution**: Verify `input_field_formatter` configuration matches client naming convention

**TypeScript Compilation Errors**
```
Property 'user_name' does not exist on type 'UserSchema'
```
**Cause**: TypeScript types use different formatting than client code expects  
**Solution**: Ensure `output_field_formatter` matches your TypeScript naming convention

**Response Field Missing**
```
Client code: user.userName // undefined
Server response: {user_name: "John"}
```
**Cause**: Output formatter not converting response field names to match TypeScript types
**Solution**: Configure `output_field_formatter` to match client expectations

#### Debug Techniques

**Verify Configuration**:
```elixir
# In IEx
AshTypescript.Rpc.input_field_formatter()
AshTypescript.Rpc.output_field_formatter()
```

**Test Formatter Functions**:
```elixir
# Test field name conversion
AshTypescript.FieldFormatter.format_field("user_name", :camel_case)
AshTypescript.FieldFormatter.parse_input_field("userName", :camel_case)
```

**Trace RPC Processing**:
```elixir
# Add logging to see field name transformations
Logger.info("Client fields: #{inspect(client_fields)}")
Logger.info("Internal fields: #{inspect(internal_fields)}")
Logger.info("Response fields: #{inspect(Map.keys(formatted_response))}")
```

### RPC Operation Structure

#### Update Operation Structure

Update operations in the RPC system require a specific parameter structure that differs from create operations:

**✅ Correct Update Structure:**
```elixir
%{
  "action" => "update_user_settings",
  "primary_key" => record_id,        # Which record to update
  "input" => %{"theme" => "dark"},   # What changes to make  
  "tenant" => user_id,               # Tenant context (if required)
  "fields" => ["id", "theme"]        # Which fields to return
}
```

**❌ Incorrect Update Structure:**
```elixir
%{
  "action" => "update_user_settings",
  "input" => %{
    "id" => record_id,               # Wrong: ID should be in primary_key
    "theme" => "dark"
  },
  "tenant" => user_id,
  "fields" => ["id", "theme"]
}
```

#### Why This Structure Matters

The RPC layer processes updates in two steps:
1. **Fetch the record**: `Ash.get(resource, params["primary_key"], opts)`
2. **Apply changes**: Uses `params["input"]` for field updates

**Critical separation:**
- `"primary_key"` → **Which record** to operate on
- `"input"` → **What changes** to apply
- `"tenant"` → **Security context** for the operation

#### Common Update Error

**Error**: `record with id: nil not found`

**Cause**: Passing the record ID in `"input"` instead of `"primary_key"`

**Solution**: Move the ID to the `"primary_key"` field and remove it from `"input"`

#### Create vs Update Comparison

**Create Operations** (no existing record):
```elixir
%{
  "action" => "create_user_settings",
  "input" => %{
    "user_id" => user_id,            # All data goes in input
    "theme" => "dark"
  },
  "tenant" => user_id
}
```

**Update Operations** (existing record):
```elixir
%{
  "action" => "update_user_settings", 
  "primary_key" => record_id,        # Identify existing record
  "input" => %{
    "theme" => "dark"                # Only fields being changed
  },
  "tenant" => user_id
}
```

### Debugging Techniques

#### Isolating RPC Issues
When debugging calculation problems:
1. **Test direct Ash calls first**: Use `Ash.Query.load/2` directly to verify the calculation works
2. **Create minimal RPC test**: Replicate the exact RPC request in a test
3. **Check argument format**: Inspect what the RPC layer passes to `Ash.Query.load/2`
4. **Verify atom conversion**: Ensure string arguments convert to expected atoms

#### Update Operation Debugging
When debugging update failures:
1. **Verify primary_key structure**: Ensure ID is in `"primary_key"`, not `"input"`
2. **Check tenant context**: For multitenant resources, verify tenant is passed correctly
3. **Test record exists**: Confirm the record can be fetched with `Ash.get/3` using the same parameters
4. **Validate input changes**: Ensure only updatable fields are in `"input"`

#### Example Debug Test
```elixir
test "debug calculation arguments" do
  # Test direct Ash usage
  query = Todo |> Ash.Query.load(self: %{prefix: "test"})

  # Test RPC conversion
  params = %{
    "calculations" => %{
      "self" => %{"calcArgs" => %{"prefix" => "test"}}
    }
  }
  result = Rpc.run_action(:my_domain, conn, params)
end

test "debug update operation structure" do
  # Create a record first
  create_params = %{
    "action" => "create_todo",
    "input" => %{"title" => "Test Todo", "user_id" => user_id},
    "fields" => ["id"]
  }
  
  create_result = Rpc.run_action(:my_domain, conn, create_params)
  %{data: %{id: record_id}} = create_result
  
  # Test update with correct structure
  update_params = %{
    "action" => "update_todo",
    "primary_key" => record_id,      # ✅ Correct: ID in primary_key
    "input" => %{"title" => "Updated"}, # ✅ Correct: Only changes in input
    "fields" => ["id", "title"]
  }
  
  result = Rpc.run_action(:my_domain, conn, update_params)
  assert %{success: true} = result
end
```
