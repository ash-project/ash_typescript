defmodule AshTypescript.CodegenTest.Todo do
  use Ash.Resource,
    domain: AshTypescript.CodegenTest.Domain,
    data_layer: Ash.DataLayer.Ets

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

    attribute :status, :atom do
      constraints one_of: [:pending, :ongoing, :finished, :cancelled]
      public? true
    end

    attribute :priority, :atom do
      constraints one_of: [:low, :medium, :high, :urgent]
      public? true
    end

    attribute :due_date, :date do
      public? true
    end

    attribute :tags, {:array, :string} do
      public? true
    end

    attribute :metadata, :map do
      public? true
    end

    attribute :user_id, :uuid do
      allow_nil? false
      public? true
    end
  end

  relationships do
    has_many :comments, AshTypescript.CodegenTest.Comment do
      public? false
    end
  end

  aggregates do
    count :comment_count, :comments do
      public? true
    end
  end

  calculations do
    calculate :is_overdue, :boolean, expr(true) do
      public? true
    end

    calculate :days_remaining, :integer, expr(5) do
      public? true
    end
  end

  actions do
    defaults [:read, :create, :update, :destroy]
  end
end

defmodule AshTypescript.CodegenTest.Comment do
  use Ash.Resource,
    domain: AshTypescript.CodegenTest.Domain,
    data_layer: Ash.DataLayer.Ets

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
      public? true
    end

    attribute :is_helpful, :boolean do
      public? true
    end

    attribute :todo_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :user_id, :uuid do
      allow_nil? false
      public? true
    end
  end

  actions do
    defaults [:read, :create, :update, :destroy]
  end
end

defmodule AshTypescript.CodegenTest.Domain do
  use Ash.Domain

  resources do
    resource AshTypescript.CodegenTest.Todo
    resource AshTypescript.CodegenTest.Comment
  end
end