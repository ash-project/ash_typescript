# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule TodoMetadata do
  use Ash.Resource,
    data_layer: :embedded,
    domain: nil,
    extensions: [AshTypescript.Resource]

  typescript do
    type_name "TodoMetadata"
  end

  attributes do
    uuid_primary_key :id
    attribute :category, :string, public?: true, allow_nil?: false
    attribute :priority_score, :integer, public?: true, default: 0
    attribute :is_urgent, :boolean, public?: true, default: false

    attribute :status, :atom,
      public?: true,
      default: :draft,
      constraints: [one_of: [:draft, :active, :archived]]
  end
end

defmodule TodoStatistics do
  use Ash.TypedStruct

  def typescript_field_names do
    [all_completed?: "allCompleted"]
  end

  typed_struct do
    field(:view_count, :integer, default: 0)
    field(:edit_count, :integer, default: 0)
    field(:completion_time_seconds, :integer)
    field(:difficulty_rating, :float)
    field(:all_completed?, :boolean)

    field(:performance_metrics, :map,
      constraints: [
        fields: [
          focus_time_seconds: [type: :integer, allow_nil?: false],
          interruption_count: [type: :integer, allow_nil?: false],
          efficiency_score: [type: :float, allow_nil?: false],
          task_complexity: [type: :string, allow_nil?: true]
        ]
      ]
    )
  end
end

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
    attribute :metadata, TodoMetadata, public?: true
    attribute :statistics, TodoStatistics, public?: true
  end
end

alias AshTypescript.Rpc.ValueFormatter

# Sample values pre-normalized as they arrive at format/5 — upstream
# ResultProcessor.normalize_primitive has already converted DateTime → ISO8601, etc.
sample_string = "Pick up groceries"
sample_uuid = "0190e5b1-c3a1-7000-8000-000000000001"
sample_iso_datetime = "2026-04-21T12:00:00Z"
sample_iso_date = "2026-04-21"
sample_decimal_str = "42.5"
sample_atom_str = "pending"

sample_typed_map = %{
  view_count: 5,
  edit_count: 2,
  completion_time_seconds: 300,
  difficulty_rating: 0.7,
  all_completed?: true,
  performance_metrics: %{
    focus_time_seconds: 200,
    interruption_count: 1,
    efficiency_score: 0.85,
    task_complexity: "medium"
  }
}

sample_embedded = %{
  category: "work",
  priority_score: 50,
  is_urgent: false,
  status: "active"
}

embedded_constraints = [instance_of: TodoMetadata]

typed_struct_constraints = [
  instance_of: TodoStatistics,
  fields: [
    view_count: [type: :integer],
    edit_count: [type: :integer],
    completion_time_seconds: [type: :integer],
    difficulty_rating: [type: :float],
    all_completed?: [type: :boolean],
    performance_metrics: [type: :map]
  ]
]

Benchee.run(
  %{
    # Built-in scalars — the guard-clause targets.
    "scalar/string" =>
      fn -> ValueFormatter.format(sample_string, Ash.Type.String, [], :camel_case, :output) end,
    "scalar/uuid" =>
      fn -> ValueFormatter.format(sample_uuid, Ash.Type.UUID, [], :camel_case, :output) end,
    "scalar/boolean" =>
      fn -> ValueFormatter.format(true, Ash.Type.Boolean, [], :camel_case, :output) end,
    "scalar/integer" =>
      fn -> ValueFormatter.format(42, Ash.Type.Integer, [], :camel_case, :output) end,
    "scalar/float" =>
      fn -> ValueFormatter.format(3.14, Ash.Type.Float, [], :camel_case, :output) end,
    "scalar/decimal" =>
      fn ->
        ValueFormatter.format(sample_decimal_str, Ash.Type.Decimal, [], :camel_case, :output)
      end,
    "scalar/date" =>
      fn -> ValueFormatter.format(sample_iso_date, Ash.Type.Date, [], :camel_case, :output) end,
    "scalar/utc_datetime" =>
      fn ->
        ValueFormatter.format(
          sample_iso_datetime,
          Ash.Type.UtcDatetime,
          [],
          :camel_case,
          :output
        )
      end,
    "scalar/atom" =>
      fn -> ValueFormatter.format(sample_atom_str, Ash.Type.Atom, [], :camel_case, :output) end,

    # Composite types — no change expected after the guard clause (regression checks).
    "composite/embedded_resource" =>
      fn ->
        ValueFormatter.format(
          sample_embedded,
          Ash.Type.Struct,
          embedded_constraints,
          :camel_case,
          :output
        )
      end,
    "composite/typed_struct" =>
      fn ->
        ValueFormatter.format(
          sample_typed_map,
          Ash.Type.Struct,
          typed_struct_constraints,
          :camel_case,
          :output
        )
      end,
    "composite/resource_map" =>
      fn ->
        ValueFormatter.format(
          %{title: "x", description: "y", completed: false},
          Todo,
          [],
          :camel_case,
          :output
        )
      end,

    # Existing nil fast paths.
    "fastpath/nil_value" =>
      fn -> ValueFormatter.format(nil, Ash.Type.String, [], :camel_case, :output) end,
    "fastpath/nil_type" =>
      fn -> ValueFormatter.format("hi", nil, [], :camel_case, :output) end
  },
  memory_time: 2
)
