# Filter Usage Examples

This document shows how to use the filter functionality with AshTypescript RPC actions.

## 1. Define RPC Actions in Your Domain

First, configure your domain to expose RPC actions:

```elixir
defmodule MyApp.Blog do
  use Ash.Domain,
    extensions: [AshTypescript.RPC]

  rpc do
    resource MyApp.Blog.Post do
      rpc_action :list_posts, :read
      rpc_action :get_post, :read
    end

    resource MyApp.Blog.User do
      rpc_action :list_users, :read
    end
  end

  resources do
    resource MyApp.Blog.Post
    resource MyApp.Blog.User
    resource MyApp.Blog.Comment
  end
end
```

## 2. Define Your Resources

```elixir
defmodule MyApp.Blog.Post do
  use Ash.Resource,
    domain: MyApp.Blog,
    data_layer: AshPostgres.DataLayer

  attributes do
    uuid_primary_key :id
    attribute :title, :string, allow_nil?: false
    attribute :content, :string
    attribute :published_at, :utc_datetime
    attribute :status, :atom do
      constraints one_of: [:draft, :published, :archived]
    end
    attribute :view_count, :integer, default: 0
  end

  relationships do
    belongs_to :author, MyApp.Blog.User
    has_many :comments, MyApp.Blog.Comment
  end

  actions do
    defaults [:create, :read, :update, :destroy]

    read :read do
      primary? true
    end
  end
end

defmodule MyApp.Blog.User do
  use Ash.Resource,
    domain: MyApp.Blog,
    data_layer: AshPostgres.DataLayer

  attributes do
    uuid_primary_key :id
    attribute :email, :string, allow_nil?: false
    attribute :name, :string
    attribute :role, :atom do
      constraints one_of: [:user, :admin, :moderator]
    end
    attribute :created_at, :utc_datetime, default: &DateTime.utc_now/0
  end

  relationships do
    has_many :posts, MyApp.Blog.Post, destination_attribute: :author_id
  end

  actions do
    defaults [:create, :read, :update, :destroy]
  end
end

defmodule MyApp.Blog.Comment do
  use Ash.Resource,
    domain: MyApp.Blog,
    data_layer: AshPostgres.DataLayer

  attributes do
    uuid_primary_key :id
    attribute :content, :string, allow_nil?: false
    attribute :created_at, :utc_datetime, default: &DateTime.utc_now/0
    attribute :approved, :boolean, default: false
  end

  relationships do
    belongs_to :post, MyApp.Blog.Post
    belongs_to :author, MyApp.Blog.User
  end

  actions do
    defaults [:create, :read, :update, :destroy]
  end
end
```

## 3. Generate TypeScript Types

Run your RPC codegen to generate TypeScript types:

```elixir
# In your application code
AshTypescript.RPC.Codegen.generate_typescript_types(:my_app, rpc_specs)
```

This will generate filter types like:

```typescript
export type PostFilterInput = {
  and?: Array<PostFilterInput>;
  or?: Array<PostFilterInput>;
  not?: Array<PostFilterInput>;
  id?: {
    eq?: string;
    notEq?: string;
    in?: Array<string>;
    notIn?: Array<string>;
  };
  title?: {
    eq?: string;
    notEq?: string;
    in?: Array<string>;
    notIn?: Array<string>;
  };
  content?: {
    eq?: string;
    notEq?: string;
    in?: Array<string>;
    notIn?: Array<string>;
  };
  published_at?: {
    eq?: string;
    notEq?: string;
    greaterThan?: string;
    greaterThanOrEqual?: string;
    lessThan?: string;
    lessThanOrEqual?: string;
    in?: Array<string>;
    notIn?: Array<string>;
  };
  status?: {
    eq?: "draft" | "published" | "archived";
    notEq?: "draft" | "published" | "archived";
    in?: Array<"draft" | "published" | "archived">;
    notIn?: Array<"draft" | "published" | "archived">;
  };
  view_count?: {
    eq?: number;
    notEq?: number;
    greaterThan?: number;
    greaterThanOrEqual?: number;
    lessThan?: number;
    lessThanOrEqual?: number;
    in?: Array<number>;
    notIn?: Array<number>;
  };
  author?: UserFilterInput;
  comments?: CommentFilterInput;
};

export type UserFilterInput = {
  and?: Array<UserFilterInput>;
  or?: Array<UserFilterInput>;
  not?: Array<UserFilterInput>;
  id?: {
    eq?: string;
    notEq?: string;
    in?: Array<string>;
    notIn?: Array<string>;
  };
  email?: {
    eq?: string;
    notEq?: string;
    in?: Array<string>;
    notIn?: Array<string>;
  };
  name?: {
    eq?: string;
    notEq?: string;
    in?: Array<string>;
    notIn?: Array<string>;
  };
  role?: {
    eq?: "user" | "admin" | "moderator";
    notEq?: "user" | "admin" | "moderator";
    in?: Array<"user" | "admin" | "moderator">;
    notIn?: Array<"user" | "admin" | "moderator">;
  };
  created_at?: {
    eq?: string;
    notEq?: string;
    greaterThan?: string;
    greaterThanOrEqual?: string;
    lessThan?: string;
    lessThanOrEqual?: string;
    in?: Array<string>;
    notIn?: Array<string>;
  };
  posts?: PostFilterInput;
};
```

## 4. Usage Examples

### Basic Field Filtering

```typescript
// Filter posts by status
const filter: PostFilterInput = {
  status: { eq: "published" }
};

const posts = await listPosts({}, filter);
```

### Numeric Comparisons

```typescript
// Filter posts with more than 100 views
const filter: PostFilterInput = {
  view_count: { greaterThan: 100 }
};

const popularPosts = await listPosts({}, filter);
```

### Date Range Filtering

```typescript
// Filter posts published in the last week
const oneWeekAgo = new Date();
oneWeekAgo.setDate(oneWeekAgo.getDate() - 7);

const filter: PostFilterInput = {
  published_at: { 
    greaterThanOrEqual: oneWeekAgo.toISOString() 
  }
};

const recentPosts = await listPosts({}, filter);
```

### Array Filtering

```typescript
// Filter posts by multiple statuses
const filter: PostFilterInput = {
  status: { in: ["published", "archived"] }
};

const visiblePosts = await listPosts({}, filter);
```

### Relationship Filtering

```typescript
// Filter posts by author properties
const filter: PostFilterInput = {
  author: {
    role: { eq: "admin" },
    email: { notEq: "banned@example.com" }
  }
};

const adminPosts = await listPosts({}, filter);
```

### Complex Logical Operations

```typescript
// Complex AND/OR combinations
const filter: PostFilterInput = {
  and: [
    {
      status: { eq: "published" }
    },
    {
      or: [
        {
          view_count: { greaterThan: 1000 }
        },
        {
          author: {
            role: { eq: "admin" }
          }
        }
      ]
    }
  ]
};

const featuredPosts = await listPosts({}, filter);
```

### NOT Operations

```typescript
// Filter posts that are NOT drafts and NOT by banned users
const filter: PostFilterInput = {
  not: [
    {
      status: { eq: "draft" }
    },
    {
      author: {
        email: { in: ["banned1@example.com", "banned2@example.com"] }
      }
    }
  ]
};

const validPosts = await listPosts({}, filter);
```

### Nested Relationship Filtering

```typescript
// Filter posts that have approved comments by moderators
const filter: PostFilterInput = {
  comments: {
    and: [
      {
        approved: { eq: true }
      },
      {
        author: {
          role: { eq: "moderator" }
        }
      }
    ]
  }
};

const moderatedPosts = await listPosts({}, filter);
```

## 5. Complete Usage Example

```typescript
import { 
  listPosts, 
  PostFilterInput,
  ListPostsReturn 
} from './generated/rpc-types';

async function getPopularRecentPosts(): Promise<ListPostsReturn> {
  const filter: PostFilterInput = {
    and: [
      // Only published posts
      {
        status: { eq: "published" }
      },
      // Published in the last 30 days
      {
        published_at: {
          greaterThanOrEqual: new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString()
        }
      },
      // Either high view count OR by admin authors
      {
        or: [
          {
            view_count: { greaterThan: 500 }
          },
          {
            author: {
              role: { eq: "admin" }
            }
          }
        ]
      }
    ]
  };

  try {
    const result = await listPosts({}, filter);
    
    if (result.success) {
      return result.data;
    } else {
      console.error('Failed to fetch posts:', result.error);
      return [];
    }
  } catch (error) {
    console.error('Error fetching posts:', error);
    return [];
  }
}
```

## 6. Server-Side RPC Configuration

Make sure your RPC endpoint can handle filters:

```elixir
# In your Phoenix controller or plug
def handle_rpc(conn, params) do
  case AshTypescript.RPC.run_action(:my_app, conn, params) do
    %{success: true, data: data} ->
      json(conn, %{success: true, data: data, error: nil})
    
    %{success: false, error: error} ->
      conn
      |> put_status(400)
      |> json(%{success: false, data: nil, error: error})
  end
end
```

The filter will be automatically applied to read actions when the `filter` parameter is provided in the RPC payload.