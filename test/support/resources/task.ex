# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
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
    field_names archived?: "isArchived"
    argument_names mark_completed: [is_task_completed_now?: "isCompleted"]
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

    attribute :custom_id, AshTypescript.Test.CustomIdentifier do
      allow_nil? true
      public? true
    end

    attribute :price, AshMoney.Types.Money do
      allow_nil? true
      public? true
    end

    timestamps()
  end

  actions do
    defaults [:read]

    read :read_with_metadata do
      metadata :some_string, :string, allow_nil?: false, default: "default_value"
      metadata :some_number, :integer, allow_nil?: false, default: 123
      metadata :some_boolean, :boolean

      prepare fn query, _context ->
        Ash.Query.after_action(query, fn _query, results ->
          # Set metadata on each result
          results_with_metadata =
            Enum.map(results, fn record ->
              record
              |> Ash.Resource.put_metadata(:some_string, "default_value")
              |> Ash.Resource.put_metadata(:some_number, 123)
              |> Ash.Resource.put_metadata(:title, 1)
            end)

          {:ok, results_with_metadata}
        end)
      end
    end

    read :read_with_typed_map_metadata do
      metadata :audit_entries, {:array, :map},
        constraints: [
          items: [
            fields: [
              field_name: [type: :string],
              old_value: [type: :string]
            ]
          ]
        ]

      metadata :completion_info, :map,
        constraints: [
          fields: [
            completed_at: [type: :string],
            completed_by: [type: :string]
          ]
        ]

      prepare fn query, _context ->
        Ash.Query.after_action(query, fn _query, results ->
          results_with_metadata =
            Enum.map(results, fn record ->
              record
              |> Ash.Resource.put_metadata(:audit_entries, [
                %{field_name: "title", old_value: "Old Title"},
                %{field_name: "completed", old_value: "false"}
              ])
              |> Ash.Resource.put_metadata(:completion_info, %{
                completed_at: "2025-01-15T10:30:00Z",
                completed_by: "user_123"
              })
            end)

          {:ok, results_with_metadata}
        end)
      end
    end

    read :read_with_unconstrained_map_metadata do
      metadata :raw_audit, :map
      metadata :raw_events, {:array, :map}

      prepare fn query, _context ->
        Ash.Query.after_action(query, fn _query, results ->
          results_with_metadata =
            Enum.map(results, fn record ->
              record
              |> Ash.Resource.put_metadata(:raw_audit, %{
                "_id" => "audit-1",
                "_type" => "audit.event",
                "_createdAt" => "2026-04-14T00:00:00Z",
                "nested" => %{"_rev" => "rev-1", "field_name" => "title"}
              })
              |> Ash.Resource.put_metadata(:raw_events, [
                %{"_id" => "evt-1", "event_type" => "created"},
                %{"_id" => "evt-2", "event_type" => "updated"}
              ])
            end)

          {:ok, results_with_metadata}
        end)
      end
    end

    read :read_with_invalid_metadata_names do
      metadata :meta_1, :string, allow_nil?: false, default: "metadata_value"
      metadata :is_valid?, :boolean, allow_nil?: false, default: true
      metadata :field_2, :integer, allow_nil?: false, default: 999

      prepare fn query, _context ->
        Ash.Query.after_action(query, fn _query, results ->
          # Set metadata on each result
          results_with_metadata =
            Enum.map(results, fn record ->
              record
              |> Ash.Resource.put_metadata(:meta_1, "metadata_value")
              |> Ash.Resource.put_metadata(:is_valid?, true)
              |> Ash.Resource.put_metadata(:field_2, 999)
            end)

          {:ok, results_with_metadata}
        end)
      end
    end

    create :create do
      accept [:title, :price]
      primary? true
      metadata :some_string, :string, allow_nil?: false
      metadata :some_number, :integer, allow_nil?: false
      metadata :some_boolean, :boolean

      change fn changeset, _context ->
        Ash.Changeset.after_action(changeset, fn _changeset, record ->
          {:ok,
           record
           |> Ash.Resource.put_metadata(:some_string, "created")
           |> Ash.Resource.put_metadata(:some_number, 456)
           |> Ash.Resource.put_metadata(:some_boolean, false)}
        end)
      end
    end

    create :create_with_unconstrained_map_metadata do
      accept [:title]
      metadata :raw_result, :map

      change fn changeset, _context ->
        Ash.Changeset.after_action(changeset, fn _changeset, record ->
          {:ok,
           Ash.Resource.put_metadata(record, :raw_result, %{
             "_id" => "doc-42",
             "_type" => "task",
             "_createdAt" => "2026-04-14T12:00:00Z"
           })}
        end)
      end
    end

    update :update do
      accept [:title, :archived?, :stats]
      primary? true
      require_atomic? false
      metadata :some_string, :string, allow_nil?: false
      metadata :some_number, :integer, allow_nil?: false
      metadata :some_boolean, :boolean

      change fn changeset, _context ->
        Ash.Changeset.after_action(changeset, fn _changeset, record ->
          {:ok,
           record
           |> Ash.Resource.put_metadata(:some_string, "updated")
           |> Ash.Resource.put_metadata(:some_number, 789)
           |> Ash.Resource.put_metadata(:some_boolean, true)}
        end)
      end
    end

    update :mark_completed do
      require_atomic? false
      metadata :some_string, :string, allow_nil?: false
      metadata :some_number, :integer, allow_nil?: false
      metadata :some_boolean, :boolean

      argument :is_task_completed_now?, :boolean do
        allow_nil? false
      end

      change fn changeset, _context ->
        completed_value = Ash.Changeset.get_argument(changeset, :is_task_completed_now?)

        Ash.Changeset.change_attribute(changeset, :completed, completed_value)
        |> Ash.Changeset.after_action(fn _changeset, record ->
          {:ok,
           record
           |> Ash.Resource.put_metadata(:some_string, "some_value")
           |> Ash.Resource.put_metadata(:some_number, 123)
           |> Ash.Resource.put_metadata(:some_boolean, true)}
        end)
      end
    end

    destroy :destroy do
      accept [:archived?]
      primary? true
      require_atomic? false
      metadata :some_string, :string, allow_nil?: false
      metadata :some_number, :integer, allow_nil?: false
      metadata :some_boolean, :boolean

      manual fn changeset, _context ->
        # Manual destroy to ensure we can return the record with metadata
        record = changeset.data

        # Perform the actual deletion using the data layer
        with :ok <- Ash.DataLayer.destroy(changeset.resource, changeset) do
          # Create a struct with metadata to return
          record_with_metadata =
            record
            |> Ash.Resource.put_metadata(:some_string, "destroyed")
            |> Ash.Resource.put_metadata(:some_number, 999)
            |> Ash.Resource.put_metadata(:some_boolean, nil)

          {:ok, record_with_metadata}
        end
      end
    end

    action :get_task_stats, AshTypescript.Test.TaskStats do
      argument :task_id, :uuid, allow_nil?: false

      run fn input, _context ->
        # Simulate returning task statistics
        stats = %AshTypescript.Test.TaskStats{
          total_count: 10,
          completed?: true,
          is_urgent?: false,
          average_duration: 45.5
        }

        {:ok, stats}
      end
    end

    action :list_task_stats, {:array, AshTypescript.Test.TaskStats} do
      run fn _input, _context ->
        # Simulate returning multiple task statistics
        stats_list = [
          %AshTypescript.Test.TaskStats{
            total_count: 10,
            completed?: true,
            is_urgent?: false,
            average_duration: 45.5
          },
          %AshTypescript.Test.TaskStats{
            total_count: 5,
            completed?: false,
            is_urgent?: true,
            average_duration: 30.0
          }
        ]

        {:ok, stats_list}
      end
    end

    action :get_suggestion, AshTypescript.Test.Suggestion do
      argument :query, :string, allow_nil?: false

      run fn _input, _context ->
        {:ok, %{name: "Test Suggestion", category: nil, score: 85}}
      end
    end

    action :list_suggestions, {:array, AshTypescript.Test.Suggestion} do
      argument :query, :string, default: ""

      run fn _input, _context ->
        {:ok,
         [
           %{name: "Suggestion A", category: "work", score: 90},
           %{name: "Suggestion B", category: nil, score: 75}
         ]}
      end
    end
  end
end
