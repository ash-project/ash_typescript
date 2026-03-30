# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.ValibotSchemaGenerator do
  @moduledoc """
  Generates Valibot validation schemas for Ash resources and actions.

  This module is a thin formatter adapter over `AshTypescript.Codegen.SchemaCore`.
  It implements `AshTypescript.Codegen.SchemaFormatter` with Valibot-specific output
  syntax (`v.pipe()` composition, `v.picklist`, `v.optional(schema)`, etc.).
  """

  @behaviour AshTypescript.Codegen.SchemaFormatter

  alias AshTypescript.Codegen.SchemaCore

  # ─────────────────────────────────────────────────────────────────
  # Type Constants
  # ─────────────────────────────────────────────────────────────────

  @aggregate_types %{
    count: "v.pipe(v.number(), v.integer())",
    sum: "v.number()",
    exists: "v.boolean()",
    avg: "v.number()",
    min: "v.any()",
    max: "v.any()",
    first: "v.any()",
    last: "v.any()",
    list: "v.array(v.any())",
    custom: "v.any()",
    integer: "v.pipe(v.number(), v.integer())"
  }

  @simple_primitives %{
    Ash.Type.Boolean => "v.boolean()",
    Ash.Type.UUID => "v.pipe(v.string(), v.uuid())",
    Ash.Type.UUIDv7 => "v.pipe(v.string(), v.uuid())",
    Ash.Type.Date => "v.pipe(v.string(), v.isoDate())",
    Ash.Type.Time => "v.pipe(v.string(), v.isoTimeSecond())",
    Ash.Type.TimeUsec => "v.string()",
    Ash.Type.UtcDatetime => "v.pipe(v.string(), v.isoTimestamp())",
    Ash.Type.UtcDatetimeUsec => "v.pipe(v.string(), v.isoTimestamp())",
    Ash.Type.DateTime => "v.pipe(v.string(), v.isoDateTime())",
    Ash.Type.NaiveDatetime => "v.pipe(v.string(), v.isoDateTime())",
    Ash.Type.Duration => "v.string()",
    Ash.Type.DurationName => "v.string()",
    Ash.Type.Decimal => "v.string()",
    Ash.Type.Binary => "v.string()",
    Ash.Type.UrlEncodedBinary => "v.string()",
    Ash.Type.File => "v.any()",
    Ash.Type.Function => "v.function()",
    Ash.Type.Term => "v.any()",
    Ash.Type.Vector => "v.array(v.number())",
    Ash.Type.Module => "v.string()"
  }

  @atom_primitives %{
    map: "v.record(v.string(), v.any())",
    sum: "v.number()",
    count: "v.pipe(v.number(), v.integer())"
  }

  @third_party_types %{
    AshDoubleEntry.ULID => "v.string()",
    AshMoney.Types.Money => "v.object({})"
  }

  # ─────────────────────────────────────────────────────────────────
  # SchemaFormatter callbacks
  # ─────────────────────────────────────────────────────────────────

  @impl true
  def null_schema, do: "v.null()"
  @impl true
  def any_schema, do: "v.any()"
  @impl true
  def custom_type_fallback, do: "v.string()"
  @impl true
  def aggregate_types, do: @aggregate_types
  @impl true
  def simple_primitives, do: @simple_primitives
  @impl true
  def atom_primitives, do: @atom_primitives
  @impl true
  def third_party_types, do: @third_party_types
  @impl true
  def wrap_array(inner), do: "v.array(#{inner})"
  @impl true
  def wrap_optional(schema), do: "v.optional(#{schema})"
  @impl true
  def wrap_object(fields), do: "v.object({ #{fields} })"
  @impl true
  def wrap_union(schemas), do: "v.union([#{schemas}])"
  @impl true
  def wrap_record, do: "v.record(v.string(), v.any())"
  @impl true
  def format_enum(values), do: "v.picklist([#{values}])"
  @impl true
  def ltree_array, do: "v.array(v.string())"
  @impl true
  def ltree_union, do: "v.union([v.string(), v.array(v.string())])"
  @impl true
  def schema_suffix, do: AshTypescript.Rpc.valibot_schema_suffix()
  @impl true
  def generate_schemas_enabled?, do: AshTypescript.Rpc.generate_valibot_schemas?()
  @impl true
  def section_header, do: "Valibot Schemas for Input Resources"
  @impl true
  def library_prefix, do: "v"
  @impl true
  def import_statement(path), do: "import * as v from \"#{path}\";"
  @impl true
  def library_name, do: "Valibot"
  @impl true
  def configured_import_path, do: AshTypescript.Rpc.valibot_import_path()

  @impl true
  def pagination_schemas do
    """
    export const paginationKeysetInputSchema = v.object({
      after: v.optional(v.string()),
      before: v.optional(v.string()),
      limit: v.optional(v.pipe(v.number(), v.integer())),
      filter: v.optional(v.record(v.string(), v.any())),
    });

    export const paginationOffsetInputSchema = v.object({
      limit: v.optional(v.pipe(v.number(), v.integer())),
      offset: v.optional(v.pipe(v.number(), v.integer())),
      filter: v.optional(v.record(v.string(), v.any())),
      count: v.optional(v.boolean()),
    });

    export const paginationInputSchema = v.union([
      paginationKeysetInputSchema,
      paginationOffsetInputSchema,
    ]);
    """
  end

  @impl true
  def generic_filter_schemas do
    fmt = fn field -> AshTypescript.FieldFormatter.format_field_name(field, AshTypescript.Rpc.output_field_formatter()) end

    """
    export const stringFilterFieldSchema = v.union([
      v.string(),
      v.object({
        #{fmt.("eq")}: v.optional(v.string()),
        #{fmt.("not_eq")}: v.optional(v.string()),
        #{fmt.("contains")}: v.optional(v.string()),
        #{fmt.("icontains")}: v.optional(v.string()),
        #{fmt.("is_nil")}: v.optional(v.boolean()),
        #{fmt.("in")}: v.optional(v.array(v.string())),
      }),
    ]);

    export const numberFilterFieldSchema = v.union([
      v.number(),
      v.object({
        #{fmt.("eq")}: v.optional(v.number()),
        #{fmt.("not_eq")}: v.optional(v.number()),
        #{fmt.("gt")}: v.optional(v.number()),
        #{fmt.("gte")}: v.optional(v.number()),
        #{fmt.("lt")}: v.optional(v.number()),
        #{fmt.("lte")}: v.optional(v.number()),
        #{fmt.("is_nil")}: v.optional(v.boolean()),
        #{fmt.("in")}: v.optional(v.array(v.number())),
        // aliases
        #{fmt.("greater_than")}: v.optional(v.number()),
        #{fmt.("greater_than_or_equal")}: v.optional(v.number()),
        #{fmt.("less_than")}: v.optional(v.number()),
        #{fmt.("less_than_or_equal")}: v.optional(v.number()),
      }),
    ]);

    export const booleanFilterFieldSchema = v.union([
      v.boolean(),
      v.object({
        #{fmt.("eq")}: v.optional(v.boolean()),
        #{fmt.("is_nil")}: v.optional(v.boolean()),
      }),
    ]);

    export const dateFilterFieldSchema = v.union([
      v.string(),
      v.object({
        #{fmt.("eq")}: v.optional(v.string()),
        #{fmt.("not_eq")}: v.optional(v.string()),
        #{fmt.("gt")}: v.optional(v.string()),
        #{fmt.("gte")}: v.optional(v.string()),
        #{fmt.("lt")}: v.optional(v.string()),
        #{fmt.("lte")}: v.optional(v.string()),
        #{fmt.("is_nil")}: v.optional(v.boolean()),
        // aliases
        #{fmt.("greater_than")}: v.optional(v.string()),
        #{fmt.("greater_than_or_equal")}: v.optional(v.string()),
        #{fmt.("less_than")}: v.optional(v.string()),
        #{fmt.("less_than_or_equal")}: v.optional(v.string()),
      }),
    ]);

    export const atomFilterFieldSchema = v.union([
      v.string(),
      v.object({
        #{fmt.("eq")}: v.optional(v.string()),
        #{fmt.("not_eq")}: v.optional(v.string()),
        #{fmt.("is_nil")}: v.optional(v.boolean()),
        #{fmt.("in")}: v.optional(v.array(v.string())),
      }),
    ]);
    """
  end

  @impl true
  def format_string(constraints, require_non_empty) do
    if constraints == [] do
      if require_non_empty,
        do: "v.pipe(v.string(), v.minLength(1))",
        else: "v.string()"
    else
      build_string_valibot(constraints, require_non_empty)
    end
  end

  @impl true
  def format_integer(constraints) do
    pipes = number_constraint_pipes(constraints) ++ ["v.integer()"]
    build_pipe("v.number()", pipes)
  end

  @impl true
  def format_float(constraints) do
    pipes = number_constraint_pipes(constraints)
    build_pipe("v.number()", pipes)
  end

  # ─────────────────────────────────────────────────────────────────
  # Public API (delegates to SchemaCore)
  # ─────────────────────────────────────────────────────────────────

  @doc "Generates a Valibot schema definition for an RPC action's input."
  def generate_valibot_schema(resource, action, rpc_action_name),
    do: SchemaCore.generate_action_schema(__MODULE__, resource, action, rpc_action_name)

  @doc "Generates a Valibot schema for a single resource."
  def generate_valibot_schema_for_resource(resource),
    do: SchemaCore.generate_schema_for_resource(__MODULE__, resource)

  # ─────────────────────────────────────────────────────────────────
  # Private — string constraint builder (v.pipe style)
  # ─────────────────────────────────────────────────────────────────

  defp build_string_valibot(constraints, require_non_empty) do
    min_length = Keyword.get(constraints, :min_length)
    max_length = Keyword.get(constraints, :max_length)
    effective_min = if require_non_empty && is_nil(min_length), do: 1, else: min_length

    pipes =
      []
      |> add_pipe_if("v.minLength(#{effective_min})", not is_nil(effective_min))
      |> add_pipe_if("v.maxLength(#{max_length})", not is_nil(max_length))
      |> add_regex_pipe(Keyword.get(constraints, :match))

    build_pipe("v.string()", pipes)
  end

  defp number_constraint_pipes(constraints) do
    []
    |> add_pipe_if(
      "v.minValue(#{fmt_num(Keyword.get(constraints, :min))})",
      not is_nil(Keyword.get(constraints, :min))
    )
    |> add_pipe_if(
      "v.maxValue(#{fmt_num(Keyword.get(constraints, :max))})",
      not is_nil(Keyword.get(constraints, :max))
    )
    |> add_pipe_if(
      "v.gtValue(#{fmt_num(Keyword.get(constraints, :greater_than))})",
      not is_nil(Keyword.get(constraints, :greater_than))
    )
    |> add_pipe_if(
      "v.ltValue(#{fmt_num(Keyword.get(constraints, :less_than))})",
      not is_nil(Keyword.get(constraints, :less_than))
    )
  end

  defp fmt_num(value) when is_float(value),
    do: :erlang.float_to_binary(value, [:compact, {:decimals, 10}])

  defp fmt_num(value), do: "#{value}"

  defp add_pipe_if(pipes, _entry, false), do: pipes
  defp add_pipe_if(pipes, entry, true), do: [entry | pipes]

  defp build_pipe(base, []), do: base

  defp build_pipe(base, pipes) do
    pipe_actions = pipes |> Enum.reverse() |> Enum.join(", ")
    "v.pipe(#{base}, #{pipe_actions})"
  end

  defp add_regex_pipe(pipes, nil), do: pipes

  defp add_regex_pipe(pipes, regex) when is_struct(regex, Regex) do
    source = Regex.source(regex)

    if SchemaCore.regex_safe_for_js?(source) do
      flags = SchemaCore.build_js_flags(Regex.opts(regex))
      escaped = String.replace(source, "/", "\\/")
      ["v.regex(/#{escaped}/#{flags})" | pipes]
    else
      pipes
    end
  end

  defp add_regex_pipe(pipes, {Spark.Regex, :cache, [pattern, opts]}) do
    add_regex_pipe(pipes, Spark.Regex.cache(pattern, opts))
  end

  defp add_regex_pipe(pipes, _other), do: pipes
end
