# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

alias AshTypescript.FieldFormatter

# Realistic per-record loop — format a typical resource's public field names once.
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

Benchee.run(
  %{
    # format_field_name/2 — pure name conversion, no resource context.
    "format_field_name/atom" => fn ->
      FieldFormatter.format_field_name(:user_name, :camel_case)
    end,
    "format_field_name/atom_already_short" => fn ->
      FieldFormatter.format_field_name(:title, :camel_case)
    end,
    "format_field_name/string" => fn ->
      FieldFormatter.format_field_name("user_name", :camel_case)
    end,
    "format_field_name/snake_case_passthrough" => fn ->
      FieldFormatter.format_field_name(:user_name, :snake_case)
    end,

    # Every field of a typical resource, one after another.
    "per_record_loop/todo_all_fields" => fn ->
      Enum.map(todo_fields, &FieldFormatter.format_field_name(&1, :camel_case))
    end
  },
  memory_time: 2
)
