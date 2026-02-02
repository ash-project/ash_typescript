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
  alias AshTypescript.TypeSystem.Introspection

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
  """
  @spec classify_field(map()) :: field_category()
  def classify_field(field) do
    case field do
      # Relationships
      %rel{}
      when rel in [
             Ash.Resource.Relationships.HasMany,
             Ash.Resource.Relationships.ManyToMany,
             Ash.Resource.Relationships.HasOne,
             Ash.Resource.Relationships.BelongsTo
           ] ->
        :relationship

      # Calculations - check if complex (has arguments or non-simple)
      %Ash.Resource.Calculation{} = calc ->
        if Helpers.is_simple_calculation(calc) do
          classify_by_type(calc)
        else
          :calculation
        end

      # All other fields - classify by type
      field ->
        classify_by_type(field)
    end
  end

  @doc """
  Classifies a field by its type, handling NewType unwrapping and array wrappers.
  """
  @spec classify_by_type(map()) :: field_category()
  def classify_by_type(field) do
    # Unwrap NewTypes first
    {unwrapped_type, unwrapped_constraints} =
      Introspection.unwrap_new_type(field.type, field.constraints || [])

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
      is_atom(base_type) and Introspection.is_embedded_resource?(base_type) ->
        :embedded

      # Typed containers with field constraints (Map, Keyword, Tuple)
      base_type in [Ash.Type.Map, Ash.Type.Keyword, Ash.Type.Tuple] and
          Keyword.has_key?(constraints, :fields) ->
        :typed_map

      # Struct with instance_of pointing to embedded resource
      base_type == Ash.Type.Struct and
        Keyword.has_key?(constraints, :instance_of) and
          Introspection.is_embedded_resource?(constraints[:instance_of]) ->
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
        resources_needing_input_schema \\ []
      ) do
    resources
    |> Enum.map_join(
      "\n\n",
      &generate_all_schemas_for_resource(&1, allowed_resources, resources_needing_input_schema)
    )
  end

  @doc """
  Generates all schemas for a single resource.
  Includes the unified resource schema and optionally an input schema for resources
  that need it (embedded resources or struct argument resources).
  """
  def generate_all_schemas_for_resource(resource, allowed_resources, input_schema_resources \\ []) do
    resource_name = Helpers.build_resource_type_name(resource)
    unified_schema = generate_unified_resource_schema(resource, allowed_resources)

    is_embedded = Introspection.is_embedded_resource?(resource)

    needs_input_schema =
      is_embedded || resource in input_schema_resources

    input_schema =
      if needs_input_schema do
        generate_input_schema(resource)
      else
        ""
      end

    # Generate AttributesOnlySchema for all resources
    # Used by first aggregates and load restrictions (allowed_loads with flat allows)
    attributes_only_schema = generate_attributes_only_schema(resource, allowed_resources)

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
    resource_name = Helpers.build_resource_type_name(resource)

    fields =
      resource
      |> Ash.Resource.Info.fields([:attributes, :aggregates, :calculations])
      |> Enum.filter(& &1.public?)
      |> Enum.map(fn
        %Ash.Resource.Aggregate{} = aggregate ->
          field =
            if aggregate.field do
              related = Ash.Resource.Info.related(resource, aggregate.relationship_path)

              Ash.Resource.Info.attribute(related, aggregate.field) ||
                Ash.Resource.Info.calculation(related, aggregate.field)
            end

          field_type =
            if field do
              field.type
            end

          field_constraints =
            if field do
              Map.get(field, :constraints)
            end

          case Ash.Query.Aggregate.kind_to_type(
                 aggregate.kind,
                 field_type,
                 field_constraints
               ) do
            {:ok, type, constraints} ->
              Map.merge(aggregate, %{type: type, constraints: constraints})

            _other ->
              aggregate
          end

        field ->
          field
      end)

    {complex_fields, primitive_fields} =
      Enum.split_with(fields, fn field ->
        is_complex_attr?(field)
      end)

    complex_fields =
      Enum.concat(
        complex_fields,
        Enum.filter(
          Ash.Resource.Info.public_relationships(resource),
          &(&1.destination in allowed_resources)
        )
      )

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
        type_str = TypeMapper.get_ts_type(field)

        if allow_nil?(field) do
          "  #{formatted_name}: #{type_str} | null;"
        else
          "  #{formatted_name}: #{type_str};"
        end
      end)
      |> Enum.concat(
        Enum.map(complex_fields, fn field ->
          generate_complex_field_definition(resource, field, allowed_resources)
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

  @doc """
  Generates an attributes-only schema for a resource.

  This schema only includes attributes (no calculations, relationships, or aggregates).
  It's used for first aggregates where nested field selection is possible but limited
  to fields that don't require loading.

  For embedded resource attributes, recursively references their AttributesOnlySchema.
  """
  def generate_attributes_only_schema(resource, allowed_resources) do
    resource_name = Helpers.build_resource_type_name(resource)

    attributes =
      resource
      |> Ash.Resource.Info.public_attributes()

    {complex_attrs, primitive_attrs} =
      Enum.split_with(attributes, fn attr ->
        is_complex_attr?(attr)
      end)

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
        type_str = TypeMapper.get_ts_type(field)

        if allow_nil?(field) do
          "  #{formatted_name}: #{type_str} | null;"
        else
          "  #{formatted_name}: #{type_str};"
        end
      end)
      |> Enum.concat(
        Enum.map(complex_attrs, fn attr ->
          generate_attributes_only_complex_field(resource, attr, allowed_resources)
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

  defp generate_attributes_only_complex_field(resource, attr, allowed_resources) do
    formatted_name = format_client_field_name(resource, attr.name)
    category = classify_field(attr)

    case category do
      :embedded ->
        {unwrapped_type, unwrapped_constraints} =
          Introspection.unwrap_new_type(attr.type, attr.constraints || [])

        actual_attr = %{attr | type: unwrapped_type, constraints: unwrapped_constraints}

        if embedded_resource_allowed?(actual_attr, allowed_resources) do
          embedded_resource = get_embedded_resource_from_attr(actual_attr)
          embedded_resource_name = Helpers.build_resource_type_name(embedded_resource)
          is_array = match?({:array, _}, attr.type)

          resource_type =
            if is_array do
              "#{embedded_resource_name}AttributesOnlySchema"
            else
              if allow_nil?(attr) do
                "#{embedded_resource_name}AttributesOnlySchema | null"
              else
                "#{embedded_resource_name}AttributesOnlySchema"
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

      :union ->
        {_unwrapped_type, unwrapped_constraints} =
          Introspection.unwrap_new_type(attr.type, attr.constraints || [])

        union_types = Keyword.get(unwrapped_constraints, :types, [])
        type_str = build_attributes_only_union_type(union_types, allowed_resources)
        is_array = match?({:array, _}, attr.type)

        final_type =
          if is_array do
            inner_content = String.slice(type_str, 1..-2//1)
            "{ __array: true; #{inner_content} }"
          else
            type_str
          end

        if allow_nil?(attr) do
          "  #{formatted_name}: #{final_type} | null;"
        else
          "  #{formatted_name}: #{final_type};"
        end

      _ ->
        type_str = TypeMapper.get_ts_type(attr)

        if allow_nil?(attr) do
          "  #{formatted_name}: #{type_str} | null;"
        else
          "  #{formatted_name}: #{type_str};"
        end
    end
  end

  defp build_attributes_only_union_type(types, allowed_resources) do
    primitive_fields =
      types
      |> Enum.filter(fn {_name, config} ->
        type = Keyword.get(config, :type)
        constraints = Keyword.get(config, :constraints, [])
        TypeMapper.is_primitive_union_member?(type, constraints)
      end)
      |> Enum.map(fn {name, _} -> name end)

    primitive_union = TypeMapper.generate_primitive_fields_union(primitive_fields)

    member_properties =
      types
      |> Enum.map_join("; ", fn {type_name, type_config} ->
        formatted_name =
          AshTypescript.FieldFormatter.format_field_name(
            type_name,
            AshTypescript.Rpc.output_field_formatter()
          )

        member_type = Keyword.get(type_config, :type)
        member_constraints = Keyword.get(type_config, :constraints, [])

        ts_type =
          cond do
            Introspection.is_embedded_resource?(member_type) and member_type in allowed_resources ->
              resource_name = Helpers.build_resource_type_name(member_type)
              "#{resource_name}AttributesOnlySchema"

            is_atom(member_type) and Ash.Resource.Info.resource?(member_type) and
                member_type in allowed_resources ->
              resource_name = Helpers.build_resource_type_name(member_type)
              "#{resource_name}AttributesOnlySchema"

            true ->
              TypeMapper.map_type(member_type, member_constraints, :output)
          end

        "#{formatted_name}?: #{ts_type}"
      end)

    case member_properties do
      "" -> "{ __type: \"Union\"; __primitiveFields: #{primitive_union}; }"
      properties -> "{ __type: \"Union\"; __primitiveFields: #{primitive_union}; #{properties}; }"
    end
  end

  defp allow_nil?(%{include_nil?: include_nil?}) do
    include_nil?
  end

  defp allow_nil?(%{allow_nil?: allow_nil?}) do
    allow_nil?
  end

  defp type_name(%{type: {:array, type}} = attr) do
    case type_name(%{attr | type: type}) do
      nil -> nil
      type_name -> "#{type_name}[]"
    end
  end

  defp type_name(%{type: type}) do
    if function_exported?(type, :typescript_type_name, 0) do
      type.typescript_type_name()
    end
  end

  defp is_complex_attr?(attr) do
    classify_field(attr) != :primitive
  end

  defp generate_complex_field_definition(resource, field, allowed_resources) do
    if type_str = type_name(field) do
      formatted_name = format_client_field_name(resource, field.name)

      if allow_nil?(field) do
        "  #{formatted_name}: #{type_str} | null;"
      else
        "  #{formatted_name}: #{type_str};"
      end
    else
      # Aggregates returning complex types don't support nested field selection in Ash,
      # so we generate a simpler type without __type: "Relationship" metadata
      if is_aggregate?(field) do
        generate_aggregate_complex_field_definition(resource, field, allowed_resources)
      else
        generate_non_aggregate_complex_field_definition(resource, field, allowed_resources)
      end
    end
  end

  defp is_aggregate?(%Ash.Resource.Aggregate{}), do: true
  defp is_aggregate?(_), do: false

  # Aggregates support nested field selection but only for attributes (not calculations/relationships)
  # Use AttributesOnlySchema with __type: "Relationship" metadata to enable field selection
  defp generate_aggregate_complex_field_definition(resource, field, allowed_resources) do
    category = classify_field(field)
    formatted_name = format_client_field_name(resource, field.name)

    case category do
      :embedded ->
        {unwrapped_type, unwrapped_constraints} =
          Introspection.unwrap_new_type(field.type, field.constraints || [])

        actual_field = %{field | type: unwrapped_type, constraints: unwrapped_constraints}

        if embedded_resource_allowed?(actual_field, allowed_resources) do
          embedded_resource = get_embedded_resource_from_attr(actual_field)
          embedded_resource_name = Helpers.build_resource_type_name(embedded_resource)
          is_array = match?({:array, _}, field.type)

          resource_type =
            if is_array do
              "#{embedded_resource_name}AttributesOnlySchema"
            else
              if allow_nil?(field) do
                "#{embedded_resource_name}AttributesOnlySchema | null"
              else
                "#{embedded_resource_name}AttributesOnlySchema"
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

      :union ->
        {_unwrapped_type, unwrapped_constraints} =
          Introspection.unwrap_new_type(field.type, field.constraints || [])

        union_types = Keyword.get(unwrapped_constraints, :types, [])
        type_str = build_attributes_only_union_type(union_types, allowed_resources)
        is_array = match?({:array, _}, field.type)

        final_type =
          if is_array do
            inner_content = String.slice(type_str, 1..-2//1)
            "{ __array: true; #{inner_content} }"
          else
            type_str
          end

        if allow_nil?(field) do
          "  #{formatted_name}: #{final_type} | null;"
        else
          "  #{formatted_name}: #{final_type};"
        end

      _ ->
        type_str = TypeMapper.get_ts_type(field)

        if allow_nil?(field) do
          "  #{formatted_name}: #{type_str} | null;"
        else
          "  #{formatted_name}: #{type_str};"
        end
    end
  end

  defp generate_non_aggregate_complex_field_definition(resource, field, allowed_resources) do
    category = classify_field(field)

    case category do
      :relationship ->
        relationship_field_definition(resource, field)

      :calculation ->
        complex_calculation_definition(resource, field)

      :embedded ->
        {unwrapped_type, unwrapped_constraints} =
          Introspection.unwrap_new_type(field.type, field.constraints || [])

        actual_field = %{field | type: unwrapped_type, constraints: unwrapped_constraints}

        if embedded_resource_allowed?(actual_field, allowed_resources) do
          embedded_field_definition(resource, actual_field)
        else
          nil
        end

      :union ->
        {unwrapped_type, unwrapped_constraints} =
          Introspection.unwrap_new_type(field.type, field.constraints || [])

        actual_field = %{field | type: unwrapped_type, constraints: unwrapped_constraints}
        complex_type_field_definition(resource, actual_field)

      :typed_map ->
        complex_type_field_definition(resource, field)

      :typed_struct ->
        complex_type_field_definition(resource, field)

      :primitive ->
        # Fallback to TypeMapper for primitives that ended up here
        formatted_name = format_client_field_name(resource, field.name)
        type_str = TypeMapper.get_ts_type(field)

        if allow_nil?(field) do
          "  #{formatted_name}: #{type_str} | null;"
        else
          "  #{formatted_name}: #{type_str};"
        end
    end
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

  defp relationship_field_definition(resource, rel) do
    formatted_name = format_client_field_name(resource, rel.name)
    related_resource_name = Helpers.build_resource_type_name(rel.destination)

    resource_type =
      if rel.type in [:has_many, :many_to_many] do
        "#{related_resource_name}ResourceSchema"
      else
        if Map.get(rel, :allow_nil?, true) do
          "#{related_resource_name}ResourceSchema | null"
        else
          "#{related_resource_name}ResourceSchema"
        end
      end

    metadata =
      case rel.type do
        :has_many ->
          "{ __type: \"Relationship\"; __array: true; __resource: #{resource_type}; }"

        :many_to_many ->
          "{ __type: \"Relationship\"; __array: true; __resource: #{resource_type}; }"

        _ ->
          "{ __type: \"Relationship\"; __resource: #{resource_type}; }"
      end

    "  #{formatted_name}: #{metadata};"
  end

  defp embedded_field_definition(resource, attr) do
    formatted_name = format_client_field_name(resource, attr.name)
    embedded_resource = get_embedded_resource_from_attr(attr)
    embedded_resource_name = Helpers.build_resource_type_name(embedded_resource)

    resource_type =
      case attr.type do
        {:array, _} ->
          "#{embedded_resource_name}ResourceSchema"

        _ ->
          if allow_nil?(attr) do
            "#{embedded_resource_name}ResourceSchema | null"
          else
            "#{embedded_resource_name}ResourceSchema"
          end
      end

    metadata =
      case attr.type do
        {:array, _} ->
          "{ __type: \"Relationship\"; __array: true; __resource: #{resource_type}; }"

        _ ->
          "{ __type: \"Relationship\"; __resource: #{resource_type}; }"
      end

    "  #{formatted_name}: #{metadata};"
  end

  defp complex_calculation_definition(resource, calc) do
    formatted_name = format_client_field_name(resource, calc.name)
    return_type = get_calculation_return_type_for_metadata(calc, calc.allow_nil?)

    metadata =
      if Enum.empty?(calc.arguments) do
        "{ __type: \"ComplexCalculation\"; __returnType: #{return_type}; }"
      else
        args_type = generate_calculation_args_type(calc.arguments)

        "{ __type: \"ComplexCalculation\"; __returnType: #{return_type}; __args: #{args_type}; }"
      end

    "  #{formatted_name}: #{metadata};"
  end

  # Unified handler for complex types (Union, TypedMap, TypedStruct)
  # All delegate to TypeMapper.map_type which handles the type-specific generation
  defp complex_type_field_definition(resource, attr) do
    formatted_name = format_client_field_name(resource, attr.name)

    # Extract inner type and constraints, handling array wrapper
    {inner_type, inner_constraints, is_array} =
      case attr.type do
        {:array, inner} -> {inner, attr.constraints[:items] || [], true}
        inner -> {inner, attr.constraints || [], false}
      end

    # Delegate to TypeMapper for the core type generation
    # This handles recursion, field name mappings, and member type mapping automatically
    inner_ts_type = TypeMapper.map_type(inner_type, inner_constraints, :output)

    # Wrap in array metadata if needed
    final_type =
      if is_array do
        # For arrays, inject __array: true at the beginning of the metadata object
        inner_content = String.slice(inner_ts_type, 1..-2//1)
        "{ __array: true; #{inner_content} }"
      else
        inner_ts_type
      end

    if allow_nil?(attr) do
      "  #{formatted_name}: #{final_type} | null;"
    else
      "  #{formatted_name}: #{final_type};"
    end
  end

  defp embedded_resource_allowed?(attr, allowed_resources) do
    embedded_resource = get_embedded_resource_from_attr(attr)
    Enum.member?(allowed_resources, embedded_resource)
  end

  defp get_embedded_resource_from_attr(%{type: type}) when is_atom(type), do: type
  defp get_embedded_resource_from_attr(%{type: {:array, type}}) when is_atom(type), do: type

  defp get_calculation_return_type_for_metadata(calc, allow_nil?) do
    base_type =
      case calc.type do
        Ash.Type.Struct ->
          constraints = calc.constraints || []
          instance_of = Keyword.get(constraints, :instance_of)

          if instance_of && Ash.Resource.Info.resource?(instance_of) do
            resource_name = Helpers.build_resource_type_name(instance_of)
            "#{resource_name}ResourceSchema"
          else
            "any"
          end

        {:array, Ash.Type.Struct} ->
          constraints = calc.constraints || []
          items_constraints = Keyword.get(constraints, :items, [])
          instance_of = Keyword.get(items_constraints, :instance_of)

          if instance_of && Ash.Resource.Info.resource?(instance_of) do
            resource_name = Helpers.build_resource_type_name(instance_of)
            "Array<#{resource_name}ResourceSchema>"
          else
            "any[]"
          end

        _ ->
          TypeMapper.get_ts_type(calc)
      end

    if allow_nil? do
      "#{base_type} | null"
    else
      base_type
    end
  end

  defp generate_calculation_args_type(arguments) do
    if Enum.empty?(arguments) do
      "{}"
    else
      args =
        arguments
        |> Enum.map_join("; ", fn arg ->
          formatted_name =
            AshTypescript.FieldFormatter.format_field_name(
              arg.name,
              AshTypescript.Rpc.output_field_formatter()
            )

          has_default = Map.has_key?(arg, :default)
          base_type = TypeMapper.get_ts_type(arg)

          type_str =
            if arg.allow_nil? do
              "#{base_type} | null"
            else
              base_type
            end

          if has_default do
            "#{formatted_name}?: #{type_str}"
          else
            "#{formatted_name}: #{type_str}"
          end
        end)

      "{ #{args} }"
    end
  end

  @doc """
  Generates an input schema for embedded resources.
  """
  def generate_input_schema(resource) do
    resource_name = Helpers.build_resource_type_name(resource)

    input_fields =
      resource
      |> Ash.Resource.Info.public_attributes()
      |> Enum.map_join("\n", fn attr ->
        formatted_name = format_client_field_name(resource, attr.name)
        base_type = TypeMapper.get_ts_input_type(attr)

        if attr.allow_nil? || attr.default != nil do
          if attr.allow_nil? do
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

  # Helper to format a resource field name for client output
  # Uses field_names DSL mapping if available, otherwise applies formatter
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
end
