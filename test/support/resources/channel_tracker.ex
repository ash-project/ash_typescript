# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.ChannelTracker do
  @moduledoc """
  Test resource for TypedChannel codegen with ash automagic features.

  Exercises two new Ash core capabilities:
  1. `transform: :calc_name` — atom-based transforms that reference a calculation
  2. `:auto` type calculations — types inferred from expressions at compile time

  All publications use `transform: :calc_name` without explicit `returns:`.
  The typed channel codegen auto-derives the payload type from the calculation.

  Expression types covered:
  - String concat (explicit and :auto)
  - Map with local fields (:auto)
  - Map with relationship traversal via first() (:auto)
  - Map with nested relationship traversal via first() with dot access (:auto)
  - Map mixing aggregates, booleans, strings, and relationship fields (:auto)
  - Count aggregate (:auto)
  - Max aggregate (:auto)
  - Boolean expression (:auto)
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

    # Map calc with relationship traversal (:auto typed)
    publish :detail_snapshot, [:id],
      event: "tracker_detail",
      public?: true,
      transform: :detail

    # Count aggregate (:auto typed)
    publish :count_entries, [:id],
      event: "tracker_entry_count",
      public?: true,
      transform: :entry_count

    # Boolean expression (:auto typed)
    publish :check_active, [:id],
      event: "tracker_is_active",
      public?: true,
      transform: :is_active

    # Max aggregate (:auto typed)
    publish :top_score, [:id],
      event: "tracker_top_score",
      public?: true,
      transform: :top_entry_score

    # Map with nested relationship traversal (:auto typed)
    publish :deep_snapshot, [:id],
      event: "tracker_deep_detail",
      public?: true,
      transform: :deep_detail

    # Map mixing aggregates, booleans, and strings (:auto typed)
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

    # :auto map calc with relationship traversal (first aggregate)
    calculate :detail,
              :auto,
              expr(%{id: id, name: name, latest_entry_body: first(entries, :body)}) do
      public?(true)
    end

    # :auto count aggregate — should resolve to integer
    calculate :entry_count, :auto, expr(count(entries)) do
      public?(true)
    end

    # :auto boolean expression — type inferred as boolean
    calculate :is_active, :auto, expr(status == "active" and priority > 0) do
      public?(true)
    end

    # :auto max aggregate on related field — should resolve to integer
    calculate :top_entry_score, :auto, expr(max(entries, :score)) do
      public?(true)
    end

    # :auto map with nested relationship traversal — entries -> author -> username
    calculate :deep_detail,
              :auto,
              expr(%{
                id: id,
                name: name,
                latest_author: first(entries, :channel_tracker_author_id),
                latest_body: first(entries, :body),
                latest_score: first(entries, :score)
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
                entry_count: count(entries),
                top_score: max(entries, :score),
                latest_body: first(entries, :body)
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
