# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.ZodSchemaGenerator do
  @moduledoc """
  Generates Zod validation schemas for Ash resources and actions.

  This module is a thin formatter adapter over `AshTypescript.Codegen.SchemaCore`.
  It implements `AshTypescript.Codegen.SchemaFormatter` with Zod-specific output
  syntax (method chaining, `z.enum`, `.optional()`, etc.).
  """

  @behaviour AshTypescript.Codegen.SchemaFormatter

  alias AshTypescript.Codegen.SchemaCore

  # ─────────────────────────────────────────────────────────────────
  # Type Constants
  # ─────────────────────────────────────────────────────────────────

  @aggregate_types %{
    count: "z.number().int()",
    sum: "z.number()",
    exists: "z.boolean()",
    avg: "z.number()",
    min: "z.any()",
    max: "z.any()",
    first: "z.any()",
    last: "z.any()",
    list: "z.array(z.any())",
    custom: "z.any()",
    integer: "z.number().int()"
  }

  @simple_primitives %{
    Ash.Type.Boolean => "z.boolean()",
    Ash.Type.UUID => "z.uuid()",
    Ash.Type.UUIDv7 => "z.uuid()",
    Ash.Type.Date => "z.iso.date()",
    Ash.Type.Time => "z.string().time()",
    Ash.Type.TimeUsec => "z.string().time()",
    Ash.Type.UtcDatetime => "z.iso.datetime()",
    Ash.Type.UtcDatetimeUsec => "z.iso.datetime()",
    Ash.Type.DateTime => "z.iso.datetime()",
    Ash.Type.NaiveDatetime => "z.iso.datetime()",
    Ash.Type.Duration => "z.iso.duration()",
    Ash.Type.DurationName => "z.string()",
    Ash.Type.Decimal => "z.string()",
    Ash.Type.Binary => "z.string()",
    Ash.Type.UrlEncodedBinary => "z.string()",
    Ash.Type.File => "z.any()",
    Ash.Type.Function => "z.function()",
    Ash.Type.Term => "z.any()",
    Ash.Type.Vector => "z.array(z.number())",
    Ash.Type.Module => "z.string()"
  }

  @atom_primitives %{
    map: "z.record(z.string(), z.any())",
    sum: "z.number()",
    count: "z.number().int()"
  }

  @third_party_types %{
    AshDoubleEntry.ULID => "z.string()",
    AshMoney.Types.Money => "z.object({ amount: z.string(), currency: z.string() })"
  }

  # ─────────────────────────────────────────────────────────────────
  # SchemaFormatter callbacks
  # ─────────────────────────────────────────────────────────────────

  @impl true
  def null_schema, do: "z.null()"
  @impl true
  def any_schema, do: "z.any()"
  @impl true
  def custom_type_fallback, do: "z.string()"
  @impl true
  def aggregate_types, do: @aggregate_types
  @impl true
  def simple_primitives, do: @simple_primitives
  @impl true
  def atom_primitives, do: @atom_primitives
  @impl true
  def third_party_types, do: @third_party_types
  @impl true
  def wrap_array(inner), do: "z.array(#{inner})"
  @impl true
  def wrap_optional(schema), do: "#{schema}.optional()"
  @impl true
  def wrap_object(fields), do: "z.object({ #{fields} })"
  @impl true
  def wrap_union(schemas), do: "z.union([#{schemas}])"
  @impl true
  def wrap_record, do: "z.record(z.string(), z.any())"
  @impl true
  def format_enum(values), do: "z.enum([#{values}])"
  @impl true
  def ltree_array, do: "z.array(z.string())"
  @impl true
  def ltree_union, do: "z.union([z.string(), z.array(z.string())])"
  @impl true
  def schema_suffix, do: AshTypescript.Rpc.zod_schema_suffix()
  @impl true
  def generate_schemas_enabled?, do: AshTypescript.Rpc.generate_zod_schemas?()
  @impl true
  def section_header, do: "Zod Schemas for Input Resources"
  @impl true
  def library_prefix, do: "z"
  @impl true
  def import_statement(path), do: "import { z } from \"#{path}\";"
  @impl true
  def library_name, do: "Zod"
  @impl true
  def configured_import_path, do: AshTypescript.Rpc.zod_import_path()

  @impl true
  def format_string(constraints, require_non_empty) do
    if constraints == [] do
      if require_non_empty, do: "z.string().min(1)", else: "z.string()"
    else
      build_string_zod(constraints, require_non_empty)
    end
  end

  @impl true
  def format_integer(constraints) do
    if constraints == [] do
      "z.number().int()"
    else
      "z.number().int()"
      |> add_min(Keyword.get(constraints, :min))
      |> add_max(Keyword.get(constraints, :max))
    end
  end

  @impl true
  def format_float(constraints) do
    if constraints == [] do
      "z.number()"
    else
      "z.number()"
      |> add_min(Keyword.get(constraints, :min))
      |> add_max(Keyword.get(constraints, :max))
      |> add_gt(Keyword.get(constraints, :greater_than))
      |> add_lt(Keyword.get(constraints, :less_than))
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Public API (delegates to SchemaCore)
  # ─────────────────────────────────────────────────────────────────

  @doc "Maps Ash type structs (attribute/argument maps) to a Zod schema string."
  def get_zod_type(type_and_constraints, context \\ nil),
    do: SchemaCore.get_type(__MODULE__, type_and_constraints, context)

  @doc "Generates a Zod schema definition for an RPC action's input."
  def generate_zod_schema(resource, action, rpc_action_name),
    do: SchemaCore.generate_action_schema(__MODULE__, resource, action, rpc_action_name)

  @doc "Generates Zod schemas for embedded resources and struct arguments."
  def generate_zod_schemas_for_resources(resources),
    do: SchemaCore.generate_schemas_for_resources(__MODULE__, resources)

  @doc "Generates a Zod schema for a single resource."
  def generate_zod_schema_for_resource(resource),
    do: SchemaCore.generate_schema_for_resource(__MODULE__, resource)

  # ─────────────────────────────────────────────────────────────────
  # Private — string constraint builder (method-chain style)
  # ─────────────────────────────────────────────────────────────────

  defp build_string_zod(constraints, require_non_empty) do
    min_length = Keyword.get(constraints, :min_length)
    max_length = Keyword.get(constraints, :max_length)
    effective_min = if require_non_empty && is_nil(min_length), do: 1, else: min_length

    "z.string()"
    |> add_string_min(effective_min)
    |> add_string_max(max_length)
    |> add_string_regex(Keyword.get(constraints, :match))
  end

  defp add_min(s, nil), do: s
  defp add_min(s, n), do: "#{s}.min(#{n})"

  defp add_max(s, nil), do: s
  defp add_max(s, n), do: "#{s}.max(#{n})"

  defp add_gt(s, nil), do: s
  defp add_gt(s, n), do: "#{s}.gt(#{n})"

  defp add_lt(s, nil), do: s
  defp add_lt(s, n), do: "#{s}.lt(#{n})"

  defp add_string_min(s, nil), do: s
  defp add_string_min(s, n), do: "#{s}.min(#{n})"

  defp add_string_max(s, nil), do: s
  defp add_string_max(s, n), do: "#{s}.max(#{n})"

  defp add_string_regex(s, nil), do: s

  defp add_string_regex(s, regex) when is_struct(regex, Regex) do
    source = Regex.source(regex)

    if SchemaCore.regex_safe_for_js?(source) do
      flags = SchemaCore.build_js_flags(Regex.opts(regex))
      escaped = String.replace(source, "/", "\\/")
      "#{s}.regex(/#{escaped}/#{flags})"
    else
      s
    end
  end

  defp add_string_regex(s, {Spark.Regex, :cache, [pattern, opts]}) do
    add_string_regex(s, Spark.Regex.cache(pattern, opts))
  end

  defp add_string_regex(s, _other), do: s
end
