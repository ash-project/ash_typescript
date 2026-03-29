# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.SchemaCore do
  @moduledoc """
  Shared logic for schema generation across all validation library targets.

  All resource introspection, topological sorting, field resolution, and structural
  code generation lives here. Output syntax is delegated to a module implementing
  `AshTypescript.Codegen.SchemaFormatter`.

  Consumers (e.g. `ZodSchemaGenerator`) pass `__MODULE__` as the first `formatter`
  argument to each public function.
  """

  alias AshTypescript.Codegen.Helpers, as: CodegenHelpers
  alias AshTypescript.Rpc.Codegen.Helpers.ActionIntrospection
  alias AshTypescript.TypeSystem.Introspection

  import AshTypescript.Helpers

  @typed_containers [Ash.Type.Map, Ash.Type.Keyword, Ash.Type.Tuple, Ash.Type.Struct]

  # ─────────────────────────────────────────────────────────────────
  # Core Type Mapping
  # ─────────────────────────────────────────────────────────────────

  @doc """
  Maps an Ash type + constraints to a schema string using the given formatter.
  """
  def map_type(formatter, nil, _constraints), do: formatter.null_schema()

  def map_type(formatter, type, constraints) do
    if is_custom_type?(type) do
      formatter.any_schema()
    else
      map_type_inner(formatter, type, constraints)
    end
  end

  defp map_type_inner(formatter, type, constraints) do
    {unwrapped_type, full_constraints} = Introspection.unwrap_new_type(type, constraints)

    aggregate_types = formatter.aggregate_types()
    simple_primitives = formatter.simple_primitives()
    third_party_types = formatter.third_party_types()
    atom_primitives = formatter.atom_primitives()

    cond do
      is_atom(type) and Map.has_key?(aggregate_types, type) ->
        Map.get(aggregate_types, type)

      is_atom(type) and Map.has_key?(atom_primitives, type) ->
        Map.get(atom_primitives, type)

      match?({:array, _}, type) ->
        {:array, inner_type} = type
        inner_constraints = Keyword.get(constraints, :items, [])
        inner_schema = map_type(formatter, inner_type, inner_constraints)
        formatter.wrap_array(inner_schema)

      Map.has_key?(simple_primitives, unwrapped_type) ->
        Map.get(simple_primitives, unwrapped_type)

      Map.has_key?(third_party_types, unwrapped_type) ->
        Map.get(third_party_types, unwrapped_type)

      unwrapped_type in [Ash.Type.String, Ash.Type.CiString] ->
        formatter.format_string(full_constraints, false)

      unwrapped_type == Ash.Type.Integer ->
        formatter.format_integer(full_constraints)

      unwrapped_type == Ash.Type.Float ->
        formatter.format_float(full_constraints)

      unwrapped_type == Ash.Type.Atom ->
        map_atom_type(formatter, full_constraints)

      unwrapped_type in @typed_containers ->
        map_typed_container(formatter, unwrapped_type, full_constraints)

      unwrapped_type == Ash.Type.Union ->
        map_union_type(formatter, full_constraints)

      unwrapped_type == AshPostgres.Ltree ->
        map_ltree_type(formatter, full_constraints)

      Introspection.is_embedded_resource?(unwrapped_type) ->
        map_resource_ref(formatter, unwrapped_type)

      Spark.implements_behaviour?(unwrapped_type, Ash.Type.Enum) ->
        map_enum_type(formatter, unwrapped_type)

      is_custom_type?(unwrapped_type) ->
        formatter.custom_type_fallback()

      true ->
        formatter.any_schema()
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Public API — type resolution
  # ─────────────────────────────────────────────────────────────────

  @doc """
  Maps Ash type structs (attribute/argument maps) to a schema string.
  Handles `allow_nil?` for string types (non-nullable strings get min-length 1).
  """
  def get_type(formatter, type_and_constraints, context \\ nil)

  def get_type(formatter, kind, _context) when is_atom(kind) and not is_nil(kind) do
    Map.get(formatter.aggregate_types(), kind, formatter.any_schema())
  end

  def get_type(formatter, %{type: type, constraints: constraints} = attr, _context) do
    allow_nil? = Map.get(attr, :allow_nil?, true)
    map_type_with_allow_nil(formatter, type, constraints || [], allow_nil?)
  end

  def get_type(formatter, %{type: type} = attr, _context) do
    allow_nil? = Map.get(attr, :allow_nil?, true)
    map_type_with_allow_nil(formatter, type, [], allow_nil?)
  end

  defp map_type_with_allow_nil(formatter, type, constraints, allow_nil?) do
    {unwrapped_type, full_constraints} = Introspection.unwrap_new_type(type, constraints)

    if unwrapped_type in [Ash.Type.String, Ash.Type.CiString] do
      require_non_empty = not allow_nil?
      formatter.format_string(full_constraints, require_non_empty)
    else
      map_type(formatter, type, constraints)
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Public API — schema generation
  # ─────────────────────────────────────────────────────────────────

  @doc """
  Generates a schema definition for an RPC action's input.
  Returns an empty string when the action has no input.
  """
  def generate_action_schema(formatter, resource, action, rpc_action_name) do
    if ActionIntrospection.action_input_type(resource, action) != :none do
      suffix = formatter.schema_suffix()
      schema_name = format_output_field("#{rpc_action_name}#{suffix}")

      field_defs =
        case action.type do
          :read ->
            arguments = Enum.filter(action.arguments, & &1.public?)
            if arguments != [], do: Enum.map(arguments, &process_argument_field(formatter, resource, action, &1)), else: []

          :create ->
            accepts = Ash.Resource.Info.action(resource, action.name).accept || []
            arguments = Enum.filter(action.arguments, & &1.public?)

            if accepts != [] || arguments != [] do
              Enum.map(accepts, &process_accept_field(formatter, resource, &1, action)) ++
                Enum.map(arguments, &process_argument_field(formatter, resource, action, &1))
            else
              []
            end

          action_type when action_type in [:update, :destroy] ->
            arguments = Enum.filter(action.arguments, & &1.public?)

            if action.accept != [] || arguments != [] do
              Enum.map(action.accept, &process_accept_field(formatter, resource, &1, action)) ++
                Enum.map(arguments, &process_argument_field(formatter, resource, action, &1))
            else
              []
            end

          :action ->
            arguments = Enum.filter(action.arguments, & &1.public?)
            if arguments != [], do: Enum.map(arguments, &process_argument_field(formatter, resource, action, &1)), else: []
        end

      field_lines = Enum.map(field_defs, fn {name, type} -> "  #{name}: #{type}," end)
      kw = formatter.object_keyword()

      """
      export const #{schema_name} = #{kw}.object({
      #{Enum.join(field_lines, "\n")}
      });
      """
    else
      ""
    end
  end

  @doc """
  Generates schemas for a list of resources (embedded resources, struct args).
  Returns an empty string when generation is disabled or the list is empty.
  """
  def generate_schemas_for_resources(formatter, resources) do
    if formatter.generate_schemas_enabled?() and resources != [] do
      schemas =
        resources
        |> Enum.uniq()
        |> topological_sort()
        |> Enum.map_join("\n\n", &generate_schema_for_resource(formatter, &1))

      """
      // ============================
      // #{formatter.section_header()}
      // ============================

      #{schemas}
      """
    else
      ""
    end
  end

  @doc "Generates a schema for a single resource."
  def generate_schema_for_resource(formatter, resource) do
    generate_schema_impl(formatter, resource)
  end

  # ─────────────────────────────────────────────────────────────────
  # Regex utilities (shared by both formatters)
  # ─────────────────────────────────────────────────────────────────

  @doc "Returns true when a regex source string is safe to emit as a JS literal."
  def regex_safe_for_js?(source) do
    pcre_only_patterns = [
      ~r/\(\?<[!=]/,
      ~r/[*+?]\+/,
      ~r/\(\?>/,
      ~r/\(\?P</,
      ~r/\(\?[imsxADSUXJ]/,
      ~r/\(\?R\)/,
      ~r/\(\?[0-9]/,
      ~r/\(\?\([^)]+\)/,
      ~r/\\[AG]/,
      ~r/\\[pP]\{/
    ]

    not Enum.any?(pcre_only_patterns, &Regex.match?(&1, source))
  end

  @doc "Builds a JS regex flag string from Elixir Regex opts."
  def build_js_flags(opts) do
    []
    |> then(fn flags -> if :caseless in opts, do: ["i" | flags], else: flags end)
    |> then(fn flags -> if :multiline in opts, do: ["m" | flags], else: flags end)
    |> then(fn flags -> if :dotall in opts, do: ["s" | flags], else: flags end)
    |> Enum.join()
  end

  # ─────────────────────────────────────────────────────────────────
  # Private — type-specific dispatch
  # ─────────────────────────────────────────────────────────────────

  defp map_atom_type(formatter, constraints) do
    case Keyword.get(constraints, :one_of) do
      nil ->
        formatter.format_string([], false)

      values ->
        enum_values = Enum.map_join(values, ", ", &"\"#{to_string(&1)}\"")
        formatter.format_enum(enum_values)
    end
  end

  defp map_typed_container(formatter, type, constraints) do
    fields = Keyword.get(constraints, :fields)
    instance_of = Keyword.get(constraints, :instance_of)

    cond do
      fields != nil ->
        field_name_mappings = get_field_name_mappings(constraints)
        build_object_type(formatter, fields, nil, field_name_mappings)

      type == Ash.Type.Struct and instance_of != nil and Spark.Dsl.is?(instance_of, Ash.Resource) ->
        map_resource_ref(formatter, instance_of)

      type == Ash.Type.Struct and instance_of != nil ->
        formatter.wrap_object("")

      true ->
        formatter.wrap_record()
    end
  end

  defp map_resource_ref(formatter, resource) do
    resource_name = CodegenHelpers.build_resource_type_name(resource)
    "#{resource_name}#{formatter.schema_suffix()}"
  end

  defp map_enum_type(formatter, type) do
    enum_values = Enum.map_join(type.values(), ", ", &"\"#{to_string(&1)}\"")
    formatter.format_enum(enum_values)
  rescue
    _ -> formatter.format_string([], false)
  end

  defp map_union_type(formatter, constraints) do
    case Keyword.get(constraints, :types) do
      nil -> formatter.any_schema()
      types -> build_simple_union(formatter, types, nil)
    end
  end

  defp map_ltree_type(formatter, constraints) do
    if Keyword.get(constraints, :escape?, false) do
      formatter.ltree_array()
    else
      formatter.ltree_union()
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Private — object / union builders
  # ─────────────────────────────────────────────────────────────────

  defp build_object_type(formatter, fields, context, field_name_mappings) do
    field_schemas =
      Enum.map_join(fields, ", ", fn {field_name, field_config} ->
        field_type = Keyword.get(field_config, :type, :string)
        field_constraints = Keyword.get(field_config, :constraints, [])
        allow_nil = Keyword.get(field_config, :allow_nil?, false)

        schema_type = get_type(formatter, %{type: field_type, constraints: field_constraints}, context)
        schema_type = if allow_nil, do: formatter.wrap_optional(schema_type), else: schema_type

        base_name =
          if field_name_mappings && Keyword.has_key?(field_name_mappings, field_name),
            do: Keyword.get(field_name_mappings, field_name),
            else: field_name

        "#{format_output_field(base_name)}: #{schema_type}"
      end)

    formatter.wrap_object(field_schemas)
  end

  defp build_simple_union(formatter, types, context) do
    union_schemas =
      Enum.map_join(types, ", ", fn {type_name, config} ->
        formatted_name = format_field(type_name)
        type = Keyword.get(config, :type, :string)
        constraints = Keyword.get(config, :constraints, [])
        schema_type = get_type(formatter, %{type: type, constraints: constraints}, context)
        formatter.wrap_object("#{formatted_name}: #{schema_type}")
      end)

    formatter.wrap_union(union_schemas)
  end

  # ─────────────────────────────────────────────────────────────────
  # Private — field processing
  # ─────────────────────────────────────────────────────────────────

  defp process_argument_field(formatter, resource, action, arg) do
    optional = arg.allow_nil? || arg.default != nil
    formatted_name = format_argument_for_client(resource, action.name, arg.name)
    schema_type = get_type(formatter, arg)
    schema_type = if optional, do: formatter.wrap_optional(schema_type), else: schema_type
    {formatted_name, schema_type}
  end

  defp process_accept_field(formatter, resource, field_name, action) do
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

    schema_type = get_type(formatter, attr)
    schema_type = if optional, do: formatter.wrap_optional(schema_type), else: schema_type
    {formatted_name, schema_type}
  end

  defp format_argument_for_client(resource, action_name, arg_name) do
    mapped = AshTypescript.Resource.Info.get_mapped_argument_name(resource, action_name, arg_name)

    cond do
      is_binary(mapped) -> mapped
      mapped == arg_name -> format_field(arg_name)
      true -> format_field(mapped)
    end
  end

  defp format_field(field_name) do
    AshTypescript.FieldFormatter.format_field_name(field_name, AshTypescript.Rpc.output_field_formatter())
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

  # ─────────────────────────────────────────────────────────────────
  # Private — resource schema generation
  # ─────────────────────────────────────────────────────────────────

  defp generate_schema_impl(formatter, resource) do
    resource_name = CodegenHelpers.build_resource_type_name(resource)
    schema_name = "#{resource_name}#{formatter.schema_suffix()}"
    kw = formatter.object_keyword()

    fields =
      resource
      |> Ash.Resource.Info.public_attributes()
      |> Enum.map_join("\n", fn attr ->
        formatted_name =
          AshTypescript.FieldFormatter.format_field_for_client(
            attr.name,
            resource,
            AshTypescript.Rpc.output_field_formatter()
          )

        schema_type = get_type(formatter, attr)

        schema_type =
          if attr.allow_nil? || attr.default != nil,
            do: formatter.wrap_optional(schema_type),
            else: schema_type

        "  #{formatted_name}: #{schema_type},"
      end)

    """
    export const #{schema_name} = #{kw}.object({
    #{fields}
    });
    """
  end

  # ─────────────────────────────────────────────────────────────────
  # Private — topological sort (Kahn's algorithm)
  # ─────────────────────────────────────────────────────────────────

  defp topological_sort(resources) do
    resource_set = MapSet.new(resources)

    deps_map =
      Map.new(resources, fn resource ->
        {resource, find_resource_dependencies(resource, resource_set)}
      end)

    {sorted, remaining} = kahns_sort(resources, deps_map)

    sorted ++ Enum.filter(resources, &MapSet.member?(remaining, &1))
  end

  defp kahns_sort(resources, deps_map) do
    do_kahns_sort([], MapSet.new(resources), deps_map)
  end

  defp do_kahns_sort(sorted, remaining, deps_map) do
    ready =
      remaining
      |> Enum.filter(fn resource ->
        deps = Map.get(deps_map, resource, [])
        Enum.all?(deps, fn dep -> not MapSet.member?(remaining, dep) end)
      end)
      |> Enum.sort_by(&inspect/1)

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
      Introspection.is_embedded_resource?(unwrapped_type) and MapSet.member?(resource_set, unwrapped_type) ->
        [unwrapped_type]

      unwrapped_type == Ash.Type.Struct ->
        instance_of = Keyword.get(full_constraints, :instance_of)

        if instance_of != nil and Spark.Dsl.is?(instance_of, Ash.Resource) and
             MapSet.member?(resource_set, instance_of),
           do: [instance_of],
           else: []

      true ->
        []
    end
  end

  defp extract_resource_deps(_type, _constraints, _resource_set), do: []
end
