# SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.TodoMetadata do
  @moduledoc """
  Test embedded resource for todo metadata with calculations and relationships.
  """
  use Ash.Resource,
    data_layer: :embedded,
    domain: nil,
    extensions: [AshTypescript.Resource]

  typescript do
    type_name "TodoMetadata"
  end

  attributes do
    # Primary key for identity testing
    uuid_primary_key :id

    # String types with constraints
    attribute :category, :string, public?: true, allow_nil?: false
    # Optional
    attribute :subcategory, :string, public?: true

    attribute :external_reference, :string,
      public?: true,
      constraints: [match: ~r/^[A-Z]{2}-\d{4}$/]

    # Numeric types
    attribute :priority_score, :integer,
      public?: true,
      default: 0,
      constraints: [min: 0, max: 100]

    attribute :estimated_hours, :float, public?: true
    attribute :budget, :decimal, public?: true

    # Boolean and atom types
    attribute :is_urgent, :boolean, public?: true, default: false

    attribute :status, :atom,
      public?: true,
      constraints: [one_of: [:draft, :active, :archived]],
      default: :draft

    # Date/time types
    attribute :deadline, :date, public?: true
    attribute :created_at, :utc_datetime, public?: true, default: &DateTime.utc_now/0
    attribute :reminder_time, :naive_datetime, public?: true

    # Collection types
    attribute :tags, {:array, :string}, public?: true, default: []
    attribute :labels, {:array, :atom}, public?: true, default: []
    attribute :custom_fields, :map, public?: true, default: %{}

    attribute :settings, :map,
      public?: true,
      constraints: [
        fields: [
          notifications: [type: :boolean],
          auto_archive: [type: :boolean],
          reminder_frequency: [type: :integer]
        ]
      ]

    # UUID types
    attribute :creator_id, :uuid, public?: true
    attribute :project_id, :uuid, public?: true

    # Private attribute for testing visibility
    attribute :internal_notes, :string, public?: false
  end

  calculations do
    # Simple calculation (no arguments)
    calculate :display_category, :string, expr(category || "Uncategorized") do
      public? true
    end

    # Calculation with arguments
    calculate :adjusted_priority,
              :integer,
              AshTypescript.Test.TodoMetadata.AdjustedPriorityCalculation do
      public? true
      argument :urgency_multiplier, :float, default: 1.0, allow_nil?: false
      argument :deadline_factor, :boolean, default: true
      argument :user_bias, :integer, default: 0, constraints: [min: -10, max: 10]
    end

    # Boolean calculation
    calculate :is_overdue,
              :boolean,
              expr(if(is_nil(deadline), false, deadline < ^Date.utc_today())) do
      public? true
    end

    # Calculation with format arguments
    calculate :formatted_summary,
              :string,
              AshTypescript.Test.TodoMetadata.FormattedSummaryCalculation do
      public? true
      argument :format, :atom, constraints: [one_of: [:short, :detailed, :json]], default: :short
      argument :include_metadata, :boolean, default: false
    end

    # Private calculation
    calculate :internal_score, :integer, expr(priority_score * 2) do
      public? false
    end
  end

  validations do
    validate present(:category), message: "Category is required"
    validate compare(:priority_score, greater_than_or_equal_to: 0)
  end

  identities do
    identity :unique_external_reference, [:external_reference]
  end

  actions do
    defaults [:read, :update, :destroy]

    create :create do
      primary? true

      accept [
        :category,
        :subcategory,
        :external_reference,
        :priority_score,
        :estimated_hours,
        :budget,
        :is_urgent,
        :status,
        :deadline,
        :created_at,
        :reminder_time,
        :tags,
        :labels,
        :custom_fields,
        :settings,
        :creator_id,
        :project_id
      ]
    end

    create :create_with_defaults do
      accept [:category, :priority_score]
    end

    update :archive do
      accept []
      change set_attribute(:status, :archived)
    end
  end
end
