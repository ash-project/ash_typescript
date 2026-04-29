# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Todo do
  use Ash.Resource,
    data_layer: :embedded,
    domain: nil,
    extensions: [AshTypescript.Resource]

  typescript do
    type_name "Todo"
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true, allow_nil?: false
    attribute :description, :string, public?: true
    attribute :completed, :boolean, public?: true, default: false
    attribute :status, :atom, public?: true
    attribute :priority, :atom, public?: true
    attribute :due_date, :date, public?: true
    attribute :priority_score, :integer, public?: true
    attribute :color_palette, :string, public?: true
    attribute :percentage, :float, public?: true
    attribute :tags, {:array, :string}, public?: true, default: []
    attribute :custom_data, :map, public?: true
    attribute :hierarchy, :string, public?: true
    attribute :external_reference, :string, public?: true
    attribute :assigned_user_id, :uuid, public?: true
    attribute :estimated_hours, :float, public?: true
    attribute :actual_hours, :float, public?: true
    attribute :review_status, :atom, public?: true
    attribute :workflow_stage, :string, public?: true
    create_timestamp :created_at, public?: true
    update_timestamp :updated_at, public?: true
  end
end

defmodule Ticket do
  use Ash.Resource,
    data_layer: :embedded,
    domain: nil,
    extensions: [AshTypescript.Resource]

  typescript do
    type_name "Ticket"
    field_names archived?: "isArchived"
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true, allow_nil?: false
    attribute :archived?, :boolean, public?: true, default: false
  end
end

defmodule TodoStatistics do
  use Ash.TypedStruct

  def typescript_field_names do
    [all_completed?: "allCompleted"]
  end

  typed_struct do
    field(:view_count, :integer, default: 0)
    field(:all_completed?, :boolean)
  end
end

alias AshTypescript.FieldFormatter

# Realistic per-record loop — format every public Todo field name once. This
# mirrors what OutputFormatter does for each record in a list response.
todo_fields = [
  :id,
  :title,
  :description,
  :completed,
  :status,
  :priority,
  :due_date,
  :priority_score,
  :color_palette,
  :percentage,
  :tags,
  :custom_data,
  :hierarchy,
  :external_reference,
  :assigned_user_id,
  :estimated_hours,
  :actual_hours,
  :review_status,
  :workflow_stage,
  :created_at,
  :updated_at
]

# Field with a typescript field_names DSL mapping (`archived?` → `"isArchived"`).
mapped_field = :archived?

# Field with no mapping — exercises the format_field_name fallthrough.
unmapped_field = :title

# TypedStruct field with typescript_field_names callback (`all_completed?` → `"allCompleted"`).
typed_struct_field = :all_completed?

Benchee.run(
  %{
    # format_field_name/2 — pure name conversion, no resource context.
    "format_field_name/atom" =>
      fn -> FieldFormatter.format_field_name(:user_name, :camel_case) end,
    "format_field_name/atom_already_short" =>
      fn -> FieldFormatter.format_field_name(:title, :camel_case) end,
    "format_field_name/string" =>
      fn -> FieldFormatter.format_field_name("user_name", :camel_case) end,
    "format_field_name/snake_case_passthrough" =>
      fn -> FieldFormatter.format_field_name(:user_name, :snake_case) end,

    # format_field_for_client/3 — adds resource introspection on top.
    "format_field_for_client/nil_resource" =>
      fn -> FieldFormatter.format_field_for_client(:user_name, nil, :camel_case) end,
    "format_field_for_client/resource_unmapped" =>
      fn -> FieldFormatter.format_field_for_client(unmapped_field, Todo, :camel_case) end,
    "format_field_for_client/resource_mapped" =>
      fn -> FieldFormatter.format_field_for_client(mapped_field, Ticket, :camel_case) end,
    "format_field_for_client/typed_struct_mapped" =>
      fn ->
        FieldFormatter.format_field_for_client(typed_struct_field, TodoStatistics, :camel_case)
      end,

    # Full per-record loop over every Todo public field — closest to what
    # OutputFormatter runs in a list response.
    "per_record_loop/todo_all_fields" =>
      fn ->
        Enum.map(todo_fields, fn field ->
          FieldFormatter.format_field_for_client(field, Todo, :camel_case)
        end)
      end
  },
  memory_time: 2
)
