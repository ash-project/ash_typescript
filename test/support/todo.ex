defmodule AshTypescript.Test.TodoStatus do
  use Ash.Type.Enum, values: [:pending, :ongoing, :finished, :cancelled]
end

defmodule SelfCalculation do
  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context) do
    []
  end

  @impl true
  def calculate(records, _opts, %{arguments: _arguments}) do
    # Just return the records unchanged for testing purposes
    # In a real implementation, you might modify based on the prefix argument
    records
  end
end

defmodule AshTypescript.Test.User do
  use Ash.Resource,
    domain: AshTypescript.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    primary_read_warning?: false

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :email, :string do
      allow_nil? false
      public? true
    end
  end

  relationships do
    has_many :comments, AshTypescript.Test.Comment do
      public? true
    end

    has_many :todos, AshTypescript.Test.Todo do
      public? true
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:email, :name]
    end

    update :update do
      accept [:name]
    end

    destroy :destroy do
      accept []
    end
  end

  calculations do
    calculate :self, :struct, SelfCalculation do
      constraints instance_of: __MODULE__
      public? true

      argument :prefix, :string do
        allow_nil? true
        default nil
      end
    end
  end
end

defmodule AshTypescript.Test.NotExposed do
  use Ash.Resource,
    domain: AshTypescript.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    primary_read_warning?: false

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :email, :string do
      allow_nil? false
      public? true
    end
  end

  relationships do
    belongs_to :todo, AshTypescript.Test.Todo do
      public? true
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:email, :name]
    end

    update :update do
      accept [:name]
    end

    destroy :destroy do
      accept []
    end
  end
end

defmodule AshTypescript.Test.Comment do
  use Ash.Resource,
    domain: AshTypescript.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    primary_read_warning?: false

  attributes do
    uuid_primary_key :id

    attribute :content, :string do
      allow_nil? false
      public? true
    end

    attribute :author_name, :string do
      allow_nil? false
      public? true
    end

    attribute :rating, :integer do
      constraints min: 1, max: 5
      public? true
    end

    attribute :is_helpful, :boolean do
      default false
      public? true
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :todo, AshTypescript.Test.Todo do
      allow_nil? false
      public? true
    end

    belongs_to :user, AshTypescript.Test.User do
      allow_nil? false
      public? true
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:content, :author_name, :rating, :is_helpful]

      argument :user_id, :uuid do
        allow_nil? false
        public? true
      end

      argument :todo_id, :uuid do
        allow_nil? false
        public? true
      end

      change manage_relationship(:user_id, :user, type: :append)
      change manage_relationship(:todo_id, :todo, type: :append)
    end

    update :update do
      accept [:content, :author_name, :rating, :is_helpful]
    end
  end
end

defmodule AshTypescript.Test.Todo do
  use Ash.Resource,
    domain: AshTypescript.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    primary_read_warning?: false

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      public? true
    end

    attribute :completed, :boolean do
      default false
      public? true
    end

    attribute :status, AshTypescript.Test.TodoStatus do
      default :pending
      public? true
    end

    attribute :priority, :atom do
      constraints one_of: [:low, :medium, :high, :urgent]
      default :medium
      public? true
    end

    attribute :due_date, :date do
      public? true
    end

    attribute :tags, {:array, :string} do
      default []
      public? true
    end

    attribute :metadata, :map do
      public? true
    end

    create_timestamp :created_at do
      public? true
    end

    update_timestamp :updated_at
  end

  relationships do
    belongs_to :user, AshTypescript.Test.User do
      allow_nil? false
      public? true
    end

    has_many :comments, AshTypescript.Test.Comment do
      public? true
    end

    has_many :not_exposed_items, AshTypescript.Test.NotExposed do
      public? true
    end
  end

  aggregates do
    count :comment_count, :comments do
      public? true
    end

    count :helpful_comment_count, :comments do
      public? true
      filter expr(is_helpful == true)
    end

    exists :has_comments, :comments

    avg :average_rating, :comments, :rating

    max :highest_rating, :comments, :rating

    first :latest_comment_content, :comments, :content do
      sort created_at: :desc
    end

    list :comment_authors, :comments, :author_name
  end

  calculations do
    calculate :is_overdue, :boolean, expr(not is_nil(due_date) and due_date < today()) do
      public? true
    end

    calculate :days_until_due,
              :integer,
              expr(if(is_nil(due_date), nil, date_diff(due_date, today(), :day))) do
      public? true
    end

    calculate :self, :struct, SelfCalculation do
      constraints instance_of: __MODULE__
      public? true

      argument :prefix, :string do
        allow_nil? true
        default nil
      end
    end
  end

  actions do
    defaults [:destroy]

    read :read do
      primary? true
      argument :filter_completed, :boolean

      argument :priority_filter, :atom do
        constraints one_of: [:low, :medium, :high, :urgent]
      end

      filter expr(
               if not is_nil(^arg(:filter_completed)) do
                 completed == ^arg(:filter_completed)
               else
                 true
               end and
                 if not is_nil(^arg(:priority_filter)) do
                   priority == ^arg(:priority_filter)
                 else
                   true
                 end
             )
    end

    read :get do
      get? true
      argument :id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id))
    end

    create :create do
      primary? true
      accept [:title, :description, :status, :priority, :due_date, :tags, :metadata]

      argument :auto_complete, :boolean do
        default false
      end

      argument :user_id, :uuid do
        allow_nil? false
      end

      change set_attribute(:completed, arg(:auto_complete))
      change manage_relationship(:user_id, :user, type: :append)
    end

    update :update do
      primary? true
      accept [:title, :description, :completed, :status, :priority, :due_date, :tags, :metadata]
    end

    update :complete do
      accept []
      change set_attribute(:completed, true)
    end

    update :set_priority do
      argument :priority, :atom do
        allow_nil? false
        constraints one_of: [:low, :medium, :high, :urgent]
      end

      change set_attribute(:priority, arg(:priority))
    end

    action :bulk_complete, {:array, :uuid} do
      argument :todo_ids, {:array, :uuid}, allow_nil?: false

      run fn input, _context ->
        # This would normally update multiple todos, but for testing we'll just return the IDs
        {:ok, input.arguments.todo_ids}
      end
    end

    action :get_statistics, :map do
      constraints fields: [
                    total: [type: :integer, allow_nil?: false],
                    completed: [type: :integer, allow_nil?: false],
                    pending: [type: :integer, allow_nil?: false],
                    overdue: [type: :integer, allow_nil?: false]
                  ]

      run fn _input, _context ->
        {:ok,
         %{
           total: 10,
           completed: 6,
           pending: 4,
           overdue: 2
         }}
      end
    end

    action :search, {:array, Ash.Type.Struct} do
      constraints items: [instance_of: __MODULE__]

      argument :query, :string, allow_nil?: false
      argument :include_completed, :boolean, default: true

      run fn _input, _context ->
        # This would normally search todos, but for testing we'll return empty
        {:ok, []}
      end
    end
  end
end

defmodule AshTypescript.Test.Domain do
  use Ash.Domain,
    otp_app: :ash_typescript,
    extensions: [AshTypescript.Rpc]

  rpc do
    resource AshTypescript.Test.Todo do
      rpc_action :list_todos, :read
      rpc_action :get_todo, :get
      rpc_action :create_todo, :create
      rpc_action :update_todo, :update
      rpc_action :complete_todo, :complete
      rpc_action :set_priority_todo, :set_priority
      rpc_action :bulk_complete_todo, :bulk_complete
      rpc_action :get_statistics_todo, :get_statistics
      rpc_action :search_todos, :search
      rpc_action :destroy_todo, :destroy
    end

    resource AshTypescript.Test.Comment do
      rpc_action :list_comments, :read
      rpc_action :create_comment, :create
      rpc_action :update_comment, :update
    end

    resource AshTypescript.Test.User do
      rpc_action :list_users, :read
      rpc_action :create_user, :create
      rpc_action :update_user, :update
    end
  end

  resources do
    resource AshTypescript.Test.Todo
    resource AshTypescript.Test.Comment
    resource AshTypescript.Test.User
    resource AshTypescript.Test.NotExposed
  end
end
