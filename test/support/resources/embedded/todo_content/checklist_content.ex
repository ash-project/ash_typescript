defmodule AshTypescript.Test.TodoContent.ChecklistContent do
  use Ash.Resource,
    data_layer: :embedded,
    domain: nil

  attributes do
    uuid_primary_key :id

    attribute :title, :string, public?: true, allow_nil?: false

    attribute :items, {:array, :map},
      public?: true,
      default: [],
      constraints: [
        items: [
          fields: [
            text: [type: :string, allow_nil?: false],
            completed: [type: :boolean],
            created_at: [type: :utc_datetime]
          ]
        ]
      ]

    attribute :allow_reordering, :boolean, public?: true, default: true
  end

  calculations do
    calculate :total_items, :integer, expr(length(items)) do
      public? true
    end

    calculate :completed_count, :integer, expr(0) do
      # In a real implementation, this would count completed items
      public? true
    end

    calculate :progress_percentage, :float, expr(0.0) do
      # In a real implementation, this would calculate percentage
      public? true
    end
  end

  actions do
    defaults [:read, :update, :destroy]

    create :create do
      primary? true
      accept [:title, :items, :allow_reordering]
    end
  end
end
