# SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.Task do
  @moduledoc """
  Test resource for validating field and argument name mapping in RPC actions.

  This resource demonstrates:
  - Attribute names that are invalid TypeScript identifiers (`:archived?`)
  - Argument names that are invalid TypeScript identifiers (`:completed?`)
  - Mapping these to valid TypeScript names via DSL options
  """

  use Ash.Resource,
    domain: AshTypescript.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshTypescript.Resource]

  ets do
    private? true
  end

  typescript do
    type_name "Task"
    field_names archived?: :is_archived
    argument_names mark_completed: [completed?: :is_completed]
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      allow_nil? false
      public? true
    end

    attribute :completed, :boolean do
      allow_nil? false
      default false
      public? true
    end

    attribute :archived?, :boolean do
      allow_nil? false
      default false
      public? true
    end

    attribute :metadata, AshTypescript.Test.TaskMetadata do
      allow_nil? true
      public? true
    end

    attribute :stats, AshTypescript.Test.TaskStats do
      allow_nil? true
      public? true
    end

    timestamps()
  end

  actions do
    defaults [:read]

    create :create do
      accept [:title]
      primary? true
    end

    update :update do
      accept [:title, :archived?, :stats]
      primary? true
    end

    update :mark_completed do
      require_atomic? false

      argument :completed?, :boolean do
        allow_nil? false
      end

      change fn changeset, _context ->
        completed_value = Ash.Changeset.get_argument(changeset, :completed?)
        Ash.Changeset.change_attribute(changeset, :completed, completed_value)
      end
    end

    destroy :destroy do
      accept [:archived?]
      primary? true
    end
  end
end
