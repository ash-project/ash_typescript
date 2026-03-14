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

  alias AshTypescript.Codegen.{Helpers, TypeMapper}

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

  Accepts Ash field structs, `%AshApiSpec.Field{}`, or `%AshApiSpec.Type{}`.
  """
  @spec classify_field(map()) :: field_category()

  # %AshApiSpec.Field{} dispatch — uses pre-resolved %Type{kind}
  def classify_field(%AshApiSpec.Field{kind: :calculation, type: type, arguments: args}) do
    has_args = is_list(args) and args != []

    if has_args do
      :calculation
    else
      classify_by_type(type)
    end
  end

  def classify_field(%AshApiSpec.Field{type: type}) do
    classify_by_type(type)
  end

  @doc """
  Classifies a field by its type, handling NewType unwrapping and array wrappers.

  Accepts Ash field structs or `%AshApiSpec.Type{}`.
  """
  @spec classify_by_type(map() | AshApiSpec.Type.t()) :: field_category()

  # %AshApiSpec.Type{} dispatch — direct kind matching, no unwrapping needed
  def classify_by_type(%AshApiSpec.Type{kind: :array, item_type: item_type}) do
    classify_by_type(item_type)
  end

  def classify_by_type(%AshApiSpec.Type{kind: :union}), do: :union

  def classify_by_type(%AshApiSpec.Type{kind: kind})
      when kind in [:resource, :embedded_resource],
      do: :embedded

  def classify_by_type(%AshApiSpec.Type{kind: kind} = type_info)
      when kind in [:map, :keyword, :tuple] do
    if has_type_fields?(type_info), do: :typed_map, else: :primitive
  end

  def classify_by_type(%AshApiSpec.Type{kind: :struct} = type_info) do
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

  def classify_by_type(%AshApiSpec.Type{}), do: :primitive

  def classify_by_type(field) do
    # Unwrap NewTypes first
    {unwrapped_type, unwrapped_constraints} =
      AshTypescript.TypeSystem.Introspection.unwrap_new_type(field.type, field.constraints || [])

    # Handle array wrapper - get the inner type and constraints
    {base_type, constraints} =
      case unwrapped_type do
        {:array, inner} ->
          inner_constraints = Keyword.get(unwrapped_constraints, :items, [])
          {inner, inner_constraints}

        type ->
          {type, unwrapped_constraints}
      end

    cond do
      # Union types
      base_type == Ash.Type.Union ->
        :union

      # Embedded resources
      is_atom(base_type) and embedded_resource?(base_type) ->
        :embedded

      # Typed containers with field constraints (Map, Keyword, Tuple)
      base_type in [Ash.Type.Map, Ash.Type.Keyword, Ash.Type.Tuple] and
          Keyword.has_key?(constraints, :fields) ->
        :typed_map

      # Struct with instance_of pointing to embedded resource
      base_type == Ash.Type.Struct and
        Keyword.has_key?(constraints, :instance_of) and
          embedded_resource?(constraints[:instance_of]) ->
        :embedded

      # Struct with instance_of pointing to non-embedded resource
      base_type == Ash.Type.Struct and
        Keyword.has_key?(constraints, :instance_of) and
          Spark.Dsl.is?(constraints[:instance_of], Ash.Resource) ->
        :embedded

      # Struct with field constraints (TypedStruct pattern)
      base_type == Ash.Type.Struct and
        Keyword.has_key?(constraints, :fields) and
          Keyword.has_key?(constraints, :instance_of) ->
        :typed_struct

      # Struct with just field constraints (no instance_of)
      base_type == Ash.Type.Struct and Keyword.has_key?(constraints, :fields) ->
        :typed_map

      # Everything else is primitive
      true ->
        :primitive
    end
  end

  @doc """
  Generates all schemas (unified + input) for a list of resources.

  ## Parameters

    * `resources` - List of resources to generate schemas for
    * `allowed_resources` - List of resources allowed for schema generation (used for filtering)
    * `resources_needing_input_schema` - Optional list of resources that need InputSchema generated
      (defaults to embedded resources)
  """
  def generate_all_schemas_for_resources(
        resources,
        allowed_resources,
        resources_needing_input_schema \\ [],
        resource_lookup \\ nil
      ) do
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

  @doc """
  Generates all schemas for a single resource.
  Includes the unified resource schema and optionally an input schema for resources
  that need it (embedded resources or struct argument resources).
  """
  def generate_all_schemas_for_resource(
        resource,
        allowed_resources,
        input_schema_resources \\ [],
        resource_lookup \\ nil
      )

  def generate_all_schemas_for_resource(
        resource,
        allowed_resources,
        input_schema_resources,
        resource_lookup
      )
      when is_map(resource_lookup) and map_size(resource_lookup) > 0 do
    case Map.get(resource_lookup, resource) do
      %AshApiSpec.Resource{} = api_resource ->
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

  def generate_all_schemas_for_resource(resource, allowed_resources, input_schema_resources, _) do
    # Convenience fallback: build spec internally
    resource_lookup = build_resource_lookup()

    case Map.get(resource_lookup, resource) do
      %AshApiSpec.Resource{} = api_resource ->
        generate_all_schemas_for_resource_from_spec(
          resource,
          api_resource,
          allowed_resources,
          input_schema_resources,
          resource_lookup
        )

      nil ->
        raise "ResourceSchemas: resource #{inspect(resource)} not found in resource_lookup (fallback)"
    end
  end

  defp generate_all_schemas_for_resource_from_spec(
         resource,
         api_resource,
         allowed_resources,
         input_schema_resources,
         resource_lookup
       ) do
    resource_name = Helpers.build_resource_type_name(resource)

    unified_schema =
      generate_unified_resource_schema_from_spec(
        resource,
        api_resource,
        allowed_resources,
        resource_lookup
      )

    needs_input_schema = api_resource.embedded? || resource in input_schema_resources

    input_schema =
      if needs_input_schema do
        generate_input_schema_from_spec(resource, api_resource)
      else
        ""
      end

    attributes_only_schema =
      generate_attributes_only_schema_from_spec(
        resource,
        api_resource,
        allowed_resources,
        resource_lookup
      )

    base_schemas = """
    // #{resource_name} Schema
    #{unified_schema}
    """

    [base_schemas, attributes_only_schema, input_schema]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  @doc """
  Generates a unified resource schema with metadata fields and direct field access.
  This replaces the multiple separate schemas with a single, metadata-driven schema.
  """
  def generate_unified_resource_schema(resource, allowed_resources) do
    resource_lookup = build_resource_lookup()

    case Map.get(resource_lookup, resource) do
      %AshApiSpec.Resource{} = api_resource ->
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

  @doc """
  Generates an attributes-only schema for a resource.

  This schema only includes attributes (no calculations, relationships, or aggregates).
  It's used for first aggregates where nested field selection is possible but limited
  to fields that don't require loading.

  For embedded resource attributes, recursively references their AttributesOnlySchema.
  """
  def generate_attributes_only_schema(resource, allowed_resources) do
    resource_lookup = build_resource_lookup()

    case Map.get(resource_lookup, resource) do
      %AshApiSpec.Resource{} = api_resource ->
        generate_attributes_only_schema_from_spec(
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
          formatted = format_client_field_name(resource, field_name)
          "\"#{formatted}\""
        end
      )
    end
  end

  @doc """
  Generates an input schema for embedded resources.
  """
  def generate_input_schema(resource) do
    resource_lookup = build_resource_lookup()

    case Map.get(resource_lookup, resource) do
      %AshApiSpec.Resource{} = api_resource ->
        generate_input_schema_from_spec(resource, api_resource)

      nil ->
        raise "ResourceSchemas: resource #{inspect(resource)} not found in resource_lookup"
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # AshApiSpec fast-path generators
  # ─────────────────────────────────────────────────────────────────

  defp generate_unified_resource_schema_from_spec(
         resource,
         api_resource,
         allowed_resources,
         resource_lookup
       ) do
    resource_name = Helpers.build_resource_type_name(resource)

    # AshApiSpec fields already have resolved types (no aggregate type resolution needed)
    fields = api_resource.fields |> Map.values()

    {complex_fields, primitive_fields} =
      Enum.split_with(fields, &is_complex_attr?/1)

    relationships =
      api_resource.relationships
      |> Map.values()
      |> Enum.filter(&(&1.destination in allowed_resources))

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
        formatted_name = format_client_field_name(resource, field.name)
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

    attributes =
      api_resource.fields
      |> Map.values()
      |> Enum.filter(&(&1.kind == :attribute))

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
        formatted_name = format_client_field_name(resource, field.name)
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
    resource_name = Helpers.build_resource_type_name(resource)

    attributes =
      api_resource.fields
      |> Map.values()
      |> Enum.filter(&(&1.kind == :attribute))

    input_fields =
      attributes
      |> Enum.map_join("\n", fn field ->
        formatted_name = format_client_field_name(resource, field.name)
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
    export type #{resource_name}InputSchema = {
    #{input_fields}
    };
    """
  end

  # ── AshApiSpec complex field helpers ──────────────────────────────

  defp spec_complex_field_definition(
         resource,
         %AshApiSpec.Field{} = field,
         allowed_resources,
         resource_lookup
       ) do
    # Check for custom type name first
    if type_str = spec_type_name(field.type) do
      formatted_name = format_client_field_name(resource, field.name)

      if field.allow_nil? do
        "  #{formatted_name}: #{type_str} | null;"
      else
        "  #{formatted_name}: #{type_str};"
      end
    else
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
  end

  defp spec_complex_field_definition(
         resource,
         %AshApiSpec.Relationship{} = rel,
         _allowed_resources,
         _resource_lookup
       ) do
    formatted_name = format_client_field_name(resource, rel.name)
    related_resource_name = Helpers.build_resource_type_name(rel.destination)

    resource_type =
      if rel.type in [:has_many, :many_to_many] do
        "#{related_resource_name}ResourceSchema"
      else
        if rel.allow_nil? do
          "#{related_resource_name}ResourceSchema | null"
        else
          "#{related_resource_name}ResourceSchema"
        end
      end

    metadata =
      if rel.type in [:has_many, :many_to_many] do
        "{ __type: \"Relationship\"; __array: true; __resource: #{resource_type}; }"
      else
        "{ __type: \"Relationship\"; __resource: #{resource_type}; }"
      end

    "  #{formatted_name}: #{metadata};"
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

      :primitive ->
        formatted_name = format_client_field_name(resource, field.name)
        type_str = TypeMapper.map_type(field.type, [], :output)

        if field.allow_nil? do
          "  #{formatted_name}: #{type_str} | null;"
        else
          "  #{formatted_name}: #{type_str};"
        end

      _ ->
        nil
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
        formatted_name = format_client_field_name(resource, field.name)
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
         %AshApiSpec.Field{type: type} = field,
         allowed_resources,
         schema_suffix
       ) do
    formatted_name = format_client_field_name(resource, field.name)

    {inner_type, is_array} =
      case type do
        %AshApiSpec.Type{kind: :array, item_type: item_type} -> {item_type, true}
        _ -> {type, false}
      end

    embedded_resource = inner_type.resource_module || inner_type.module

    if embedded_resource in allowed_resources do
      embedded_resource_name = Helpers.build_resource_type_name(embedded_resource)

      resource_type =
        if is_array do
          "#{embedded_resource_name}#{schema_suffix}"
        else
          if field.allow_nil? do
            "#{embedded_resource_name}#{schema_suffix} | null"
          else
            "#{embedded_resource_name}#{schema_suffix}"
          end
        end

      metadata =
        if is_array do
          "{ __type: \"Relationship\"; __array: true; __resource: #{resource_type}; }"
        else
          "{ __type: \"Relationship\"; __resource: #{resource_type}; }"
        end

      "  #{formatted_name}: #{metadata};"
    else
      nil
    end
  end

  defp spec_typed_field(resource, %AshApiSpec.Field{type: type} = field) do
    formatted_name = format_client_field_name(resource, field.name)

    {inner_type, is_array} =
      case type do
        %AshApiSpec.Type{kind: :array, item_type: item_type} -> {item_type, true}
        _ -> {type, false}
      end

    inner_ts_type = TypeMapper.map_type(inner_type, [], :output)

    final_type =
      if is_array do
        inner_content = String.slice(inner_ts_type, 1..-2//1)
        "{ __array: true; #{inner_content} }"
      else
        inner_ts_type
      end

    if field.allow_nil? do
      "  #{formatted_name}: #{final_type} | null;"
    else
      "  #{formatted_name}: #{final_type};"
    end
  end

  defp spec_calculation_definition(resource, %AshApiSpec.Field{} = field) do
    formatted_name = format_client_field_name(resource, field.name)
    return_type = spec_calculation_return_type(field)

    arguments = field.arguments || []

    metadata =
      if Enum.empty?(arguments) do
        "{ __type: \"ComplexCalculation\"; __returnType: #{return_type}; }"
      else
        args_type = spec_calculation_args_type(arguments)
        "{ __type: \"ComplexCalculation\"; __returnType: #{return_type}; __args: #{args_type}; }"
      end

    "  #{formatted_name}: #{metadata};"
  end

  defp spec_calculation_return_type(%AshApiSpec.Field{type: type, allow_nil?: allow_nil?}) do
    # For resource return types, reference the ResourceSchema directly
    base_type =
      case type do
        %AshApiSpec.Type{kind: kind, resource_module: res_mod}
        when kind in [:resource, :embedded_resource] and not is_nil(res_mod) ->
          "#{Helpers.build_resource_type_name(res_mod)}ResourceSchema"

        %AshApiSpec.Type{
          kind: :array,
          item_type: %AshApiSpec.Type{kind: kind, resource_module: res_mod}
        }
        when kind in [:resource, :embedded_resource] and not is_nil(res_mod) ->
          "Array<#{Helpers.build_resource_type_name(res_mod)}ResourceSchema>"

        _ ->
          TypeMapper.map_type(type, [], :output)
      end

    if allow_nil? do
      "#{base_type} | null"
    else
      base_type
    end
  end

  defp spec_calculation_args_type([]), do: "{}"

  defp spec_calculation_args_type(arguments) do
    args =
      arguments
      |> Enum.map_join("; ", fn arg ->
        formatted_name =
          AshTypescript.FieldFormatter.format_field_name(
            arg.name,
            AshTypescript.Rpc.output_field_formatter()
          )

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
         %AshApiSpec.Field{} = field,
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
        formatted_name = format_client_field_name(resource, field.name)
        type_str = TypeMapper.map_type(field.type, [], :output)

        if field.allow_nil? do
          "  #{formatted_name}: #{type_str} | null;"
        else
          "  #{formatted_name}: #{type_str};"
        end
    end
  end

  # Check if an AshApiSpec type module has a custom typescript_type_name
  defp spec_type_name(%AshApiSpec.Type{kind: :array, item_type: inner}) do
    case spec_type_name(inner) do
      nil -> nil
      name -> "#{name}[]"
    end
  end

  defp spec_type_name(%AshApiSpec.Type{module: module})
       when is_atom(module) and not is_nil(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :typescript_type_name, 0) do
      module.typescript_type_name()
    else
      nil
    end
  end

  defp spec_type_name(_), do: nil

  # ─────────────────────────────────────────────────────────────────

  defp embedded_resource?(module) when is_atom(module) and not is_nil(module) do
    Ash.Resource.Info.resource?(module) and Ash.Resource.Info.embedded?(module)
  end

  defp embedded_resource?(_), do: false

  # Helper to format a resource field name for client output
  # Uses field_names DSL mapping if available, otherwise applies formatter
  defp has_type_fields?(%AshApiSpec.Type{fields: fields})
       when is_list(fields) and fields != [],
       do: true

  defp has_type_fields?(%AshApiSpec.Type{constraints: constraints}) do
    Keyword.has_key?(constraints || [], :fields)
  end

  defp format_client_field_name(nil, field_name) do
    AshTypescript.FieldFormatter.format_field_name(
      field_name,
      AshTypescript.Rpc.output_field_formatter()
    )
  end

  defp format_client_field_name(resource, field_name) do
    AshTypescript.FieldFormatter.format_field_for_client(
      field_name,
      resource,
      AshTypescript.Rpc.output_field_formatter()
    )
  end

  defp build_resource_lookup do
    otp_app = Mix.Project.config()[:app]
    {:ok, api_spec} = AshApiSpec.Generator.generate(otp_app: otp_app)
    AshApiSpec.resource_lookup(api_spec)
  end
end
