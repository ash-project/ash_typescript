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
    attribute :tags, {:array, :string}, public?: true, default: []
    attribute :custom_data, :map, public?: true
    create_timestamp :created_at, public?: true
    update_timestamp :updated_at, public?: true
  end
end

alias AshTypescript.Rpc.OutputFormatter

# Plain maps matching the post-extraction shape OutputFormatter receives from
# ResultProcessor — scalars already normalized to JSON-encodable primitives.
build_todo = fn idx ->
  %{
    id: "0190e5b1-c3a1-7000-8000-#{String.pad_leading(Integer.to_string(idx), 12, "0")}",
    title: "Item #{idx}",
    description: "Description for item #{idx}",
    completed: rem(idx, 2) == 0,
    status: "pending",
    priority: "medium",
    due_date: "2026-04-21",
    tags: ["tag-a", "tag-b"],
    custom_data: %{notes: "freeform", count: idx},
    created_at: "2026-04-21T12:00:00Z",
    updated_at: "2026-04-21T12:00:00Z"
  }
end

todos_25 = Enum.map(1..25, build_todo)
todos_250 = Enum.map(1..250, build_todo)
todos_1500 = Enum.map(1..1500, build_todo)

Benchee.run(
  %{
    "format_list/25_records" =>
      fn -> OutputFormatter.format(todos_25, Todo, :read, :camel_case) end,
    "format_list/250_records" =>
      fn -> OutputFormatter.format(todos_250, Todo, :read, :camel_case) end,
    "format_list/1500_records" =>
      fn -> OutputFormatter.format(todos_1500, Todo, :read, :camel_case) end
  },
  memory_time: 2
)
