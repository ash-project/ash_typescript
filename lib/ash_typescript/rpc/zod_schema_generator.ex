# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
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

  # ─────────────────────────────────────────────────────────────────
  # Type Constants
  # ─────────────────────────────────────────────────────────────────

  # Aggregate kind atoms -> Zod schemas
  @aggregate_zod_types %{
    :count => "z.number().int()",
    :sum => "z.number()",
    :exists => "z.boolean()",
    :avg => "z.number()",
    :min => "z.any()",
    :max => "z.any()",
    :first => "z.any()",
    :last => "z.any()",
    :list => "z.array(z.any())",
    :custom => "z.any()",
    :integer => "z.number().int()"
  }

  # Simple primitive types (no constraint handling needed)
  # Note: Ash.Type.Atom is NOT here - it needs constraint handling for one_of
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

  # Atom symbol primitives (used as type keys in structs)
  @atom_primitives %{
    :map => "z.record(z.string(), z.any())",
    :sum => "z.number()",
    :count => "z.number().int()"
  }

  # Third-party type mappings
  @third_party_types %{
    AshDoubleEntry.ULID => "z.string()",
    AshMoney.Types.Money => "z.object({})"
  }

  # Typed container types that share similar handling
  @typed_containers [Ash.Type.Map, Ash.Type.Keyword, Ash.Type.Tuple, Ash.Type.Struct]

  # ─────────────────────────────────────────────────────────────────
  # Private Helpers
  # ─────────────────────────────────────────────────────────────────

  defp format_field(field_name) do
    AshTypescript.FieldFormatter.format_field_name(field_name, formatter())
  end

  defp formatter do
    AshTypescript.Rpc.output_field_formatter()
  end

  defp process_argument_field(resource, action, arg) do
    optional = arg.allow_nil? || arg.default != nil
    formatted_name = format_argument_for_client(resource, action.name, arg.name)
    zod_type = get_zod_type(arg)
    zod_type = if optional, do: "#{zod_type}.optional()", else: zod_type

    {formatted_name, zod_type}
  end

  defp process_accept_field(resource, field_name, action) do
    attr = Ash.Resource.Info.attribute(resource, field_name)

    optional =
      if action.type in [:update, :destroy] do
        field_name not in action.require_attributes
      else
        field_name in action.allow_nil_input || attr.allow_nil? || attr.default != nil
      end

    formatted_name =
      AshTypescript.FieldFormatter.format_field_for_client(
        field_name,
        resource,
        AshTypescript.Rpc.output_field_formatter()
      )

    zod_type = get_zod_type(attr)
    zod_type = if optional, do: "#{zod_type}.optional()", else: zod_type

    {formatted_name, zod_type}
  end

  # Helper to format argument name for client output
  defp format_argument_for_client(resource, action_name, arg_name) do
    mapped = AshTypescript.Resource.Info.get_mapped_argument_name(resource, action_name, arg_name)

    cond do
      is_binary(mapped) -> mapped
      mapped == arg_name -> format_field(arg_name)
      true -> format_field(mapped)
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Core Dispatcher
  # ─────────────────────────────────────────────────────────────────

  @doc """
  Maps an Ash type to a Zod schema string using unified type-driven dispatch.

  ## Parameters
  - `type` - The Ash type (atom, tuple, or module)
  - `constraints` - Type constraints (keyword list)

  ## Returns
  A Zod schema string (e.g., "z.string().min(1)")
  """
  @spec map_zod_type(atom() | tuple(), keyword()) :: String.t()
  def map_zod_type(type, constraints \\ [])

  # Handle nil type
  def map_zod_type(nil, _constraints), do: "z.null()"

  def map_zod_type(type, constraints) do
    # Check custom types BEFORE unwrapping NewTypes so that NewTypes with
    # typescript_type_name are respected (issue #52)
    if is_custom_type?(type) do
      "z.any()"
    else
      map_zod_type_inner(type, constraints)
    end
  end

  defp map_zod_type_inner(type, constraints) do
    # Unwrap NewTypes first to get the underlying type
    {unwrapped_type, full_constraints} = Introspection.unwrap_new_type(type, constraints)

    cond do
      # Aggregate atoms (fast path) - e.g., :count, :sum from aggregates
      is_atom(type) and Map.has_key?(@aggregate_zod_types, type) ->
        Map.get(@aggregate_zod_types, type)

      # Atom symbol primitives - e.g., :map, :sum when used as type keys
      is_atom(type) and Map.has_key?(@atom_primitives, type) ->
        Map.get(@atom_primitives, type)

      # Arrays - recurse for inner type
      match?({:array, _}, type) ->
        {:array, inner_type} = type
        inner_constraints = Keyword.get(constraints, :items, [])
        inner_zod = map_zod_type(inner_type, inner_constraints)
        "z.array(#{inner_zod})"

      # Simple primitives (no constraint handling needed)
      Map.has_key?(@simple_primitives, unwrapped_type) ->
        Map.get(@simple_primitives, unwrapped_type)

      # Third-party types
      Map.has_key?(@third_party_types, unwrapped_type) ->
        Map.get(@third_party_types, unwrapped_type)

      # String types with potential constraints
      unwrapped_type in [Ash.Type.String, Ash.Type.CiString] ->
        map_string_type(full_constraints)

      # Number types with potential constraints
      unwrapped_type == Ash.Type.Integer ->
        map_integer_type(full_constraints)

      unwrapped_type == Ash.Type.Float ->
        map_float_type(full_constraints)

      # Ash.Type.Atom with potential one_of constraint
      unwrapped_type == Ash.Type.Atom ->
        map_atom_type(full_constraints)

      # Typed containers (Map, Keyword, Tuple, Struct)
      unwrapped_type in @typed_containers ->
        map_typed_container(unwrapped_type, full_constraints)

      # Union type
      unwrapped_type == Ash.Type.Union ->
        map_union_type(full_constraints)

      # AshPostgres.Ltree (special handling)
      unwrapped_type == AshPostgres.Ltree ->
        map_ltree_type(full_constraints)

      # Embedded resource
      Introspection.is_embedded_resource?(unwrapped_type) ->
        map_resource_type(unwrapped_type)

      # Enum type
      Spark.implements_behaviour?(unwrapped_type, Ash.Type.Enum) ->
        map_enum_type(unwrapped_type)

      # Custom type with typescript_type_name
      is_custom_type?(unwrapped_type) ->
        "z.string()"

      # Fallback
      true ->
        "z.any()"
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Type-Specific Handlers
  # ─────────────────────────────────────────────────────────────────

  defp map_string_type(constraints) do
    if constraints == [] do
      "z.string()"
    else
      # Note: allow_nil? handling is done at the field level, not here
      build_string_zod_with_constraints(constraints, false)
    end
  end

  defp map_integer_type(constraints) do
    if constraints == [] do
      "z.number().int()"
    else
      build_integer_zod_with_constraints(constraints)
    end
  end

  defp map_float_type(constraints) do
    if constraints == [] do
      "z.number()"
    else
      build_float_zod_with_constraints(constraints)
    end
  end

  defp map_atom_type(constraints) do
    case Keyword.get(constraints, :one_of) do
      nil ->
        "z.string()"

      values ->
        enum_values = values |> Enum.map_join(", ", &"\"#{to_string(&1)}\"")
        "z.enum([#{enum_values}])"
    end
  end

  defp map_typed_container(type, constraints) do
    fields = Keyword.get(constraints, :fields)
    instance_of = Keyword.get(constraints, :instance_of)

    cond do
      # Has field constraints - build object schema
      fields != nil ->
        field_name_mappings = get_field_name_mappings(constraints)
        build_zod_object_type(fields, nil, field_name_mappings)

      # Ash.Type.Struct with instance_of pointing to resource
      type == Ash.Type.Struct and instance_of != nil and Spark.Dsl.is?(instance_of, Ash.Resource) ->
        map_resource_type(instance_of)

      # Ash.Type.Struct with non-resource instance_of
      type == Ash.Type.Struct and instance_of != nil ->
        "z.object({})"

      # Fallback to record type
      true ->
        "z.record(z.string(), z.any())"
    end
  end

  defp map_resource_type(resource) do
    resource_name = CodegenHelpers.build_resource_type_name(resource)
    suffix = AshTypescript.Rpc.zod_schema_suffix()
    "#{resource_name}#{suffix}"
  end

  defp map_enum_type(type) do
    enum_values = Enum.map_join(type.values(), ", ", &"\"#{to_string(&1)}\"")
    "z.enum([#{enum_values}])"
  rescue
    _ -> "z.string()"
  end

  defp map_union_type(constraints) do
    case Keyword.get(constraints, :types) do
      nil -> "z.any()"
      types -> build_zod_union_type(types, nil)
    end
  end

  defp map_ltree_type(constraints) do
    if Keyword.get(constraints, :escape?, false) do
      "z.array(z.string())"
    else
      "z.union([z.string(), z.array(z.string())])"
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Public API
  # ─────────────────────────────────────────────────────────────────

  @doc """
  Maps Ash types to Zod schema constructors.
  Backward compatible wrapper around map_zod_type/2.
  """
  def get_zod_type(type_and_constraints, context \\ nil)

  # Handle bare atoms (aggregate kinds) - use map lookup for fast path
  def get_zod_type(kind, _context) when is_atom(kind) and not is_nil(kind) do
    Map.get(@aggregate_zod_types, kind, "z.any()")
  end

  # Handle maps with type/constraints - delegate to unified dispatcher
  def get_zod_type(%{type: type, constraints: constraints} = attr, _context) do
    allow_nil? = Map.get(attr, :allow_nil?, true)
    map_zod_type_with_allow_nil(type, constraints || [], allow_nil?)
  end

  # Handle maps with type but no constraints
  def get_zod_type(%{type: type} = attr, _context) do
    allow_nil? = Map.get(attr, :allow_nil?, true)
    map_zod_type_with_allow_nil(type, [], allow_nil?)
  end

  # Helper that wraps map_zod_type and handles allow_nil? for string types
  defp map_zod_type_with_allow_nil(type, constraints, allow_nil?) do
    {unwrapped_type, full_constraints} = Introspection.unwrap_new_type(type, constraints)

    # For string types, pass require_non_empty to get correct ordering of constraints
    if unwrapped_type in [Ash.Type.String, Ash.Type.CiString] do
      require_non_empty = not allow_nil?

      if full_constraints == [] do
        if require_non_empty do
          "z.string().min(1)"
        else
          "z.string()"
        end
      else
        build_string_zod_with_constraints(full_constraints, require_non_empty)
      end
    else
      map_zod_type(type, constraints)
    end
  end

  @doc """
  Generates a Zod schema definition for action input validation.
  """
  def generate_zod_schema(resource, action, rpc_action_name) do
    if ActionIntrospection.action_input_type(resource, action) != :none do
      suffix = AshTypescript.Rpc.zod_schema_suffix()
      schema_name = format_output_field("#{rpc_action_name}#{suffix}")

      zod_field_defs =
        case action.type do
          :read ->
            arguments = Enum.filter(action.arguments, & &1.public?)

            if arguments != [] do
              Enum.map(arguments, &process_argument_field(resource, action, &1))
            else
              []
            end

          :create ->
            accepts = Ash.Resource.Info.action(resource, action.name).accept || []
            arguments = Enum.filter(action.arguments, & &1.public?)

            if accepts != [] || arguments != [] do
              accept_field_defs = Enum.map(accepts, &process_accept_field(resource, &1, action))

              argument_field_defs =
                Enum.map(arguments, &process_argument_field(resource, action, &1))

              accept_field_defs ++ argument_field_defs
            else
              []
            end

          action_type when action_type in [:update, :destroy] ->
            arguments = Enum.filter(action.arguments, & &1.public?)

            if action.accept != [] || arguments != [] do
              # Pass action to check require_attributes for optionality
              accept_field_defs =
                Enum.map(action.accept, &process_accept_field(resource, &1, action))

              argument_field_defs =
                Enum.map(arguments, &process_argument_field(resource, action, &1))

              accept_field_defs ++ argument_field_defs
            else
              []
            end

          :action ->
            arguments = Enum.filter(action.arguments, & &1.public?)

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
  Generates Zod schemas for resources that need input validation.

  This includes embedded resources and resources used as struct arguments in RPC actions.
  """
  def generate_zod_schemas_for_resources(resources) do
    if AshTypescript.Rpc.generate_zod_schemas?() and resources != [] do
      schemas =
        resources
        |> Enum.uniq()
        |> topological_sort()
        |> Enum.map_join("\n\n", &generate_zod_schema_for_resource/1)

      """
      // ============================
      // Zod Schemas for Input Resources
      // ============================

      #{schemas}
      """
    else
      ""
    end
  end

  @doc """
  Generates a Zod schema for a single resource.
  """
  def generate_zod_schema_for_resource(resource) do
    generate_zod_schema_impl(resource)
  end

  defp topological_sort(resources) do
    resource_set = MapSet.new(resources)

    deps_map =
      Map.new(resources, fn resource ->
        {resource, find_resource_dependencies(resource, resource_set)}
      end)

    {sorted, remaining} = kahns_sort(resources, deps_map)

    cycle_resources =
      resources
      |> Enum.filter(&MapSet.member?(remaining, &1))

    sorted ++ cycle_resources
  end

  defp kahns_sort(resources, deps_map) do
    remaining = MapSet.new(resources)
    do_kahns_sort([], remaining, deps_map)
  end

  defp do_kahns_sort(sorted, remaining, deps_map) do
    ready =
      remaining
      |> Enum.filter(fn resource ->
        deps = Map.get(deps_map, resource, [])
        Enum.all?(deps, fn dep -> not MapSet.member?(remaining, dep) end)
      end)

    case ready do
      [] ->
        {sorted, remaining}

      _ ->
        new_remaining = Enum.reduce(ready, remaining, &MapSet.delete(&2, &1))
        do_kahns_sort(sorted ++ ready, new_remaining, deps_map)
    end
  end

  defp find_resource_dependencies(resource, resource_set) do
    resource
    |> Ash.Resource.Info.public_attributes()
    |> Enum.flat_map(fn attr ->
      extract_resource_deps(attr.type, attr.constraints, resource_set)
    end)
    |> Enum.uniq()
  end

  defp extract_resource_deps({:array, inner_type}, constraints, resource_set) do
    inner_constraints = Keyword.get(constraints, :items, [])
    extract_resource_deps(inner_type, inner_constraints, resource_set)
  end

  defp extract_resource_deps(type, constraints, resource_set)
       when is_atom(type) and not is_nil(type) do
    {unwrapped_type, full_constraints} = Introspection.unwrap_new_type(type, constraints)

    cond do
      Introspection.is_embedded_resource?(unwrapped_type) and
          MapSet.member?(resource_set, unwrapped_type) ->
        [unwrapped_type]

      unwrapped_type == Ash.Type.Struct ->
        instance_of = Keyword.get(full_constraints, :instance_of)

        if instance_of != nil and Spark.Dsl.is?(instance_of, Ash.Resource) and
             MapSet.member?(resource_set, instance_of) do
          [instance_of]
        else
          []
        end

      true ->
        []
    end
  end

  defp extract_resource_deps(_type, _constraints, _resource_set), do: []

  defp generate_zod_schema_impl(resource) do
    resource_name = CodegenHelpers.build_resource_type_name(resource)
    suffix = AshTypescript.Rpc.zod_schema_suffix()
    schema_name = "#{resource_name}#{suffix}"

    zod_fields =
      resource
      |> Ash.Resource.Info.public_attributes()
      |> Enum.map_join("\n", fn attr ->
        formatted_name =
          AshTypescript.FieldFormatter.format_field_for_client(
            attr.name,
            resource,
            AshTypescript.Rpc.output_field_formatter()
          )

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

  defp get_field_name_mappings(constraints) do
    instance_of = Keyword.get(constraints, :instance_of)

    if instance_of && function_exported?(instance_of, :typescript_field_names, 0) do
      instance_of.typescript_field_names()
    else
      nil
    end
  end

  defp is_custom_type?(type), do: Introspection.is_custom_type?(type)

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
