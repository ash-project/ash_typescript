defmodule AshTypescript.Examples.TestFilter do
  @moduledoc """
  Comprehensive test example showing filter usage with AshTypescript RPC.
  
  This module demonstrates:
  - Setting up resources with various attribute types
  - Configuring RPC actions with filters
  - Testing filter translation from JSON to Ash queries
  - Generated TypeScript filter types
  """

  # Example Domain Configuration
  defmodule Blog do
    use Ash.Domain,
      extensions: [AshTypescript.RPC]

    rpc do
      resource Post do
        rpc_action :list_posts, :read
        rpc_action :get_post, :read
        rpc_action :search_posts, :read
      end

      resource User do
        rpc_action :list_users, :read
        rpc_action :find_user, :read
      end

      resource Comment do
        rpc_action :list_comments, :read
      end
    end

    resources do
      resource Post
      resource User
      resource Comment
    end
  end

  # Example Resources
  defmodule Post do
    use Ash.Resource,
      domain: Blog,
      data_layer: Ash.DataLayer.Ets

    ets do
      table :posts
    end

    attributes do
      uuid_primary_key :id
      
      attribute :title, :string do
        allow_nil? false
        constraints min_length: 1, max_length: 200
      end
      
      attribute :content, :string
      
      attribute :published_at, :utc_datetime
      
      attribute :status, :atom do
        constraints one_of: [:draft, :published, :archived, :deleted]
        default :draft
      end
      
      attribute :view_count, :integer do
        default 0
        constraints min: 0
      end
      
      attribute :rating, :float do
        constraints min: 0.0, max: 5.0
      end
      
      attribute :tags, {:array, :string}
      
      attribute :metadata, :map
      
      attribute :featured, :boolean do
        default false
      end
      
      attribute :created_at, :utc_datetime do
        default &DateTime.utc_now/0
      end
      
      attribute :updated_at, :utc_datetime do
        default &DateTime.utc_now/0
      end
    end

    relationships do
      belongs_to :author, User do
        allow_nil? false
      end
      
      has_many :comments, Comment do
        destination_attribute :post_id
      end
    end

    actions do
      defaults [:create, :read, :update, :destroy]

      read :read do
        primary? true
      end

      read :search_posts do
        pagination offset?: true, keyset?: true, required?: false
      end
    end
  end

  defmodule User do
    use Ash.Resource,
      domain: Blog,
      data_layer: Ash.DataLayer.Ets

    ets do
      table :users
    end

    attributes do
      uuid_primary_key :id
      
      attribute :email, :string do
        allow_nil? false
        constraints format: ~r/^[^\s]+@[^\s]+\.[^\s]+$/
      end
      
      attribute :username, :string do
        allow_nil? false
        constraints min_length: 3, max_length: 50
      end
      
      attribute :name, :string
      
      attribute :role, :atom do
        constraints one_of: [:user, :admin, :moderator, :editor]
        default :user
      end
      
      attribute :age, :integer do
        constraints min: 13, max: 120
      end
      
      attribute :active, :boolean do
        default true
      end
      
      attribute :last_login_at, :utc_datetime
      
      attribute :created_at, :utc_datetime do
        default &DateTime.utc_now/0
      end
      
      attribute :preferences, :map
    end

    relationships do
      has_many :posts, Post do
        destination_attribute :author_id
      end
      
      has_many :comments, Comment do
        destination_attribute :author_id
      end
    end

    actions do
      defaults [:create, :read, :update, :destroy]
    end
  end

  defmodule Comment do
    use Ash.Resource,
      domain: Blog,
      data_layer: Ash.DataLayer.Ets

    ets do
      table :comments
    end

    attributes do
      uuid_primary_key :id
      
      attribute :content, :string do
        allow_nil? false
        constraints min_length: 1, max_length: 1000
      end
      
      attribute :approved, :boolean do
        default false
      end
      
      attribute :rating, :integer do
        constraints min: 1, max: 5
      end
      
      attribute :created_at, :utc_datetime do
        default &DateTime.utc_now/0
      end
    end

    relationships do
      belongs_to :post, Post do
        allow_nil? false
      end
      
      belongs_to :author, User do
        allow_nil? false
      end
    end

    actions do
      defaults [:create, :read, :update, :destroy]
    end
  end

  # Test Filter Translation
  def test_filter_translation do
    IO.puts("=== Testing Filter Translation ===\n")

    # Test basic equality filter
    test_basic_filters()
    
    # Test comparison filters
    test_comparison_filters()
    
    # Test array filters
    test_array_filters()
    
    # Test logical operators
    test_logical_operators()
    
    # Test relationship filters
    test_relationship_filters()
    
    # Test complex nested filters
    test_complex_filters()
  end

  defp test_basic_filters do
    IO.puts("1. Basic Equality Filters:")
    
    # String equality
    filter_json = %{"title" => %{"eq" => "Hello World"}}
    result = AshTypescript.Filter.translate_filter(filter_json, Post)
    IO.inspect(result, label: "String eq filter")
    
    # Enum equality
    filter_json = %{"status" => %{"eq" => "published"}}
    result = AshTypescript.Filter.translate_filter(filter_json, Post)
    IO.inspect(result, label: "Enum eq filter")
    
    # Boolean equality
    filter_json = %{"featured" => %{"eq" => true}}
    result = AshTypescript.Filter.translate_filter(filter_json, Post)
    IO.inspect(result, label: "Boolean eq filter")
    
    # String not equal
    filter_json = %{"title" => %{"notEq" => "Spam"}}
    result = AshTypescript.Filter.translate_filter(filter_json, Post)
    IO.inspect(result, label: "String notEq filter")
    
    IO.puts("")
  end

  defp test_comparison_filters do
    IO.puts("2. Comparison Filters:")
    
    # Greater than
    filter_json = %{"view_count" => %{"greaterThan" => 100}}
    result = AshTypescript.Filter.translate_filter(filter_json, Post)
    IO.inspect(result, label: "Greater than filter")
    
    # Less than or equal
    filter_json = %{"rating" => %{"lessThanOrEqual" => 4.5}}
    result = AshTypescript.Filter.translate_filter(filter_json, Post)
    IO.inspect(result, label: "Less than or equal filter")
    
    # Date comparison
    filter_json = %{"created_at" => %{"greaterThanOrEqual" => "2024-01-01T00:00:00Z"}}
    result = AshTypescript.Filter.translate_filter(filter_json, Post)
    IO.inspect(result, label: "Date comparison filter")
    
    IO.puts("")
  end

  defp test_array_filters do
    IO.puts("3. Array Filters:")
    
    # In array
    filter_json = %{"status" => %{"in" => ["published", "archived"]}}
    result = AshTypescript.Filter.translate_filter(filter_json, Post)
    IO.inspect(result, label: "In array filter")
    
    # Not in array
    filter_json = %{"status" => %{"notIn" => ["draft", "deleted"]}}
    result = AshTypescript.Filter.translate_filter(filter_json, Post)
    IO.inspect(result, label: "Not in array filter")
    
    IO.puts("")
  end

  defp test_logical_operators do
    IO.puts("4. Logical Operators:")
    
    # AND operation
    filter_json = %{
      "and" => [
        %{"status" => %{"eq" => "published"}},
        %{"view_count" => %{"greaterThan" => 50}}
      ]
    }
    result = AshTypescript.Filter.translate_filter(filter_json, Post)
    IO.inspect(result, label: "AND filter")
    
    # OR operation
    filter_json = %{
      "or" => [
        %{"featured" => %{"eq" => true}},
        %{"rating" => %{"greaterThan" => 4.0}}
      ]
    }
    result = AshTypescript.Filter.translate_filter(filter_json, Post)
    IO.inspect(result, label: "OR filter")
    
    # NOT operation
    filter_json = %{
      "not" => [
        %{"status" => %{"eq" => "deleted"}}
      ]
    }
    result = AshTypescript.Filter.translate_filter(filter_json, Post)
    IO.inspect(result, label: "NOT filter")
    
    IO.puts("")
  end

  defp test_relationship_filters do
    IO.puts("5. Relationship Filters:")
    
    # Filter by author properties
    filter_json = %{
      "author" => %{
        "role" => %{"eq" => "admin"}
      }
    }
    result = AshTypescript.Filter.translate_filter(filter_json, Post)
    IO.inspect(result, label: "Author role filter")
    
    # Filter by author with multiple conditions
    filter_json = %{
      "author" => %{
        "and" => [
          %{"active" => %{"eq" => true}},
          %{"role" => %{"in" => ["admin", "moderator"]}}
        ]
      }
    }
    result = AshTypescript.Filter.translate_filter(filter_json, Post)
    IO.inspect(result, label: "Complex author filter")
    
    IO.puts("")
  end

  defp test_complex_filters do
    IO.puts("6. Complex Nested Filters:")
    
    # Complex filter with multiple logical operations
    filter_json = %{
      "and" => [
        %{"status" => %{"eq" => "published"}},
        %{
          "or" => [
            %{"view_count" => %{"greaterThan" => 1000}},
            %{
              "author" => %{
                "role" => %{"eq" => "admin"}
              }
            }
          ]
        },
        %{
          "not" => [
            %{"title" => %{"in" => ["Spam", "Test"]}}
          ]
        }
      ]
    }
    result = AshTypescript.Filter.translate_filter(filter_json, Post)
    IO.inspect(result, label: "Complex nested filter")
    
    IO.puts("")
  end

  # Generate TypeScript Types Example
  def generate_example_types do
    IO.puts("=== Generated TypeScript Filter Types ===\n")
    
    IO.puts("Post Filter Type:")
    post_filter = AshTypescript.Filter.generate_filter_type(Post)
    IO.puts(post_filter)
    
    IO.puts("User Filter Type:")
    user_filter = AshTypescript.Filter.generate_filter_type(User)
    IO.puts(user_filter)
    
    IO.puts("Comment Filter Type:")
    comment_filter = AshTypescript.Filter.generate_filter_type(Comment)
    IO.puts(comment_filter)
  end

  # Example RPC Specs for testing
  def example_rpc_specs do
    [
      %{
        "action" => "list_posts",
        "select" => ["id", "title", "content", "status", "view_count", "created_at"],
        "load" => ["author"]
      },
      %{
        "action" => "search_posts", 
        "select" => ["id", "title", "status", "rating"],
        "load" => ["author", "comments"]
      },
      %{
        "action" => "list_users",
        "select" => ["id", "email", "username", "role", "active"],
        "load" => []
      }
    ]
  end

  # Example TypeScript usage that would be generated
  def example_typescript_usage do
    """
    // Example TypeScript usage:

    // 1. Basic filtering
    const basicFilter: PostFilterInput = {
      status: { eq: "published" },
      featured: { eq: true }
    };

    // 2. Numeric comparisons
    const popularPostsFilter: PostFilterInput = {
      and: [
        { status: { eq: "published" } },
        { view_count: { greaterThan: 100 } },
        { rating: { greaterThanOrEqual: 4.0 } }
      ]
    };

    // 3. Date range filtering
    const recentPostsFilter: PostFilterInput = {
      created_at: {
        greaterThanOrEqual: "2024-01-01T00:00:00Z",
        lessThan: "2024-12-31T23:59:59Z"
      }
    };

    // 4. Complex relationship filtering
    const adminPostsFilter: PostFilterInput = {
      and: [
        { status: { eq: "published" } },
        {
          author: {
            and: [
              { role: { eq: "admin" } },
              { active: { eq: true } }
            ]
          }
        },
        {
          comments: {
            approved: { eq: true }
          }
        }
      ]
    };

    // 5. Using the generated functions
    async function getFilteredPosts() {
      const result = await listPosts({}, popularPostsFilter);
      
      if (result.success) {
        console.log('Posts:', result.data);
      } else {
        console.error('Error:', result.error);
      }
    }

    // 6. Advanced filtering with NOT operations
    const excludeSpamFilter: PostFilterInput = {
      and: [
        { status: { eq: "published" } },
        {
          not: [
            { title: { in: ["Spam", "Advertisement"] } },
            { 
              author: { 
                email: { in: ["spammer@example.com"] } 
              } 
            }
          ]
        }
      ]
    };
    """
  end

  # Test the complete flow
  def run_complete_test do
    IO.puts("=== AshTypescript Filter System Test ===\n")
    
    # Test filter translation
    test_filter_translation()
    
    # Generate TypeScript types
    generate_example_types()
    
    # Show example TypeScript usage
    IO.puts("=== Example TypeScript Usage ===")
    IO.puts(example_typescript_usage())
    
    # Test RPC codegen with filters
    IO.puts("=== Testing RPC Codegen with Filters ===")
    rpc_specs = example_rpc_specs()
    
    try do
      # Note: This would normally be called with a real OTP app
      # typescript_code = AshTypescript.RPC.Codegen.generate_typescript_types(:test_app, rpc_specs)
      # IO.puts(typescript_code)
      IO.puts("RPC Codegen would generate TypeScript functions with filter support")
    rescue
      e -> IO.puts("Codegen test skipped (requires full app setup): #{inspect(e)}")
    end
    
    IO.puts("\n=== Test Complete ===")
  end

  # Helper to create test data
  def create_test_data do
    # This would typically be called in tests to set up sample data
    # for testing the filter functionality
    
    users = [
      %{id: "user1", email: "admin@example.com", username: "admin", role: :admin, active: true},
      %{id: "user2", email: "user@example.com", username: "regularuser", role: :user, active: true},
      %{id: "user3", email: "mod@example.com", username: "moderator", role: :moderator, active: false}
    ]
    
    posts = [
      %{id: "post1", title: "Hello World", content: "First post", status: :published, 
        view_count: 150, rating: 4.5, featured: true, author_id: "user1"},
      %{id: "post2", title: "Draft Post", content: "Work in progress", status: :draft, 
        view_count: 0, rating: nil, featured: false, author_id: "user2"},
      %{id: "post3", title: "Popular Post", content: "Very popular", status: :published, 
        view_count: 1500, rating: 4.8, featured: true, author_id: "user1"}
    ]
    
    comments = [
      %{id: "comment1", content: "Great post!", approved: true, rating: 5, 
        post_id: "post1", author_id: "user2"},
      %{id: "comment2", content: "Needs work", approved: false, rating: 2, 
        post_id: "post2", author_id: "user3"}
    ]
    
    {users, posts, comments}
  end
end