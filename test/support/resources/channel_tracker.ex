# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.ChannelTracker do
  @moduledoc """
  Test resource for TypedChannel codegen with calculation transforms.

  All publications use `transform: :calc_name`. Ash auto-populates the
  `returns` type from the calculation, which AshTypescript reads directly.

  Expression types covered (all :auto unless noted):
  - String concat (explicit and :auto)
  - Map with local attribute fields
  - Map with mixed field types (string, integer, boolean)
  - Integer from attribute reference
  - Boolean expression

  Note: Avoids aggregate expressions (first, count, max) because
  Ash.DataLayer.Simple doesn't support aggregate type resolution for :auto.
  """
  use Ash.Resource,
    domain: nil,
    notifiers: [Ash.Notifier.PubSub]

  pub_sub do
    module AshTypescript.Test.TestEndpoint
    prefix "tracker"

    # String calc (explicitly typed)
    publish :create, [:id],
      event: "tracker_summary",
      public?: true,
      transform: :summary

    # String calc (:auto typed)
    publish :update, [:id],
      event: "tracker_label",
      public?: true,
      transform: :label

    # String calc (explicitly typed)
    publish :destroy, [:id],
      event: "tracker_status_changed",
      public?: true,
      transform: :status_display

    # Map calc with local fields (:auto typed)
    publish :snapshot, [:id],
      event: "tracker_snapshot",
      public?: true,
      transform: :snapshot

    # Map calc with different field types (:auto typed)
    publish :detail_snapshot, [:id],
      event: "tracker_detail",
      public?: true,
      transform: :detail

    # Integer from attribute (:auto typed)
    publish :count_entries, [:id],
      event: "tracker_entry_count",
      public?: true,
      transform: :entry_count

    # Boolean expression (:auto typed)
    publish :check_active, [:id],
      event: "tracker_is_active",
      public?: true,
      transform: :is_active

    # Integer from attribute (:auto typed)
    publish :top_score, [:id],
      event: "tracker_top_score",
      public?: true,
      transform: :top_entry_score

    # Map with various field types (:auto typed)
    publish :deep_snapshot, [:id],
      event: "tracker_deep_detail",
      public?: true,
      transform: :deep_detail

    # Map mixing expressions and attributes (:auto typed)
    publish :full_report, [:id],
      event: "tracker_report",
      public?: true,
      transform: :report
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
    attribute :status, :string, public?: true, default: "active"
    attribute :priority, :integer, public?: true, default: 0
  end

  relationships do
    has_many :entries, AshTypescript.Test.ChannelTrackerEntry do
      public? true
    end
  end

  calculations do
    # Explicitly typed string calculation used as transform
    calculate :summary, :string, expr(name <> " [" <> status <> "]") do
      public?(true)
    end

    # :auto typed string concat — type inferred from expression
    calculate :label, :auto, expr(name <> " tracker") do
      public?(true)
    end

    # Explicitly typed string — used without returns on publication
    calculate :status_display, :string, expr("Status: " <> status) do
      public?(true)
    end

    # :auto typed map calc with local attribute fields
    calculate :snapshot, :auto, expr(%{id: id, name: name, status: status}) do
      public?(true)
    end

    # :auto map calc with different field types (no aggregates)
    calculate :detail,
              :auto,
              expr(%{id: id, name: name, description: status}) do
      public?(true)
    end

    # :auto integer — type inferred from integer attribute
    calculate :entry_count, :auto, expr(priority) do
      public?(true)
    end

    # :auto boolean expression — type inferred as boolean
    calculate :is_active, :auto, expr(status == "active" and priority > 0) do
      public?(true)
    end

    # :auto integer — type inferred from integer attribute
    calculate :top_entry_score, :auto, expr(priority) do
      public?(true)
    end

    # :auto map with various field types
    calculate :deep_detail,
              :auto,
              expr(%{
                id: id,
                name: name,
                status: status,
                current_priority: priority
              }) do
      public?(true)
    end

    # :auto map mixing different expression types in a single map
    calculate :report,
              :auto,
              expr(%{
                name: name,
                status: status,
                is_active: status == "active" and priority > 0,
                current_priority: priority,
                label: name <> " tracker"
              }) do
      public?(true)
    end
  end

  actions do
    defaults [:read, :create, :update, :destroy]

    update :snapshot do
      accept []
    end

    update :detail_snapshot do
      accept []
    end

    update :count_entries do
      accept []
    end

    update :check_active do
      accept []
    end

    update :top_score do
      accept []
    end

    update :deep_snapshot do
      accept []
    end

    update :full_report do
      accept []
    end
  end
end
