# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.ResourceSchemas do
  @moduledoc """
  Generates TypeScript schemas for Ash resources.

  Uses a unified field classification pattern for determining how to generate
  TypeScript definitions. The `classify_field/1` function categorizes fields
  into types like :primitive, :relationship, :embedded, :union, etc.
  """

  alias AshTypescript.Codegen.{ClientNames, Helpers, TypeMapper}
  alias AshTypescript.Manifest.Custom
  alias AshTypescript.Rpc.Codegen.FunctionNames

  # ─────────────────────────────────────────────────────────────────
  # Field Classification
  # ─────────────────────────────────────────────────────────────────

  @typedoc """
  Field categories for schema generation.

  - `:primitive` - Simple types mapped directly to TypeScript
  - `:relationship` - Ash relationships (has_many, belongs_to, etc.)
  - `:embedded` - Embedded resources
  - `:union` - Ash.Type.Union types
  - `:typed_map` - Map/Keyword/Tuple with field constraints
  - `:typed_struct` - Struct with fields and instance_of constraints
  - `:calculation` - Complex calculations with arguments
  """
  @type field_category ::
          :primitive
          | :relationship
          | :embedded
          | :union
          | :typed_map
          | :typed_struct
          | :calculation

  @doc """
  Classifies an Ash field into a category for schema generation.

  Handles relationships, calculations, and attribute types. Returns the field
  category which determines how to generate its TypeScript definition.

  Accepts an `%Ash.Info.Manifest.Field{}`.
  """
  @spec classify_field(map()) :: field_category()

  # %Ash.Info.Manifest.Field{} dispatch — uses pre-resolved %Type{kind}
  def classify_field(%Ash.Info.Manifest.Field{kind: :calculation, type: type, arguments: args}) do
    has_args = is_list(args) and args != []

    if has_args do
      :calculation
    else
      classify_by_type(type)
    end
  end

  def classify_field(%Ash.Info.Manifest.Field{type: type}) do
    classify_by_type(type)
  end

  @doc """
  Classifies a field by its type, handling NewType unwrapping and array wrappers.

  Accepts an `%Ash.Info.Manifest.Type{}`.
  """
  @spec classify_by_type(map() | Ash.Info.Manifest.Type.t()) :: field_category()

  # %Ash.Info.Manifest.Type{} dispatch — direct kind matching, no unwrapping needed
  def classify_by_type(%Ash.Info.Manifest.Type{kind: :type_ref, module: module}) do
    full_type = Ash.Info.Manifest.get_type!(AshTypescript.type_lookup(), module)
    classify_by_type(full_type)
  end

  def classify_by_type(%Ash.Info.Manifest.Type{kind: :array, item_type: item_type}) do
    classify_by_type(item_type)
  end

  def classify_by_type(%Ash.Info.Manifest.Type{kind: :union}), do: :union

  def classify_by_type(%Ash.Info.Manifest.Type{kind: kind})
      when kind in [:resource, :embedded_resource],
      do: :embedded

  def classify_by_type(%Ash.Info.Manifest.Type{kind: kind} = type_info)
      when kind in [:map, :keyword, :tuple] do
    if has_type_fields?(type_info), do: :typed_map, else: :primitive
  end

  def classify_by_type(%Ash.Info.Manifest.Type{kind: :struct} = type_info) do
    cond do
      type_info.resource_module ->
        :embedded

      type_info.instance_of && has_type_fields?(type_info) ->
        :typed_struct

      has_type_fields?(type_info) ->
        :typed_map

      true ->
        :primitive
    end
  end

  def classify_by_type(%Ash.Info.Manifest.Type{}), do: :primitive

  @doc """
  Generates all schemas (unified + input) for a list of resources.

  ## Parameters

    * `resources` - List of resources to generate schemas for
    * `allowed_resources` - List of resources allowed for schema generation (used for filtering)
    * `resources_needing_input_schema` - Optional list of resources that need InputSchema generated
      (default `[]`; embedded resources always get one)
  """
  def generate_all_schemas_for_resources(
        resources,
        allowed_resources,
        resources_needing_input_schema \\ [],
        resource_lookup \\ nil
      ) do
    resource_lookup = resource_lookup || build_resource_lookup()

    resources
    |> Enum.map_join(
      "\n\n",
      &generate_all_schemas_for_resource(
        &1,
        allowed_resources,
        resources_needing_input_schema,
        resource_lookup
      )
    )
  end

  defp generate_all_schemas_for_resource(
         resource,
         allowed_resources,
         input_schema_resources,
         resource_lookup
       ) do
    case Map.get(resource_lookup, resource) do
      %Ash.Info.Manifest.Resource{} = api_resource ->
        generate_all_schemas_for_resource_from_spec(
          resource,
          api_resource,
          allowed_resources,
          input_schema_resources,
          resource_lookup
        )

      nil ->
        raise "ResourceSchemas: resource #{inspect(resource)} not found in resource_lookup"
    end
  end

  defp generate_all_schemas_for_resource_from_spec(
         resource,
         api_resource,
         allowed_resources,
         input_schema_resources,
         resource_lookup
       ) do
    needs_input_schema = api_resource.embedded? || resource in input_schema_resources

    input_schema =
      if needs_input_schema do
        generate_input_schema_from_spec(resource, api_resource)
      else
        ""
      end

    output_schemas =
      if output_schemas?(api_resource) do
        output_schemas_from_spec(resource, api_resource, allowed_resources, resource_lookup)
      else
        []
      end

    header = "// #{Helpers.build_resource_type_name(resource)} Schema"

    case Enum.reject(output_schemas ++ [input_schema], &(&1 == "")) do
      [first | rest] -> Enum.join([header <> "\n" <> first | rest], "\n\n")
      [] -> ""
    end
  end

  # An unexposed domain resource (a struct argument) is only ever sent as input,
  # so nothing references its resource or attributes-only schema. Unexposed
  # embedded resources keep theirs: union members and attributes select into them.
  defp output_schemas?(api_resource),
    do: AshRpc.Manifest.Custom.exposed?(api_resource) or api_resource.embedded? == true

  defp output_schemas_from_spec(resource, api_resource, allowed_resources, resource_lookup) do
    unified_schema =
      generate_unified_resource_schema_from_spec(
        resource,
        api_resource,
        allowed_resources,
        resource_lookup
      )

    attributes_only_schema =
      generate_attributes_only_schema_from_spec(
        resource,
        api_resource,
        allowed_resources,
        resource_lookup
      )

    [unified_schema <> "\n", attributes_only_schema]
  end

  @doc false
  def generate_unified_resource_schema(resource, allowed_resources) do
    resource_lookup = build_resource_lookup()

    case Map.get(resource_lookup, resource) do
      %Ash.Info.Manifest.Resource{} = api_resource ->
        generate_unified_resource_schema_from_spec(
          resource,
          api_resource,
          allowed_resources,
          resource_lookup
        )

      nil ->
        raise "ResourceSchemas: resource #{inspect(resource)} not found in resource_lookup"
    end
  end

  defp is_complex_attr?(attr) do
    classify_field(attr) != :primitive
  end

  defp generate_primitive_fields_union(fields, resource) do
    if Enum.empty?(fields) do
      "never"
    else
      fields
      |> Enum.map_join(
        " | ",
        fn field_name ->
          formatted = ClientNames.resource_field(resource, field_name)
          "\"#{formatted}\""
        end
      )
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Ash.Info.Manifest fast-path generators
  # ─────────────────────────────────────────────────────────────────

  defp generate_unified_resource_schema_from_spec(
         resource,
         api_resource,
         allowed_resources,
         resource_lookup
       ) do
    resource_name = Helpers.build_resource_type_name(resource)

    # Ash.Info.Manifest fields already have resolved types (no aggregate type resolution needed)
    fields = Ash.Info.Manifest.Resource.all_fields(api_resource)

    {complex_fields, primitive_fields} =
      Enum.split_with(fields, &is_complex_attr?/1)

    relationships =
      api_resource
      |> Ash.Info.Manifest.Resource.accessible_relationships(allowed_resources)
      |> Enum.filter(&Helpers.exposed_relationship?(&1, resource_lookup))

    complex_fields = complex_fields ++ relationships

    primitive_fields_union =
      generate_primitive_fields_union(Enum.map(primitive_fields, & &1.name), resource)

    metadata_schema_fields = [
      "  __type: \"Resource\";",
      "  __primitiveFields: #{primitive_fields_union};"
    ]

    all_field_lines =
      primitive_fields
      |> Enum.map(fn field ->
        formatted_name = ClientNames.resource_field(resource, field.name)
        type_str = TypeMapper.map_type(field.type, [], :output)

        if field.allow_nil? do
          "  #{formatted_name}: #{type_str} | null;"
        else
          "  #{formatted_name}: #{type_str};"
        end
      end)
      |> Enum.concat(
        Enum.map(complex_fields, fn field ->
          spec_complex_field_definition(resource, field, allowed_resources, resource_lookup)
        end)
      )
      |> Enum.filter(& &1)
      |> then(&Enum.concat(metadata_schema_fields, &1))
      |> Enum.join("\n")

    """
    export type #{resource_name}ResourceSchema = {
    #{all_field_lines}
    };
    """
  end

  defp generate_attributes_only_schema_from_spec(
         resource,
         api_resource,
         allowed_resources,
         resource_lookup
       ) do
    resource_name = Helpers.build_resource_type_name(resource)

    attributes = Ash.Info.Manifest.Resource.fields_by_kind(api_resource, :attribute)

    {complex_attrs, primitive_attrs} =
      Enum.split_with(attributes, &is_complex_attr?/1)

    primitive_fields_union =
      generate_primitive_fields_union(Enum.map(primitive_attrs, & &1.name), resource)

    metadata_schema_fields = [
      "  __type: \"Resource\";",
      "  __primitiveFields: #{primitive_fields_union};"
    ]

    all_field_lines =
      primitive_attrs
      |> Enum.map(fn field ->
        formatted_name = ClientNames.resource_field(resource, field.name)
        type_str = TypeMapper.map_type(field.type, [], :output)

        if field.allow_nil? do
          "  #{formatted_name}: #{type_str} | null;"
        else
          "  #{formatted_name}: #{type_str};"
        end
      end)
      |> Enum.concat(
        Enum.map(complex_attrs, fn attr ->
          spec_attributes_only_complex_field(resource, attr, allowed_resources, resource_lookup)
        end)
      )
      |> Enum.filter(& &1)
      |> then(&Enum.concat(metadata_schema_fields, &1))
      |> Enum.join("\n")

    """
    export type #{resource_name}AttributesOnlySchema = {
    #{all_field_lines}
    };
    """
  end

  defp generate_input_schema_from_spec(resource, api_resource) do
    attributes = Ash.Info.Manifest.Resource.fields_by_kind(api_resource, :attribute)

    input_fields =
      attributes
      |> Enum.map_join("\n", fn field ->
        formatted_name = ClientNames.resource_field(api_resource, field.name)
        base_type = TypeMapper.map_type(field.type, [], :input)

        if field.allow_nil? || field.has_default? do
          if field.allow_nil? do
            "  #{formatted_name}?: #{base_type} | null;"
          else
            "  #{formatted_name}?: #{base_type};"
          end
        else
          "  #{formatted_name}: #{base_type};"
        end
      end)

    """
    export type #{Helpers.resource_input_type_name(resource)} = {
    #{input_fields}
    };
    """
  end

  # ── Ash.Info.Manifest complex field helpers ──────────────────────────────

  defp spec_complex_field_definition(
         resource,
         %Ash.Info.Manifest.Field{} = field,
         allowed_resources,
         resource_lookup
       ) do
    category = classify_field(field)

    # Aggregates use AttributesOnlySchema for complex types
    if field.kind == :aggregate do
      spec_aggregate_complex_field(
        resource,
        field,
        category,
        allowed_resources,
        resource_lookup
      )
    else
      spec_non_aggregate_complex_field(
        resource,
        field,
        category,
        allowed_resources,
        resource_lookup
      )
    end
  end

  defp spec_complex_field_definition(
         resource,
         %Ash.Info.Manifest.Relationship{} = rel,
         _allowed_resources,
         _resource_lookup
       ) do
    formatted_name = ClientNames.resource_field(resource, rel.name)
    schema = "#{Helpers.build_resource_type_name(rel.destination)}ResourceSchema"

    "  #{formatted_name}: #{relationship_field_type(rel, schema)};"
  end

  @doc false
  # The type of a relationship with `schema` as its destination's schema: a
  # has_many / many_to_many carries the query markers. RestrictedSchema renders
  # its relationship overrides through it.
  def relationship_field_type(%Ash.Info.Manifest.Relationship{} = rel, schema) do
    if rel.type in [:has_many, :many_to_many] do
      markers = relationship_query_markers(rel, Helpers.build_resource_type_name(rel.destination))
      "{ __type: \"Relationship\"; __array: true; __resource: #{schema};#{markers} }"
    else
      resource_type = if rel.allow_nil?, do: "#{schema} | null", else: schema
      "{ __type: \"Relationship\"; __resource: #{resource_type}; }"
    end
  end

  # Capability markers gate which envelope keys the TS types offer. Each is
  # independently omitted when the capability is absent. Embedded attributes
  # reuse __type: "Relationship" through a different code path and never get
  # markers.
  defp relationship_query_markers(rel, related_resource_name) do
    pagination =
      case Custom.relationship_pagination(rel) do
        :none -> ""
        kind -> ~s( __pagination: "#{kind}";)
      end

    filter =
      if rel.filterable? do
        " __filterInput: #{FunctionNames.filter_input_type(related_resource_name)};"
      else
        ""
      end

    sort =
      if rel.sortable? do
        " __sortField: #{related_resource_name}SortField;"
      else
        ""
      end

    pagination <> filter <> sort
  end

  defp spec_non_aggregate_complex_field(
         resource,
         field,
         category,
         allowed_resources,
         _resource_lookup
       ) do
    case category do
      :calculation ->
        spec_calculation_definition(resource, field)

      :embedded ->
        spec_embedded_field(resource, field, allowed_resources, "ResourceSchema")

      cat when cat in [:union, :typed_map, :typed_struct] ->
        spec_typed_field(resource, field)
    end
  end

  # Aggregates use AttributesOnlySchema for embedded types
  defp spec_aggregate_complex_field(
         resource,
         field,
         category,
         allowed_resources,
         _resource_lookup
       ) do
    case category do
      :embedded ->
        spec_embedded_field(resource, field, allowed_resources, "AttributesOnlySchema")

      :union ->
        # For aggregate unions, use the same typed field approach
        spec_typed_field(resource, field)

      _ ->
        formatted_name = ClientNames.resource_field(resource, field.name)
        type_str = TypeMapper.map_type(field.type, [], :output)

        if field.allow_nil? do
          "  #{formatted_name}: #{type_str} | null;"
        else
          "  #{formatted_name}: #{type_str};"
        end
    end
  end

  defp spec_embedded_field(
         resource,
         %Ash.Info.Manifest.Field{type: type} = field,
         allowed_resources,
         schema_suffix
       ) do
    formatted_name = ClientNames.resource_field(resource, field.name)

    inner_type =
      case type do
        %Ash.Info.Manifest.Type{kind: :array, item_type: item_type} -> item_type
        _ -> type
      end

    embedded_resource = inner_type.resource_module || inner_type.module

    if embedded_resource in allowed_resources do
      embedded_resource_name = Helpers.build_resource_type_name(embedded_resource)

      "  #{formatted_name}: #{embedded_field_type(field, "#{embedded_resource_name}#{schema_suffix}")};"
    else
      nil
    end
  end

  @doc false
  # The type of a field holding an embedded resource (or an array of one),
  # with `schema` as the resource's schema. RestrictedSchema renders its
  # overrides through it.
  def embedded_field_type(%Ash.Info.Manifest.Field{} = field, schema) do
    # Nullability lives inside `__resource` for arrays too; InferFieldValue
    # turns it into `Array<...> | null`.
    resource_type = if field.allow_nil?, do: "#{schema} | null", else: schema

    case field.type do
      %Ash.Info.Manifest.Type{kind: :array} ->
        "{ __type: \"Relationship\"; __array: true; __resource: #{resource_type}; }"

      _ ->
        "{ __type: \"Relationship\"; __resource: #{resource_type}; }"
    end
  end

  defp spec_typed_field(resource, %Ash.Info.Manifest.Field{type: type} = field) do
    formatted_name = ClientNames.resource_field(resource, field.name)

    inner_type =
      case type do
        %Ash.Info.Manifest.Type{kind: :array, item_type: item_type} -> item_type
        _ -> type
      end

    "  #{formatted_name}: #{typed_field_type(field, TypeMapper.map_type(inner_type, [], :output))};"
  end

  @doc false
  # The type of a field holding a typed map, struct or union (or an array of
  # one) whose item type is `inner_ts_type`: an array is marked with
  # `__array` inside the object type. RestrictedSchema renders union
  # overrides through it.
  def typed_field_type(%Ash.Info.Manifest.Field{} = field, inner_ts_type) do
    final_type =
      case field.type do
        %Ash.Info.Manifest.Type{kind: :array} ->
          inner_content = String.slice(inner_ts_type, 1..-2//1)
          "{ __array: true; #{inner_content} }"

        _ ->
          inner_ts_type
      end

    if field.allow_nil?, do: "#{final_type} | null", else: final_type
  end

  defp spec_calculation_definition(resource, %Ash.Info.Manifest.Field{} = field) do
    formatted_name = ClientNames.resource_field(resource, field.name)

    "  #{formatted_name}: #{calculation_field_type(resource, field)};"
  end

  @doc false
  # The type of a calculation with arguments (only those are complex
  # calculations). `return_type` replaces the return type its own type maps
  # to (nullability is added here); RestrictedSchema passes a restricted
  # schema.
  def calculation_field_type(resource, %Ash.Info.Manifest.Field{} = field, return_type \\ nil) do
    return_type = spec_calculation_return_type(field, return_type)
    args_type = spec_calculation_args_type(resource, field.name, field.arguments)
    "{ __type: \"ComplexCalculation\"; __returnType: #{return_type}; __args: #{args_type}; }"
  end

  defp spec_calculation_return_type(
         %Ash.Info.Manifest.Field{type: type, allow_nil?: allow_nil?},
         return_type
       ) do
    base_type = return_type || spec_calculation_base_type(type)

    if allow_nil? do
      "#{base_type} | null"
    else
      base_type
    end
  end

  # For resource return types, reference the ResourceSchema directly
  defp spec_calculation_base_type(type) do
    case type do
      %Ash.Info.Manifest.Type{kind: kind, resource_module: res_mod}
      when kind in [:resource, :embedded_resource] and not is_nil(res_mod) ->
        "#{Helpers.build_resource_type_name(res_mod)}ResourceSchema"

      %Ash.Info.Manifest.Type{
        kind: :array,
        item_type: %Ash.Info.Manifest.Type{kind: kind, resource_module: res_mod}
      }
      when kind in [:resource, :embedded_resource] and not is_nil(res_mod) ->
        "Array<#{Helpers.build_resource_type_name(res_mod)}ResourceSchema>"

      _ ->
        TypeMapper.map_type(type, [], :output)
    end
  end

  defp spec_calculation_args_type(resource, calc, arguments) do
    args =
      arguments
      |> Enum.map_join("; ", fn arg ->
        formatted_name = ClientNames.calculation_argument(resource, calc, arg.name)
        base_type = TypeMapper.map_type(arg.type, [], :input)

        type_str =
          if arg.allow_nil? do
            "#{base_type} | null"
          else
            base_type
          end

        if arg.has_default? || arg.allow_nil? do
          "#{formatted_name}?: #{type_str}"
        else
          "#{formatted_name}: #{type_str}"
        end
      end)

    "{ #{args} }"
  end

  defp spec_attributes_only_complex_field(
         resource,
         %Ash.Info.Manifest.Field{} = field,
         allowed_resources,
         _resource_lookup
       ) do
    category = classify_field(field)

    case category do
      :embedded ->
        spec_embedded_field(resource, field, allowed_resources, "AttributesOnlySchema")

      :union ->
        spec_typed_field(resource, field)

      _ ->
        formatted_name = ClientNames.resource_field(resource, field.name)
        type_str = TypeMapper.map_type(field.type, [], :output)

        if field.allow_nil? do
          "  #{formatted_name}: #{type_str} | null;"
        else
          "  #{formatted_name}: #{type_str};"
        end
    end
  end

  # ─────────────────────────────────────────────────────────────────

  defp has_type_fields?(%Ash.Info.Manifest.Type{fields: fields})
       when is_list(fields) and fields != [],
       do: true

  defp has_type_fields?(%Ash.Info.Manifest.Type{constraints: constraints}) do
    Keyword.has_key?(constraints || [], :fields)
  end

  defp build_resource_lookup do
    AshTypescript.resource_lookup()
  end
end
