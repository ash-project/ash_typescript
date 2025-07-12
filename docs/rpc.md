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