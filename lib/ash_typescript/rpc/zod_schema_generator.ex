# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.ZodSchemaGenerator do
  @moduledoc """
  Generates Zod validation schemas for Ash resources and actions.

  This module handles the generation of Zod schemas for TypeScript validation,
  supporting all Ash types including embedded resources, union types, and custom types.
  """

  alias AshTypescript.Codegen.Helpers, as: CodegenHelpers
  alias AshTypescript.Rpc.Codegen.Helpers.ActionIntrospection
  alias AshTypescript.TypeSystem.Introspection

  import AshTypescript.Helpers

  # Helper to format field with output formatter
  defp format_field(field_name) do
    AshTypescript.FieldFormatter.format_field(field_name, formatter())
  end

  # Get formatter (called at runtime, not compile time)
  defp formatter do
    AshTypescript.Rpc.output_field_formatter()
  end

  # Helper to process an argument into a Zod field definition
  defp process_argument_field(resource, action, arg) do
    optional = arg.allow_nil? || arg.default != nil

    mapped_name =
      AshTypescript.Resource.Info.get_mapped_argument_name(
        resource,
        action.name,
        arg.name
      )

    formatted_name = format_field(mapped_name)
    zod_type = get_zod_type(arg)
    zod_type = if optional, do: "#{zod_type}.optional()", else: zod_type

    {formatted_name, zod_type}
  end

  # Helper to process an accept field into a Zod field definition
  defp process_accept_field(resource, field_name) do
    attr = Ash.Resource.Info.attribute(resource, field_name)
    optional = attr.allow_nil? || attr.default != nil

    mapped_name = AshTypescript.Resource.Info.get_mapped_field_name(resource, field_name)
    formatted_name = format_field(mapped_name)
    zod_type = get_zod_type(attr)
    zod_type = if optional, do: "#{zod_type}.optional()", else: zod_type

    {formatted_name, zod_type}
  end

  @doc """
  Maps Ash types to Zod schema constructors.
  Mirrors the pattern of get_ts_type/2 but generates Zod validation schemas.
  """
  def get_zod_type(type_and_constraints, context \\ nil)

  def get_zod_type(:count, _), do: "z.number().int()"
  def get_zod_type(:sum, _), do: "z.number()"
  def get_zod_type(:exists, _), do: "z.boolean()"
  def get_zod_type(:avg, _), do: "z.number()"
  def get_zod_type(:min, _), do: "z.any()"
  def get_zod_type(:max, _), do: "z.any()"
  def get_zod_type(:first, _), do: "z.any()"
  def get_zod_type(:last, _), do: "z.any()"
  def get_zod_type(:list, _), do: "z.array(z.any())"
  def get_zod_type(:custom, _), do: "z.any()"
  def get_zod_type(:integer, _), do: "z.number().int()"

  def get_zod_type(%{type: nil}, _), do: "z.null()"
  def get_zod_type(%{type: :sum}, _), do: "z.number()"
  def get_zod_type(%{type: :count}, _), do: "z.number().int()"
  def get_zod_type(%{type: :map}, _), do: "z.record(z.string(), z.any())"

  def get_zod_type(%{type: Ash.Type.Atom, constraints: constraints}, _) when constraints != [] do
    case Keyword.get(constraints, :one_of) do
      nil ->
        "z.string()"

      values ->
        enum_values = values |> Enum.map_join(", ", &"\"#{to_string(&1)}\"")
        "z.enum([#{enum_values}])"
    end
  end

  def get_zod_type(%{type: Ash.Type.Atom}, _), do: "z.string()"

  def get_zod_type(%{type: Ash.Type.String, constraints: constraints, allow_nil?: false}, _)
      when constraints != [] do
    build_string_zod_with_constraints(constraints, true)
  end

  def get_zod_type(%{type: Ash.Type.String, constraints: constraints}, _)
      when constraints != [] do
    build_string_zod_with_constraints(constraints, false)
  end

  def get_zod_type(%{type: Ash.Type.String, allow_nil?: false}, _), do: "z.string().min(1)"
  def get_zod_type(%{type: Ash.Type.String}, _), do: "z.string()"

  def get_zod_type(%{type: Ash.Type.CiString, constraints: constraints, allow_nil?: false}, _)
      when constraints != [] do
    build_string_zod_with_constraints(constraints, true)
  end

  def get_zod_type(%{type: Ash.Type.CiString, constraints: constraints}, _)
      when constraints != [] do
    build_string_zod_with_constraints(constraints, false)
  end

  def get_zod_type(%{type: Ash.Type.CiString, allow_nil?: false}, _), do: "z.string().min(1)"
  def get_zod_type(%{type: Ash.Type.CiString}, _), do: "z.string()"

  def get_zod_type(%{type: Ash.Type.Integer, constraints: constraints}, _)
      when constraints != [] do
    build_integer_zod_with_constraints(constraints)
  end

  def get_zod_type(%{type: Ash.Type.Integer}, _), do: "z.number().int()"

  def get_zod_type(%{type: Ash.Type.Float, constraints: constraints}, _)
      when constraints != [] do
    build_float_zod_with_constraints(constraints)
  end

  def get_zod_type(%{type: Ash.Type.Float}, _), do: "z.number()"
  def get_zod_type(%{type: Ash.Type.Decimal}, _), do: "z.string()"
  def get_zod_type(%{type: Ash.Type.Boolean}, _), do: "z.boolean()"
  def get_zod_type(%{type: Ash.Type.UUID}, _), do: "z.uuid()"
  def get_zod_type(%{type: Ash.Type.UUIDv7}, _), do: "z.uuid()"

  def get_zod_type(%{type: Ash.Type.Date}, _), do: "z.iso.date()"
  def get_zod_type(%{type: Ash.Type.Time}, _), do: "z.string().time()"
  def get_zod_type(%{type: Ash.Type.TimeUsec}, _), do: "z.string().time()"
  def get_zod_type(%{type: Ash.Type.UtcDatetime}, _), do: "z.iso.datetime()"
  def get_zod_type(%{type: Ash.Type.UtcDatetimeUsec}, _), do: "z.iso.datetime()"
  def get_zod_type(%{type: Ash.Type.DateTime}, _), do: "z.iso.datetime()"
  def get_zod_type(%{type: Ash.Type.NaiveDatetime}, _), do: "z.iso.datetime()"
  def get_zod_type(%{type: Ash.Type.Duration}, _), do: "z.string()"
  def get_zod_type(%{type: Ash.Type.DurationName}, _), do: "z.string()"

  def get_zod_type(%{type: Ash.Type.Binary}, _), do: "z.string()"
  def get_zod_type(%{type: Ash.Type.UrlEncodedBinary}, _), do: "z.string()"
  def get_zod_type(%{type: Ash.Type.File}, _), do: "z.any()"
  def get_zod_type(%{type: Ash.Type.Function}, _), do: "z.function()"
  def get_zod_type(%{type: Ash.Type.Term}, _), do: "z.any()"
  def get_zod_type(%{type: Ash.Type.Vector}, _), do: "z.array(z.number())"
  def get_zod_type(%{type: Ash.Type.Module}, _), do: "z.string()"

  def get_zod_type(%{type: Ash.Type.Map, constraints: constraints}, context)
      when constraints != [] do
    case Keyword.get(constraints, :fields) do
      nil -> "z.record(z.string(), z.any())"
      fields -> build_zod_object_type(fields, context, nil)
    end
  end

  def get_zod_type(%{type: Ash.Type.Map}, _), do: "z.record(z.string(), z.any())"

  def get_zod_type(%{type: Ash.Type.Keyword, constraints: constraints}, context)
      when constraints != [] do
    case Keyword.get(constraints, :fields) do
      nil -> "z.record(z.string(), z.any())"
      fields -> build_zod_object_type(fields, context, nil)
    end
  end

  def get_zod_type(%{type: Ash.Type.Keyword}, _), do: "z.record(z.string(), z.any())"

  def get_zod_type(%{type: Ash.Type.Tuple, constraints: constraints}, context) do
    case Keyword.get(constraints, :fields) do
      nil -> "z.record(z.string(), z.any())"
      fields -> build_zod_object_type(fields, context, nil)
    end
  end

  def get_zod_type(%{type: Ash.Type.Struct, constraints: constraints}, context) do
    instance_of = Keyword.get(constraints, :instance_of)
    fields = Keyword.get(constraints, :fields)

    cond do
      fields != nil ->
        build_zod_object_type(fields, context, nil)

      instance_of != nil ->
        if Spark.Dsl.is?(instance_of, Ash.Resource) do
          resource_name = CodegenHelpers.build_resource_type_name(instance_of)
          suffix = AshTypescript.Rpc.zod_schema_suffix()
          "#{resource_name}#{suffix}"
        else
          "z.object({})"
        end

      true ->
        "z.record(z.string(), z.any())"
    end
  end

  def get_zod_type(%{type: Ash.Type.Union, constraints: constraints}, context) do
    case Keyword.get(constraints, :types) do
      nil -> "z.any()"
      types -> build_zod_union_type(types, context)
    end
  end

  def get_zod_type(%{type: {:array, inner_type}, constraints: constraints}, context) do
    inner_constraints = constraints[:items] || []
    inner_zod_type = get_zod_type(%{type: inner_type, constraints: inner_constraints}, context)
    "z.array(#{inner_zod_type})"
  end

  def get_zod_type(%{type: AshDoubleEntry.ULID}, _), do: "z.string()"

  def get_zod_type(%{type: AshPostgres.Ltree, constraints: constraints}, _) do
    escape = Keyword.get(constraints, :escape?, false)

    if escape do
      "z.array(z.string())"
    else
      "z.union([z.string(), z.array(z.string())])"
    end
  end

  def get_zod_type(%{type: AshPostgres.Ltree}, _),
    do: "z.union([z.string(), z.array(z.string())])"

  def get_zod_type(%{type: AshMoney.Types.Money}, _), do: "z.object({})"

  def get_zod_type(%{type: type, constraints: constraints} = attr, context) do
    cond do
      is_custom_type?(type) ->
        "z.string()"

      Introspection.is_embedded_resource?(type) ->
        resource_name = CodegenHelpers.build_resource_type_name(type)
        suffix = AshTypescript.Rpc.zod_schema_suffix()
        "#{resource_name}#{suffix}"

      Ash.Type.NewType.new_type?(type) ->
        sub_type_constraints = Ash.Type.NewType.constraints(type, constraints)
        subtype = Ash.Type.NewType.subtype_of(type)

        # Check if this NewType has typescript_field_names callback
        field_name_mappings =
          if function_exported?(type, :typescript_field_names, 0) do
            type.typescript_field_names()
          else
            nil
          end

        # If it's a map/keyword/tuple/struct type with field mappings, handle specially
        if field_name_mappings &&
             subtype in [Ash.Type.Map, Ash.Type.Keyword, Ash.Type.Tuple, Ash.Type.Struct] do
          case Keyword.get(sub_type_constraints, :fields) do
            nil ->
              get_zod_type(%{attr | type: subtype, constraints: sub_type_constraints}, context)

            fields ->
              build_zod_object_type(fields, context, field_name_mappings)
          end
        else
          get_zod_type(%{attr | type: subtype, constraints: sub_type_constraints}, context)
        end

      Spark.implements_behaviour?(type, Ash.Type.Enum) ->
        enum_values = Enum.map_join(type.values(), ", ", &"\"#{to_string(&1)}\"")
        "z.enum([#{enum_values}])"

      true ->
        "z.any()"
    end
  end

  @doc """
  Generates a Zod schema definition for action input validation.
  """
  def generate_zod_schema(resource, action, rpc_action_name) do
    if ActionIntrospection.action_input_type(resource, action) != :none do
      suffix = AshTypescript.Rpc.zod_schema_suffix()
      schema_name = format_output_field("#{rpc_action_name}_#{suffix}")

      zod_field_defs =
        case action.type do
          :read ->
            arguments = action.arguments

            if arguments != [] do
              Enum.map(arguments, &process_argument_field(resource, action, &1))
            else
              []
            end

          :create ->
            accepts = Ash.Resource.Info.action(resource, action.name).accept || []
            arguments = action.arguments

            if accepts != [] || arguments != [] do
              accept_field_defs = Enum.map(accepts, &process_accept_field(resource, &1))

              argument_field_defs =
                Enum.map(arguments, &process_argument_field(resource, action, &1))

              accept_field_defs ++ argument_field_defs
            else
              []
            end

          action_type when action_type in [:update, :destroy] ->
            if action.accept != [] || action.arguments != [] do
              accept_field_defs = Enum.map(action.accept, &process_accept_field(resource, &1))

              argument_field_defs =
                Enum.map(action.arguments, &process_argument_field(resource, action, &1))

              accept_field_defs ++ argument_field_defs
            else
              []
            end

          :action ->
            arguments = action.arguments

            if arguments != [] do
              Enum.map(arguments, &process_argument_field(resource, action, &1))
            else
              []
            end
        end

      field_lines =
        Enum.map(zod_field_defs, fn {name, zod_type} ->
          "  #{name}: #{zod_type},"
        end)

      """
      export const #{schema_name} = z.object({
      #{Enum.join(field_lines, "\n")}
      });
      """
    else
      ""
    end
  end

  @doc """
  Generates Zod schemas for embedded resources.
  """
  def generate_zod_schemas_for_embedded_resources(embedded_resources) do
    if AshTypescript.Rpc.generate_zod_schemas?() and embedded_resources != [] do
      schemas =
        embedded_resources
        |> Enum.map_join("\n\n", &generate_zod_schema_for_embedded_resource/1)

      """
      // ============================
      // Zod Schemas for Embedded Resources
      // ============================

      #{schemas}
      """
    else
      ""
    end
  end

  @doc """
  Generates a Zod schema for a single embedded resource.
  """
  def generate_zod_schema_for_embedded_resource(resource) do
    resource_name = CodegenHelpers.build_resource_type_name(resource)
    suffix = AshTypescript.Rpc.zod_schema_suffix()
    schema_name = "#{resource_name}#{suffix}"

    zod_fields =
      resource
      |> Ash.Resource.Info.public_attributes()
      |> Enum.map_join("\n", fn attr ->
        mapped_name = AshTypescript.Resource.Info.get_mapped_field_name(resource, attr.name)

        formatted_name = format_field(mapped_name)

        zod_type = get_zod_type(attr)

        zod_type =
          if attr.allow_nil? || attr.default != nil do
            "#{zod_type}.optional()"
          else
            zod_type
          end

        "  #{formatted_name}: #{zod_type},"
      end)

    """
    export const #{schema_name} = z.object({
    #{zod_fields}
    });
    """
  end

  defp build_zod_object_type(fields, context, field_name_mappings) do
    field_schemas =
      fields
      |> Enum.map_join(", ", fn {field_name, field_config} ->
        field_type = Keyword.get(field_config, :type, :string)
        field_constraints = Keyword.get(field_config, :constraints, [])
        allow_nil = Keyword.get(field_config, :allow_nil?, false)

        zod_type = get_zod_type(%{type: field_type, constraints: field_constraints}, context)
        zod_type = if allow_nil, do: "#{zod_type}.optional()", else: zod_type

        base_field_name =
          if field_name_mappings && Keyword.has_key?(field_name_mappings, field_name) do
            Keyword.get(field_name_mappings, field_name)
          else
            field_name
          end

        formatted_field_name = format_output_field(base_field_name)

        "#{formatted_field_name}: #{zod_type}"
      end)

    "z.object({ #{field_schemas} })"
  end

  defp build_zod_union_type(types, context) do
    has_discriminator =
      Enum.any?(types, fn {_name, config} ->
        Keyword.has_key?(config, :tag) && Keyword.has_key?(config, :tag_value)
      end)

    if has_discriminator do
      build_simple_zod_union(types, context)
    else
      build_simple_zod_union(types, context)
    end
  end

  defp build_simple_zod_union(types, context) do
    union_schemas =
      types
      |> Enum.map_join(", ", fn {type_name, config} ->
        formatted_name = format_field(type_name)

        type = Keyword.get(config, :type, :string)
        constraints = Keyword.get(config, :constraints, [])
        zod_type = get_zod_type(%{type: type, constraints: constraints}, context)

        "z.object({#{formatted_name}: #{zod_type}})"
      end)

    "z.union([#{union_schemas}])"
  end

  defp is_custom_type?(type) do
    is_atom(type) and
      Code.ensure_loaded?(type) and
      function_exported?(type, :typescript_type_name, 0) and
      Spark.implements_behaviour?(type, Ash.Type)
  end

  defp build_integer_zod_with_constraints(constraints) do
    base = "z.number().int()"

    base
    |> add_min_constraint(Keyword.get(constraints, :min))
    |> add_max_constraint(Keyword.get(constraints, :max))
  end

  defp build_float_zod_with_constraints(constraints) do
    base = "z.number()"

    base
    |> add_min_constraint(Keyword.get(constraints, :min))
    |> add_max_constraint(Keyword.get(constraints, :max))
    |> add_gt_constraint(Keyword.get(constraints, :greater_than))
    |> add_lt_constraint(Keyword.get(constraints, :less_than))
  end

  defp build_string_zod_with_constraints(constraints, require_non_empty) do
    base = "z.string()"
    min_length = Keyword.get(constraints, :min_length)
    max_length = Keyword.get(constraints, :max_length)

    # If require_non_empty is true and no min_length is set, default to min(1)
    effective_min_length =
      if require_non_empty && is_nil(min_length) do
        1
      else
        min_length
      end

    base
    |> add_string_min_length(effective_min_length)
    |> add_string_max_length(max_length)
    |> add_string_regex(Keyword.get(constraints, :match))
  end

  defp add_min_constraint(zod_str, nil), do: zod_str
  defp add_min_constraint(zod_str, min), do: "#{zod_str}.min(#{min})"

  defp add_max_constraint(zod_str, nil), do: zod_str
  defp add_max_constraint(zod_str, max), do: "#{zod_str}.max(#{max})"

  defp add_gt_constraint(zod_str, nil), do: zod_str
  defp add_gt_constraint(zod_str, gt), do: "#{zod_str}.gt(#{gt})"

  defp add_lt_constraint(zod_str, nil), do: zod_str
  defp add_lt_constraint(zod_str, lt), do: "#{zod_str}.lt(#{lt})"

  defp add_string_min_length(zod_str, nil), do: zod_str
  defp add_string_min_length(zod_str, min), do: "#{zod_str}.min(#{min})"

  defp add_string_max_length(zod_str, nil), do: zod_str
  defp add_string_max_length(zod_str, max), do: "#{zod_str}.max(#{max})"

  defp add_string_regex(zod_str, nil), do: zod_str

  defp add_string_regex(zod_str, regex) when is_struct(regex, Regex) do
    source = Regex.source(regex)

    # Skip regex conversion for PCRE-specific features to avoid silent validation errors
    if regex_is_safe_for_js?(source) do
      opts = Regex.opts(regex)

      js_flags =
        []
        |> then(fn flags -> if :caseless in opts, do: ["i" | flags], else: flags end)
        |> then(fn flags -> if :multiline in opts, do: ["m" | flags], else: flags end)
        |> then(fn flags -> if :dotall in opts, do: ["s" | flags], else: flags end)
        |> Enum.join()

      escaped_source = String.replace(source, "/", "\\/")

      "#{zod_str}.regex(/#{escaped_source}/#{js_flags})"
    else
      # Server-side Ash validation will still enforce the constraint
      zod_str
    end
  end

  defp add_string_regex(zod_str, {Spark.Regex, :cache, [pattern, opts]}) do
    regex = Spark.Regex.cache(pattern, opts)
    add_string_regex(zod_str, regex)
  end

  defp add_string_regex(zod_str, _other), do: zod_str

  # Checks if a regex pattern uses PCRE-specific features incompatible with JavaScript
  defp regex_is_safe_for_js?(source) do
    pcre_only_patterns = [
      # Lookbehind assertions
      ~r/\(\?<[!=]/,
      # Possessive quantifiers
      ~r/[*+?]\+/,
      # Atomic groups
      ~r/\(\?>/,
      # PCRE named captures (JS uses (?<name> which is safe)
      ~r/\(\?P</,
      # Inline modifiers
      ~r/\(\?[imsxADSUXJ]/,
      # Recursion
      ~r/\(\?R\)/,
      # Subroutines
      ~r/\(\?[0-9]/,
      # Conditionals
      ~r/\(\?\([^)]+\)/,
      # PCRE-specific anchors
      ~r/\\[AG]/,
      # Unicode properties (syntax differs)
      ~r/\\[pP]\{/
    ]

    not Enum.any?(pcre_only_patterns, fn pattern -> Regex.match?(pattern, source) end)
  end
end
