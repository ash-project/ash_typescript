defmodule AshTypescript.Test.TodoComment do
  use Ash.Resource,
    domain: AshTypescript.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    primary_read_warning?: false

  ets do
    private? true
  end

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
