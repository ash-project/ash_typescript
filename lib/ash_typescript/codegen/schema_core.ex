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

  alias AshApiSpec.Type, as: SpecType
  alias AshTypescript.Codegen.Helpers, as: CodegenHelpers
  alias AshTypescript.Rpc.Codegen.Helpers.ActionIntrospection
  alias AshTypescript.TypeSystem.Introspection

  import AshTypescript.Helpers

  # AshApiSpec.Type kinds → corresponding Ash type module, used to look up
  # static primitive schemas in `formatter.simple_primitives()`. Only listed
  # for kinds that have a 1:1 module correspondence and don't need
  # constraint-driven formatting (string/integer/float/atom/etc. are handled
  # directly by their kind in the dispatch).
  @kind_to_ash_module %{
    boolean: Ash.Type.Boolean,
    uuid: Ash.Type.UUID,
    date: Ash.Type.Date,
    time: Ash.Type.Time,
    time_usec: Ash.Type.TimeUsec,
    datetime: Ash.Type.DateTime,
    utc_datetime: Ash.Type.UtcDatetime,
    utc_datetime_usec: Ash.Type.UtcDatetimeUsec,
    naive_datetime: Ash.Type.NaiveDatetime,
    duration: Ash.Type.Duration,
    decimal: Ash.Type.Decimal,
    binary: Ash.Type.Binary,
    term: Ash.Type.Term
  }

  # ─────────────────────────────────────────────────────────────────
  # Core Type Mapping (dispatches on %AshApiSpec.Type{})
  # ─────────────────────────────────────────────────────────────────

  # Recursive dispatch — assumes input is already an `%AshApiSpec.Type{}`.
  # Strings are emitted with `require_non_empty: false`; the entry-point
  # `get_type/3` applies non-empty enforcement based on the caller's
  # `allow_nil?` before recursing.
  defp map_spec_type(_formatter, nil), do: nil

  defp map_spec_type(formatter, %SpecType{} = type_info) do
    case type_info.kind do
      kind when kind in [:string, :ci_string] ->
        formatter.format_string(type_info.constraints || [], false)

      :integer ->
        formatter.format_integer(type_info.constraints || [])

      :float ->
        formatter.format_float(type_info.constraints || [])

      :atom ->
        # Atom without `one_of` (which becomes :enum). Plain string.
        formatter.format_string([], false)

      :enum ->
        format_enum_values(formatter, type_info.values || [])

      :array ->
        inner = map_spec_type(formatter, type_info.item_type) || formatter.any_schema()
        formatter.wrap_array(inner)

      :union ->
        map_spec_union(formatter, type_info.members || [])

      kind when kind in [:resource, :embedded_resource] ->
        map_resource_ref(formatter, SpecType.effective_resource(type_info))

      kind when kind in [:map, :keyword, :tuple, :struct] ->
        map_typed_container(formatter, type_info)

      :type_ref ->
        full_type = AshApiSpec.get_type!(AshTypescript.type_lookup(), type_info.module)
        map_spec_type(formatter, full_type)

      :unknown ->
        map_unknown_module(formatter, type_info)

      primitive_kind ->
        lookup_primitive_kind(formatter, primitive_kind)
    end
  end

  # Lookup for primitive kinds with a 1:1 Ash module mapping.
  defp lookup_primitive_kind(formatter, kind) do
    case Map.get(@kind_to_ash_module, kind) do
      nil ->
        formatter.any_schema()

      module ->
        Map.get(formatter.simple_primitives(), module, formatter.any_schema())
    end
  end

  # Handles `:unknown` kinds — custom Ash types (Ltree, ULID, Money, third-party).
  defp map_unknown_module(formatter, %SpecType{module: module} = type_info) do
    cond do
      module == AshPostgres.Ltree ->
        if Keyword.get(type_info.constraints || [], :escape?, false),
          do: formatter.ltree_array(),
          else: formatter.ltree_union()

      module && Map.has_key?(formatter.simple_primitives(), module) ->
        Map.get(formatter.simple_primitives(), module)

      module && Map.has_key?(formatter.third_party_types(), module) ->
        Map.get(formatter.third_party_types(), module)

      module && Introspection.is_custom_type?(module) ->
        formatter.custom_type_fallback()

      true ->
        formatter.any_schema()
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Public API — type resolution
  # ─────────────────────────────────────────────────────────────────

  @doc """
  Maps a type-bearing spec input to a schema string.

  Accepted shapes (all `%AshApiSpec.*{}`):
  - `%AshApiSpec.Type{}` — the canonical spec form
  - `%AshApiSpec.Argument{}` / `%AshApiSpec.Field{}` — anything with a
    `:type` field carrying a `%AshApiSpec.Type{}`
  - Aggregate kind atoms (e.g. `:count`, `:sum`) — looked up in
    `formatter.aggregate_types()`

  Callers must feed spec data. Raw Ash types (atom modules, `{:array, _}`
  tuples, `%{type: SomeType, constraints: [...]}` shapes) are no longer
  accepted; resolve via `AshApiSpec.Generator.TypeResolver.resolve/2` first.

  Handles `allow_nil?` for string types: non-nullable strings get
  `format_string(constraints, true)` (which adds an effective min-length 1
  when no explicit `:min_length` is set). Nested string fields inside typed
  containers do not get this treatment — they're recursed via `map_spec_type/2`.
  """
  def get_type(formatter, type_input, context \\ nil)

  def get_type(formatter, kind, _context) when is_atom(kind) and not is_nil(kind) do
    Map.get(formatter.aggregate_types(), kind, formatter.any_schema())
  end

  def get_type(formatter, %SpecType{} = type_info, _context) do
    map_with_allow_nil(formatter, type_info, true)
  end

  def get_type(formatter, %{type: %SpecType{} = type_info} = attr, _context) do
    allow_nil? = Map.get(attr, :allow_nil?, true)
    map_with_allow_nil(formatter, type_info, allow_nil?)
  end

  defp map_with_allow_nil(formatter, %SpecType{kind: kind} = type_info, allow_nil?)
       when kind in [:string, :ci_string] do
    formatter.format_string(type_info.constraints || [], not allow_nil?)
  end

  defp map_with_allow_nil(formatter, type_info, _allow_nil?) do
    map_spec_type(formatter, type_info)
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
            arguments = filter_public_arguments(action.arguments)

            if arguments != [],
              do: Enum.map(arguments, &process_argument_field(formatter, resource, action, &1)),
              else: []

          :create ->
            accepts = action.accept || []
            arguments = filter_public_arguments(action.arguments)

            if accepts != [] || arguments != [] do
              Enum.map(accepts, &process_accept_field(formatter, resource, &1, action)) ++
                Enum.map(arguments, &process_argument_field(formatter, resource, action, &1))
            else
              []
            end

          action_type when action_type in [:update, :destroy] ->
            arguments = filter_public_arguments(action.arguments)

            if action.accept != [] || arguments != [] do
              Enum.map(action.accept, &process_accept_field(formatter, resource, &1, action)) ++
                Enum.map(arguments, &process_argument_field(formatter, resource, action, &1))
            else
              []
            end

          :action ->
            arguments = filter_public_arguments(action.arguments)

            if arguments != [],
              do: Enum.map(arguments, &process_argument_field(formatter, resource, action, &1)),
              else: []
        end

      field_lines = Enum.map(field_defs, fn {name, type} -> "  #{name}: #{type}," end)
      kw = formatter.library_prefix()

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

  Builds an augmented resource lookup that includes any orphan resources not
  already present in the cached spec — letting callers pass arbitrary embedded
  resources (e.g., test fixtures) without pre-registering them.
  """
  def generate_schemas_for_resources(formatter, resources) do
    if formatter.generate_schemas_enabled?() and resources != [] do
      uniq_resources = Enum.uniq(resources)
      resource_lookup = build_augmented_lookup(uniq_resources)

      schemas =
        uniq_resources
        |> topological_sort(resource_lookup)
        |> Enum.map_join("\n\n", &generate_schema_for_resource(formatter, &1, resource_lookup))

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
  def generate_schema_for_resource(formatter, resource, resource_lookup \\ nil) do
    lookup = resource_lookup || build_augmented_lookup([resource])
    generate_schema_impl(formatter, resource, lookup)
  end

  # Returns the cached resource lookup augmented with any orphan resources
  # in `resources` that aren't already registered.
  defp build_augmented_lookup(resources) do
    current = AshTypescript.resource_lookup()

    Enum.reduce(resources, current, fn r, acc ->
      if Map.has_key?(acc, r) do
        acc
      else
        Map.put(acc, r, AshApiSpec.Generator.ResourceBuilder.build(r, []))
      end
    end)
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

  defp map_typed_container(formatter, %SpecType{} = type_info) do
    fields = SpecType.get_fields(type_info)
    # Prefer `instance_of` (set explicitly for typed structs); fall back to
    # `module` (NewType subtype modules end up here after `resolve_definition`
    # stamps the original module on the resolved type).
    field_name_source = type_info.instance_of || type_info.module

    cond do
      fields != [] ->
        field_name_mappings = field_name_mappings_for(field_name_source)
        build_object_from_fields(formatter, fields, field_name_mappings)

      type_info.kind == :struct and type_info.instance_of != nil and
          Spark.Dsl.is?(type_info.instance_of, Ash.Resource) ->
        map_resource_ref(formatter, type_info.instance_of)

      type_info.kind == :struct and type_info.instance_of != nil ->
        formatter.wrap_object("")

      true ->
        formatter.wrap_record()
    end
  end

  defp map_resource_ref(formatter, resource) do
    resource_name = CodegenHelpers.build_resource_type_name(resource)
    "#{resource_name}#{formatter.schema_suffix()}"
  end

  defp format_enum_values(formatter, values) do
    enum_values =
      values
      |> Enum.sort_by(&to_string/1)
      |> Enum.map_join(", ", &"\"#{to_string(&1)}\"")

    formatter.format_enum(enum_values)
  end

  # ─────────────────────────────────────────────────────────────────
  # Private — object / union builders (spec-typed)
  # ─────────────────────────────────────────────────────────────────

  defp build_object_from_fields(formatter, fields, field_name_mappings) do
    field_schemas =
      Enum.map_join(fields, ", ", fn %{
                                       name: field_name,
                                       type: %SpecType{} = field_type,
                                       allow_nil?: allow_nil
                                     } ->
        schema_type = map_spec_type(formatter, field_type)
        schema_type = maybe_wrap_nullable_optional(formatter, schema_type, allow_nil, allow_nil)

        base_name =
          if field_name_mappings && Keyword.has_key?(field_name_mappings, field_name),
            do: Keyword.get(field_name_mappings, field_name),
            else: field_name

        "#{format_output_field(base_name)}: #{schema_type}"
      end)

    formatter.wrap_object(field_schemas)
  end

  defp map_spec_union(formatter, members) do
    case members do
      [] ->
        formatter.any_schema()

      _ ->
        union_schemas =
          Enum.map_join(members, ", ", fn %{name: name, type: %SpecType{} = type} ->
            formatted_name = format_field(name)
            schema_type = map_spec_type(formatter, type)
            formatter.wrap_object("#{formatted_name}: #{schema_type}")
          end)

        formatter.wrap_union(union_schemas)
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Private — field processing
  # ─────────────────────────────────────────────────────────────────

  defp process_argument_field(formatter, resource, action, arg) do
    nullable = arg.allow_nil?
    omittable = arg.allow_nil? || has_default?(arg)
    formatted_name = format_argument_for_client(resource, action.name, arg.name)
    schema_type = get_type(formatter, arg)
    schema_type = maybe_wrap_nullable_optional(formatter, schema_type, nullable, omittable)
    {formatted_name, schema_type}
  end

  # Compatibility shim: AshApiSpec.Argument exposes `has_default?`, while raw
  # Ash arguments only expose the `:default` value. Treat any explicit default
  # as "has default".
  defp has_default?(%{has_default?: has_default?}), do: has_default?
  defp has_default?(%{default: default}), do: not is_nil(default)
  defp has_default?(_), do: false

  # AshApiSpec arguments are already filtered to public ones; raw Ash arguments
  # carry a `:public?` field that needs filtering.
  defp filter_public_arguments(args) do
    Enum.filter(args, fn arg -> Map.get(arg, :public?, true) end)
  end

  defp process_accept_field(formatter, resource, field_name, action) do
    attr = AshApiSpec.get_field(AshTypescript.resource_lookup(), resource, field_name)

    {nullable, omittable} =
      if action.type in [:update, :destroy] do
        {attr.allow_nil?, field_name not in (action.require_attributes || [])}
      else
        nullable = attr.allow_nil? || field_name in (action.allow_nil_input || [])
        omittable = nullable || attr.has_default?
        {nullable, omittable}
      end

    formatted_name =
      AshTypescript.FieldFormatter.format_field_for_client(
        field_name,
        resource,
        AshTypescript.Rpc.output_field_formatter()
      )

    schema_type = get_type(formatter, attr)
    schema_type = maybe_wrap_nullable_optional(formatter, schema_type, nullable, omittable)
    {formatted_name, schema_type}
  end

  @doc """
  Wraps a schema string with `wrap_nullable` (innermost) and/or `wrap_optional`
  (outermost) based on the two booleans, using the given formatter.
  """
  def maybe_wrap_nullable_optional(formatter, schema, nullable?, omittable?) do
    schema = if nullable?, do: formatter.wrap_nullable(schema), else: schema
    if omittable?, do: formatter.wrap_optional(schema), else: schema
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
    AshTypescript.FieldFormatter.format_field_name(
      field_name,
      AshTypescript.Rpc.output_field_formatter()
    )
  end

  # Returns the keyword list of field-name mappings declared by a NewType /
  # TypedStruct module via `typescript_field_names/0`, or nil if the module
  # doesn't define one.
  defp field_name_mappings_for(nil), do: nil

  defp field_name_mappings_for(module) when is_atom(module) do
    if function_exported?(module, :typescript_field_names, 0) do
      module.typescript_field_names()
    else
      nil
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Private — resource schema generation
  # ─────────────────────────────────────────────────────────────────

  defp generate_schema_impl(formatter, resource, resource_lookup) do
    resource_name = CodegenHelpers.build_resource_type_name(resource)
    schema_name = "#{resource_name}#{formatter.schema_suffix()}"
    kw = formatter.library_prefix()
    api_resource = AshApiSpec.get_resource!(resource_lookup, resource)

    fields =
      api_resource.fields
      |> Map.values()
      |> Enum.filter(&(&1.kind == :attribute))
      |> Enum.map_join("\n", fn attr ->
        formatted_name =
          AshTypescript.FieldFormatter.format_field_for_client(
            attr.name,
            resource,
            AshTypescript.Rpc.output_field_formatter()
          )

        schema_type = get_type(formatter, attr)
        nullable = attr.allow_nil?
        omittable = attr.allow_nil? || attr.has_default?
        schema_type = maybe_wrap_nullable_optional(formatter, schema_type, nullable, omittable)

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

  defp topological_sort(resources, resource_lookup) do
    resource_set = MapSet.new(resources)

    deps_map =
      Map.new(resources, fn resource ->
        {resource, find_resource_dependencies(resource, resource_set, resource_lookup)}
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

  defp find_resource_dependencies(resource, resource_set, resource_lookup) do
    api_resource = AshApiSpec.get_resource!(resource_lookup, resource)

    api_resource.fields
    |> Map.values()
    |> Enum.filter(&(&1.kind == :attribute))
    |> Enum.flat_map(fn attr -> extract_resource_deps_from_spec(attr.type, resource_set) end)
    |> Enum.uniq()
  end

  # Walks a resolved `%AshApiSpec.Type{}` and returns the embedded/instance_of
  # resource modules it depends on (those present in `resource_set`).
  defp extract_resource_deps_from_spec(%SpecType{kind: :array, item_type: item}, resource_set) do
    extract_resource_deps_from_spec(item, resource_set)
  end

  defp extract_resource_deps_from_spec(
         %SpecType{kind: :embedded_resource, resource_module: mod},
         resource_set
       )
       when not is_nil(mod) do
    if MapSet.member?(resource_set, mod), do: [mod], else: []
  end

  defp extract_resource_deps_from_spec(
         %SpecType{kind: :resource, resource_module: mod},
         resource_set
       )
       when not is_nil(mod) do
    if MapSet.member?(resource_set, mod), do: [mod], else: []
  end

  defp extract_resource_deps_from_spec(
         %SpecType{kind: :struct, instance_of: inst},
         resource_set
       )
       when not is_nil(inst) do
    if Spark.Dsl.is?(inst, Ash.Resource) and MapSet.member?(resource_set, inst),
      do: [inst],
      else: []
  end

  defp extract_resource_deps_from_spec(_type, _resource_set), do: []
end
