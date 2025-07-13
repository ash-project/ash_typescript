# RPC System Core

The AshTypescript RPC extension provides DSL for exposing Ash resources as RPC endpoints with generated TypeScript clients.

## DSL Configuration

### Domain Setup
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
Defines which resource to expose via RPC and contains `rpc_action` definitions.

#### `rpc_action` definition
- **name**: TypeScript function name (camelCase recommended)
- **action**: Corresponding Ash resource action
- Creates type-safe client function

## Generated Client Functions

### Function Signatures
```typescript
// Create/update actions
async createPost(params: PostCreateInput): Promise<PostSchema>

// Read actions  
async listPosts(params?: PostListInput): Promise<PostSchema[]>

// Get actions
async getPost(id: string, params?: PostGetInput): Promise<PostSchema>

// Destroy actions
async deletePost(id: string): Promise<void>
```

### Generated Input Types
- **CreateInput**: Required and optional attributes for creation
- **UpdateInput**: All attributes optional except primary key
- **ListInput**: Filter, sort, pagination, load options
- **GetInput**: Load options for relationships

## Request/Response Format

### Request Structure
```typescript
{
  action: "MyApp.Blog.Post.create",
  input: { title: "New Post", body: "Content..." },
  load: ["author", "comments"],
  actor: { id: "user-123" }
}
```

### Response Format
```typescript
// Success
{ data: PostSchema, errors: null }

// Error
{ data: null, errors: ErrorSchema[] }
```

## Phoenix Integration

### Router Setup
```elixir
scope "/rpc" do
  pipe_through :api
  post "/run", AshRpcWeb.RpcController, :run
  post "/validate", AshRpcWeb.RpcController, :validate
end
```

### Security Integration
- All actions use normal Ash authorization
- Actor context passed in requests
- Policies apply to RPC calls
- No bypass of resource-level security

## Update Operations

Update operations require specific parameter structure:

### Correct Structure
```elixir
%{
  "action" => "update_user_settings",
  "primary_key" => record_id,        # Which record to update
  "input" => %{"theme" => "dark"},   # What changes to make
  "tenant" => user_id,               # Tenant context (if required)
  "fields" => ["id", "theme"]        # Which fields to return
}
```

### Processing Steps
1. **Fetch record**: `Ash.get(resource, params["primary_key"], opts)`
2. **Apply changes**: Uses `params["input"]` for field updates

### Key Separation
- `"primary_key"` → **Which record** to operate on
- `"input"` → **What changes** to apply
- `"tenant"` → **Security context** for the operation

## Error Handling

### Common Errors

**Missing Primary Key**: `record with id: nil not found`
- Cause: ID passed in `"input"` instead of `"primary_key"`
- Solution: Move ID to `"primary_key"` field

**Tenant Parameter Required**
- Cause: Multitenant resource without tenant parameter
- Solution: Include `"tenant"` field in request

**Field Not Found**
- Cause: Input formatter not converting field names
- Solution: Check `input_field_formatter` configuration

### Debug Techniques

```elixir
# Test direct Ash calls first
query = Resource |> Ash.Query.load(calculation: %{arg: value})

# Verify RPC parameter structure
params = %{
  "action" => "action_name",
  "primary_key" => id,  # For updates
  "input" => %{...},
  "fields" => [...]
}
```

## Generated Code Structure

### RPC Client Class
- `AshRpc` class with methods for each exposed action
- Handles HTTP requests to Phoenix endpoints
- Type-safe parameter validation
- Error handling and response transformation

### Action Methods
- Named according to `rpc_action` name
- Accept typed parameters
- Return typed responses
- Handle loading of relationships

## Operation Types

### Create Operations
```typescript
await createPost({
  fields: ["id", "title"],
  input: {
    title: "New Post",      // All data in input
    userId: "user-123"
  }
});
```

### Update Operations
```typescript
await updatePost({
  primaryKey: "post-456",   // Identify existing record
  fields: ["id", "title"],
  input: {
    title: "Updated Post"   // Only changed fields
  }
});
```

### Read Operations
```typescript
await listPosts({
  fields: ["id", "title"],
  filter: { published: true },
  sort: [{ field: "created_at", order: "desc" }],
  limit: 10
});
```

### Get Operations
```typescript
await getPost("post-123", {
  fields: ["id", "title", "body"],
  load: ["author", "comments"]
});
```