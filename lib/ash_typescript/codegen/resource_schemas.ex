# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.ResourceSchemas do
  @moduledoc """
  Generates TypeScript schemas for Ash resources.
  Includes both output schemas (ResourceSchema) and input schemas (InputSchema).
  """

  alias AshTypescript.Codegen.{Helpers, TypeMapper}
  alias AshTypescript.TypeSystem.Introspection

  @doc """
  Generates all schemas (unified + input) for a list of resources.
  """
  def generate_all_schemas_for_resources(resources, allowed_resources) do
    resources
    |> Enum.map_join("\n\n", &generate_all_schemas_for_resource(&1, allowed_resources))
  end

  @doc """
  Generates all schemas for a single resource.
  Includes the unified resource schema and optionally an input schema for embedded resources.
  """
  def generate_all_schemas_for_resource(resource, allowed_resources) do
    resource_name = Helpers.build_resource_type_name(resource)
    unified_schema = generate_unified_resource_schema(resource, allowed_resources)

    input_schema =
      if Introspection.is_embedded_resource?(resource) do
        generate_input_schema(resource)
      else
        ""
      end

    base_schemas = """
    // #{resource_name} Schema
    #{unified_schema}
    """

    [base_schemas, input_schema]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  @doc """
  Generates a unified resource schema with metadata fields and direct field access.
  This replaces the multiple separate schemas with a single, metadata-driven schema.
  """
  def generate_unified_resource_schema(resource, allowed_resources) do
    resource_name = Helpers.build_resource_type_name(resource)

    primitive_fields = get_primitive_fields(resource)

    primitive_fields_union = generate_primitive_fields_union(primitive_fields, resource)

    metadata_schema_fields = [
      "  __type: \"Resource\";",
      "  __primitiveFields: #{primitive_fields_union};"
    ]

    primitive_field_defs = generate_primitive_field_definitions(resource)

    relationship_field_defs = generate_relationship_field_definitions(resource, allowed_resources)
    embedded_field_defs = generate_embedded_field_definitions(resource, allowed_resources)
    complex_calc_field_defs = generate_complex_calculation_field_definitions(resource)
    union_field_defs = generate_union_field_definitions(resource)
    keyword_tuple_field_defs = generate_keyword_tuple_field_definitions(resource)

    all_field_lines =
      metadata_schema_fields ++
        primitive_field_defs ++
        relationship_field_defs ++
        embedded_field_defs ++
        complex_calc_field_defs ++
        union_field_defs ++
        keyword_tuple_field_defs

    """
    export type #{resource_name}ResourceSchema = {
    #{Enum.join(all_field_lines, "\n")}
    };
    """
  end

  defp get_primitive_fields(resource) do
    attributes = Ash.Resource.Info.public_attributes(resource)
    calculations = Ash.Resource.Info.public_calculations(resource)
    aggregates = Ash.Resource.Info.public_aggregates(resource)

    primitive_attrs =
      attributes
      |> Enum.reject(fn attr ->
        is_union_attribute?(attr) or
          is_embedded_attribute?(attr) or
          is_typed_struct_attribute?(attr) or
          is_keyword_attribute?(attr) or
          is_tuple_attribute?(attr)
      end)
      |> Enum.map(& &1.name)

    simple_calcs =
      calculations
      |> Enum.filter(&Helpers.is_simple_calculation/1)
      |> Enum.map(& &1.name)

    aggregate_names = Enum.map(aggregates, & &1.name)
    primitive_attrs ++ simple_calcs ++ aggregate_names
  end

  defp get_union_primitive_fields(union_types) do
    union_types
    |> Enum.filter(fn {_name, config} ->
      type = Keyword.get(config, :type)

      case type do
        Ash.Type.Map ->
          false

        Ash.Type.Keyword ->
          false

        Ash.Type.Struct ->
          false

        Ash.Type.Union ->
          false

        atom_type when is_atom(atom_type) ->
          not Introspection.is_embedded_resource?(atom_type) and
            not Introspection.is_typed_struct?(atom_type)

        _ ->
          false
      end
    end)
    |> Enum.map(fn {name, _config} -> name end)
  end

  defp generate_primitive_fields_union(fields, resource \\ nil) do
    if Enum.empty?(fields) do
      "never"
    else
      fields
      |> Enum.map_join(
        " | ",
        fn field_name ->
          # Apply field name mapping if resource is provided
          mapped_name =
            if resource do
              AshTypescript.Resource.Info.get_mapped_field_name(resource, field_name)
            else
              field_name
            end

          formatted =
            AshTypescript.FieldFormatter.format_field(
              mapped_name,
              AshTypescript.Rpc.output_field_formatter()
            )

          "\"#{formatted}\""
        end
      )
    end
  end

  defp generate_primitive_field_definitions(resource) do
    attributes = Ash.Resource.Info.public_attributes(resource)
    calculations = Ash.Resource.Info.public_calculations(resource)
    aggregates = Ash.Resource.Info.public_aggregates(resource)

    primitive_attrs =
      attributes
      |> Enum.reject(fn attr ->
        is_union_attribute?(attr) or
          is_embedded_attribute?(attr) or
          is_typed_struct_attribute?(attr) or
          is_keyword_attribute?(attr) or
          is_tuple_attribute?(attr)
      end)

    simple_calcs =
      calculations
      |> Enum.filter(&Helpers.is_simple_calculation/1)

    attr_defs =
      Enum.map(primitive_attrs, fn attr ->
        mapped_name = AshTypescript.Resource.Info.get_mapped_field_name(resource, attr.name)

        formatted_name =
          AshTypescript.FieldFormatter.format_field(
            mapped_name,
            AshTypescript.Rpc.output_field_formatter()
          )

        type_str = TypeMapper.get_ts_type(attr)

        if attr.allow_nil? do
          "  #{formatted_name}: #{type_str} | null;"
        else
          "  #{formatted_name}: #{type_str};"
        end
      end)

    calc_defs =
      Enum.map(simple_calcs, fn calc ->
        mapped_name = AshTypescript.Resource.Info.get_mapped_field_name(resource, calc.name)

        formatted_name =
          AshTypescript.FieldFormatter.format_field(
            mapped_name,
            AshTypescript.Rpc.output_field_formatter()
          )

        type_str = TypeMapper.get_ts_type(calc)

        if calc.allow_nil? do
          "  #{formatted_name}: #{type_str} | null;"
        else
          "  #{formatted_name}: #{type_str};"
        end
      end)

    agg_defs =
      Enum.map(aggregates, fn agg ->
        mapped_name = AshTypescript.Resource.Info.get_mapped_field_name(resource, agg.name)

        formatted_name =
          AshTypescript.FieldFormatter.format_field(
            mapped_name,
            AshTypescript.Rpc.output_field_formatter()
          )

        type_str =
          case agg.kind do
            :sum ->
              resource
              |> Helpers.lookup_aggregate_type(agg.relationship_path, agg.field)
              |> TypeMapper.get_ts_type()

            :first ->
              resource
              |> Helpers.lookup_aggregate_type(agg.relationship_path, agg.field)
              |> TypeMapper.get_ts_type()

            _ ->
              TypeMapper.get_ts_type(agg.kind)
          end

        if agg.include_nil? do
          "  #{formatted_name}?: #{type_str} | null;"
        else
          "  #{formatted_name}: #{type_str};"
        end
      end)

    attr_defs ++ calc_defs ++ agg_defs
  end

  defp generate_relationship_field_definitions(resource, allowed_resources) do
    relationships = Ash.Resource.Info.public_relationships(resource)

    relationships
    |> Enum.filter(fn rel ->
      Enum.member?(allowed_resources, rel.destination)
    end)
    |> Enum.map(fn rel ->
      mapped_name = AshTypescript.Resource.Info.get_mapped_field_name(resource, rel.name)

      formatted_name =
        AshTypescript.FieldFormatter.format_field(
          mapped_name,
          AshTypescript.Rpc.output_field_formatter()
        )

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
    end)
  end

  defp generate_embedded_field_definitions(resource, allowed_resources) do
    attributes = Ash.Resource.Info.public_attributes(resource)

    attributes
    |> Enum.filter(fn attr ->
      is_embedded_attribute?(attr) and
        embedded_resource_allowed?(attr, allowed_resources)
    end)
    |> Enum.map(fn attr ->
      mapped_name = AshTypescript.Resource.Info.get_mapped_field_name(resource, attr.name)

      formatted_name =
        AshTypescript.FieldFormatter.format_field(
          mapped_name,
          AshTypescript.Rpc.output_field_formatter()
        )

      embedded_resource = get_embedded_resource_from_attr(attr)
      embedded_resource_name = Helpers.build_resource_type_name(embedded_resource)

      resource_type =
        case attr.type do
          {:array, _} ->
            "#{embedded_resource_name}ResourceSchema"

          _ ->
            if attr.allow_nil? do
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
    end)
  end

  defp generate_complex_calculation_field_definitions(resource) do
    calculations = Ash.Resource.Info.public_calculations(resource)

    calculations
    |> Enum.reject(&Helpers.is_simple_calculation/1)
    |> Enum.map(fn calc ->
      mapped_name = AshTypescript.Resource.Info.get_mapped_field_name(resource, calc.name)

      formatted_name =
        AshTypescript.FieldFormatter.format_field(
          mapped_name,
          AshTypescript.Rpc.output_field_formatter()
        )

      return_type = get_calculation_return_type_for_metadata(calc, calc.allow_nil?)

      metadata =
        if Enum.empty?(calc.arguments) do
          "{ __type: \"ComplexCalculation\"; __returnType: #{return_type}; }"
        else
          args_type = generate_calculation_args_type(calc.arguments)

          "{ __type: \"ComplexCalculation\"; __returnType: #{return_type}; __args: #{args_type}; }"
        end

      "  #{formatted_name}: #{metadata};"
    end)
  end

  defp generate_union_field_definitions(resource) do
    attributes = Ash.Resource.Info.public_attributes(resource)

    attributes
    |> Enum.filter(&is_union_attribute?/1)
    |> Enum.map(fn attr ->
      mapped_name = AshTypescript.Resource.Info.get_mapped_field_name(resource, attr.name)

      formatted_name =
        AshTypescript.FieldFormatter.format_field(
          mapped_name,
          AshTypescript.Rpc.output_field_formatter()
        )

      union_metadata = generate_union_metadata(attr)

      # Check if this is an array union and add __array: true
      final_type =
        case attr.type do
          {:array, Ash.Type.Union} ->
            # Extract the content of the union metadata and add __array: true
            # Remove outer braces
            union_content = String.slice(union_metadata, 1..-2//1)
            "{ __array: true; #{union_content} }"

          _ ->
            union_metadata
        end

      if attr.allow_nil? do
        "  #{formatted_name}: #{final_type} | null;"
      else
        "  #{formatted_name}: #{final_type};"
      end
    end)
  end

  defp generate_keyword_tuple_field_definitions(resource) do
    attributes = Ash.Resource.Info.public_attributes(resource)

    attributes
    |> Enum.filter(fn attr ->
      is_keyword_attribute?(attr) or is_tuple_attribute?(attr)
    end)
    |> Enum.map(fn attr ->
      mapped_name = AshTypescript.Resource.Info.get_mapped_field_name(resource, attr.name)

      formatted_name =
        AshTypescript.FieldFormatter.format_field(
          mapped_name,
          AshTypescript.Rpc.output_field_formatter()
        )

      ts_type = TypeMapper.get_ts_type(attr, nil)

      if attr.allow_nil? do
        "  #{formatted_name}: #{ts_type} | null;"
      else
        "  #{formatted_name}: #{ts_type};"
      end
    end)
  end

  defp is_union_attribute?(%{type: Ash.Type.Union}), do: true
  defp is_union_attribute?(%{type: {:array, Ash.Type.Union}}), do: true
  defp is_union_attribute?(_), do: false

  defp is_embedded_attribute?(%{type: type}) when is_atom(type),
    do: Introspection.is_embedded_resource?(type)

  defp is_embedded_attribute?(%{type: {:array, type}}) when is_atom(type),
    do: Introspection.is_embedded_resource?(type)

  defp is_embedded_attribute?(_), do: false

  defp is_typed_struct_attribute?(%{type: type}) when is_atom(type),
    do: Introspection.is_typed_struct?(type)

  defp is_typed_struct_attribute?(%{type: {:array, type}}) when is_atom(type),
    do: Introspection.is_typed_struct?(type)

  defp is_typed_struct_attribute?(_), do: false

  defp is_keyword_attribute?(%{type: Ash.Type.Keyword}), do: true
  defp is_keyword_attribute?(%{type: {:array, Ash.Type.Keyword}}), do: true
  defp is_keyword_attribute?(_), do: false

  defp is_tuple_attribute?(%{type: Ash.Type.Tuple}), do: true
  defp is_tuple_attribute?(%{type: {:array, Ash.Type.Tuple}}), do: true
  defp is_tuple_attribute?(_), do: false

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
            AshTypescript.FieldFormatter.format_field(
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

  defp generate_union_metadata(attr) do
    constraints = attr.constraints || []

    union_types =
      case attr.type do
        {:array, Ash.Type.Union} ->
          items_constraints = Keyword.get(constraints, :items, [])
          Keyword.get(items_constraints, :types, [])

        Ash.Type.Union ->
          Keyword.get(constraints, :types, [])

        _ ->
          []
      end

    primitive_fields = get_union_primitive_fields(union_types)
    primitive_union = generate_primitive_fields_union(primitive_fields)

    member_fields =
      union_types
      |> Enum.map_join("; ", fn {name, config} ->
        formatted_name =
          AshTypescript.FieldFormatter.format_field(
            name,
            AshTypescript.Rpc.output_field_formatter()
          )

        type = Keyword.get(config, :type)
        constraints = Keyword.get(config, :constraints, [])

        cond do
          Introspection.is_embedded_resource?(type) ->
            resource_name = Helpers.build_resource_type_name(type)
            "#{formatted_name}?: #{resource_name}ResourceSchema"

          Introspection.is_typed_struct?(type) ->
            "#{formatted_name}?: any"

          true ->
            ts_type = TypeMapper.get_ts_type(%{type: type, constraints: constraints})
            "#{formatted_name}?: #{ts_type}"
        end
      end)

    if member_fields == "" do
      "{ __type: \"Union\"; __primitiveFields: #{primitive_union}; }"
    else
      "{ __type: \"Union\"; __primitiveFields: #{primitive_union}; #{member_fields}; }"
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
        # Apply field name mapping before formatting
        mapped_name = AshTypescript.Resource.Info.get_mapped_field_name(resource, attr.name)

        formatted_name =
          AshTypescript.FieldFormatter.format_field(
            mapped_name,
            AshTypescript.Rpc.output_field_formatter()
          )

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
end
