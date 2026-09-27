# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.EffectSchemaGenerator do
  @moduledoc """
  Generates Effect Schema (Effect v4) validation schemas for Ash resources and actions.

  This module is a thin formatter adapter over `AshTypescript.Codegen.SchemaCore`.
  It implements `AshTypescript.Codegen.SchemaFormatter` with Effect-specific output
  syntax (`Schema.Struct`, `Schema.Literals`, `.check(...)` refinements,
  `Schema.optional(schema)`, etc.).

  Effect v4 ships Schema inside the `effect` package, so the generated file
  imports `{ Schema }` from the configured `effect_import_path`.
  """

  @behaviour AshTypescript.Codegen.SchemaFormatter

  alias AshTypescript.Codegen.SchemaCore

  # ─────────────────────────────────────────────────────────────────
  # Type Constants
  # ─────────────────────────────────────────────────────────────────

  # Effect has no built-in ISO string checks, so date/time strings validate
  # against a pattern. The patterns check shape only (not calendar validity)
  # and cover the canonical ISO 8601 form the server emits, with optional
  # fractional seconds and offsets. Ash also casts looser forms (a space
  # separator, `,` fractions, `+0100` offsets) that these patterns reject.
  @iso_date ~S"Schema.String.check(Schema.isPattern(/^\d{4}-\d{2}-\d{2}$/))"
  @iso_time ~S"Schema.String.check(Schema.isPattern(/^\d{2}:\d{2}:\d{2}(\.\d+)?$/))"
  @iso_datetime ~S"Schema.String.check(Schema.isPattern(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})?$/))"

  @aggregate_types %{
    count: "Schema.Int",
    sum: "Schema.Finite",
    exists: "Schema.Boolean",
    avg: "Schema.Finite",
    min: "Schema.Any",
    max: "Schema.Any",
    first: "Schema.Any",
    last: "Schema.Any",
    list: "Schema.Array(Schema.Any)",
    custom: "Schema.Any",
    integer: "Schema.Int"
  }

  @simple_primitives %{
    Ash.Type.Boolean => "Schema.Boolean",
    Ash.Type.UUID => "Schema.String.check(Schema.isUUID())",
    Ash.Type.UUIDv7 => "Schema.String.check(Schema.isUUID())",
    Ash.Type.Date => @iso_date,
    Ash.Type.Time => @iso_time,
    Ash.Type.TimeUsec => @iso_time,
    Ash.Type.UtcDatetime => @iso_datetime,
    Ash.Type.UtcDatetimeUsec => @iso_datetime,
    Ash.Type.DateTime => @iso_datetime,
    Ash.Type.NaiveDatetime => @iso_datetime,
    Ash.Type.Duration => "Schema.String",
    Ash.Type.DurationName => "Schema.String",
    Ash.Type.Decimal => "Schema.String",
    Ash.Type.Binary => "Schema.String",
    Ash.Type.UrlEncodedBinary => "Schema.String",
    Ash.Type.File => "Schema.Any",
    # A function can never cross a JSON boundary, so there is nothing to
    # validate; this matches the generated TS type (`export type Function = any`).
    Ash.Type.Function => "Schema.Any",
    Ash.Type.Term => "Schema.Any",
    Ash.Type.Vector => "Schema.Array(Schema.Finite)",
    Ash.Type.Module => "Schema.String"
  }

  @atom_primitives %{
    map: "Schema.Record(Schema.String, Schema.Any)",
    sum: "Schema.Finite",
    count: "Schema.Int"
  }

  @third_party_types %{
    AshDoubleEntry.ULID => "Schema.String",
    AshMoney.Types.Money => "Schema.Struct({ amount: Schema.String, currency: Schema.String })"
  }

  # ─────────────────────────────────────────────────────────────────
  # SchemaFormatter callbacks
  # ─────────────────────────────────────────────────────────────────

  @impl true
  def null_schema, do: "Schema.Null"
  @impl true
  def any_schema, do: "Schema.Any"
  @impl true
  def mapping_overrides, do: AshTypescript.Rpc.effect_mapping_overrides()
  @impl true
  def custom_imports, do: AshTypescript.Rpc.effect_import_into_generated()
  @impl true
  def aggregate_types, do: @aggregate_types
  @impl true
  def simple_primitives, do: @simple_primitives
  @impl true
  def atom_primitives, do: @atom_primitives
  @impl true
  def third_party_types, do: @third_party_types

  @impl true
  def format_array(inner, constraints) do
    checks =
      []
      |> add_check_if(
        "Schema.isMinLength(#{Keyword.get(constraints, :min_length)})",
        not is_nil(Keyword.get(constraints, :min_length))
      )
      |> add_check_if(
        "Schema.isMaxLength(#{Keyword.get(constraints, :max_length)})",
        not is_nil(Keyword.get(constraints, :max_length))
      )

    build_checks("Schema.Array(#{inner})", checks)
  end

  # `Schema.optional` accepts an absent key *and* an explicit `undefined`,
  # matching zod's `.optional()` and valibot's `v.optional(...)`.
  @impl true
  def wrap_optional(schema), do: "Schema.optional(#{schema})"
  @impl true
  def wrap_nullable(schema), do: "Schema.NullOr(#{schema})"
  @impl true
  def wrap_object(fields), do: "Schema.Struct({ #{fields} })"
  @impl true
  def wrap_union(schemas), do: "Schema.Union([#{schemas}])"
  @impl true
  def wrap_record, do: "Schema.Record(Schema.String, Schema.Any)"
  @impl true
  def format_enum(values), do: "Schema.Literals([#{values}])"
  @impl true
  def ltree_array, do: "Schema.Array(Schema.String)"
  @impl true
  def ltree_union, do: "Schema.Union([Schema.String, Schema.Array(Schema.String)])"
  @impl true
  def schema_suffix, do: AshTypescript.Rpc.effect_schema_suffix()
  @impl true
  def generate_schemas_enabled?, do: AshTypescript.Rpc.generate_effect_schemas?()
  @impl true
  def section_header, do: "Effect Schemas for Input Resources"
  @impl true
  def object_constructor, do: "Schema.Struct"
  @impl true
  def import_statement(path), do: "import { Schema } from \"#{path}\";"
  @impl true
  def library_name, do: "Effect"
  @impl true
  def configured_import_path, do: AshTypescript.Rpc.effect_import_path()

  @impl true
  def format_string(constraints, require_non_empty) do
    max_length = Keyword.get(constraints, :max_length)
    effective_min = SchemaCore.effective_min_length(constraints, require_non_empty)

    checks =
      []
      |> add_check_if("Schema.isMinLength(#{effective_min})", not is_nil(effective_min))
      |> add_check_if("Schema.isMaxLength(#{max_length})", not is_nil(max_length))
      |> add_regex_check(Keyword.get(constraints, :match))

    build_checks("Schema.String", checks)
  end

  @impl true
  def format_integer(constraints) do
    build_checks("Schema.Int", number_constraint_checks(constraints))
  end

  # `Schema.Finite` rejects `NaN` and `±Infinity`, which `Schema.Number`
  # accepts — neither can come from a JSON payload.
  @impl true
  def format_float(constraints) do
    build_checks("Schema.Finite", number_constraint_checks(constraints))
  end

  # ─────────────────────────────────────────────────────────────────
  # Public API (delegates to SchemaCore)
  # ─────────────────────────────────────────────────────────────────

  @doc "Generates an Effect schema definition for an RPC action's input."
  def generate_effect_schema(resource, action, rpc_action_name),
    do: SchemaCore.generate_action_schema(__MODULE__, resource, action, rpc_action_name)

  @doc "Generates an Effect schema for a single resource."
  def generate_effect_schema_for_resource(resource),
    do: SchemaCore.generate_schema_for_resource(__MODULE__, resource)

  # ─────────────────────────────────────────────────────────────────
  # Private — `.check(...)` builder
  # ─────────────────────────────────────────────────────────────────

  defp number_constraint_checks(constraints) do
    []
    |> add_check_if(
      "Schema.isGreaterThanOrEqualTo(#{fmt_num(Keyword.get(constraints, :min))})",
      not is_nil(Keyword.get(constraints, :min))
    )
    |> add_check_if(
      "Schema.isLessThanOrEqualTo(#{fmt_num(Keyword.get(constraints, :max))})",
      not is_nil(Keyword.get(constraints, :max))
    )
    |> add_check_if(
      "Schema.isGreaterThan(#{fmt_num(Keyword.get(constraints, :greater_than))})",
      not is_nil(Keyword.get(constraints, :greater_than))
    )
    |> add_check_if(
      "Schema.isLessThan(#{fmt_num(Keyword.get(constraints, :less_than))})",
      not is_nil(Keyword.get(constraints, :less_than))
    )
  end

  defp fmt_num(value) when is_float(value),
    do: :erlang.float_to_binary(value, [:compact, {:decimals, 10}])

  defp fmt_num(value), do: "#{value}"

  defp add_check_if(checks, _entry, false), do: checks
  defp add_check_if(checks, entry, true), do: [entry | checks]

  defp build_checks(base, []), do: base

  defp build_checks(base, checks) do
    "#{base}.check(#{checks |> Enum.reverse() |> Enum.join(", ")})"
  end

  defp add_regex_check(checks, nil), do: checks

  defp add_regex_check(checks, regex) when is_struct(regex, Regex) do
    source = Regex.source(regex)

    if SchemaCore.regex_safe_for_js?(source) do
      flags = SchemaCore.build_js_flags(Regex.opts(regex))
      escaped = String.replace(source, "/", "\\/")
      ["Schema.isPattern(/#{escaped}/#{flags})" | checks]
    else
      checks
    end
  end

  defp add_regex_check(checks, {Spark.Regex, :cache, [pattern, opts]}) do
    add_regex_check(checks, Spark.Regex.cache(pattern, opts))
  end

  defp add_regex_check(checks, _other), do: checks
end
