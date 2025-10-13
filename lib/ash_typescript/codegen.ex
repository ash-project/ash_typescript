# SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen do
  @moduledoc """
  Main code generation module for TypeScript types and schemas from Ash resources.
  """
  @doc """
  Discovers embedded resources from a list of regular resources by scanning their attributes.
  Returns a list of unique embedded resource modules.
  """
  def find_embedded_resources(resources) do
    resources
    |> Enum.flat_map(&extract_embedded_from_resource/1)
    |> Enum.uniq()
  end

  @doc """
  Discovers all TypedStruct modules referenced by the given resources.
  Similar to find_embedded_resources but for TypedStruct modules.
  """
  def find_typed_struct_modules(resources) do
    resources
    |> Enum.flat_map(&extract_typed_structs_from_resource/1)
    |> Enum.uniq()
  end

  defp extract_embedded_from_resource(resource) do
    resource
    |> Ash.Resource.Info.public_attributes()
    |> Enum.filter(&is_embedded_resource_attribute?/1)
    |> Enum.flat_map(&extract_embedded_modules/1)
    |> Enum.filter(& &1)
  end

  defp extract_typed_structs_from_resource(resource) do
    resource
    |> Ash.Resource.Info.public_attributes()
    |> Enum.filter(&is_typed_struct_attribute?/1)
    |> Enum.flat_map(&extract_typed_struct_modules/1)
    |> Enum.filter(& &1)
  end

  defp is_embedded_resource_attribute?(%Ash.Resource.Attribute{
         type: type,
         constraints: constraints
       }) do
    case type do
      Ash.Type.Union ->
        union_types = Keyword.get(constraints, :types, [])

        Enum.any?(union_types, fn {_type_name, type_config} ->
          type = Keyword.get(type_config, :type)
          type && is_embedded_resource?(type)
        end)

      {:array, Ash.Type.Union} ->
        items_constraints = Keyword.get(constraints, :items, [])
        union_types = Keyword.get(items_constraints, :types, [])

        Enum.any?(union_types, fn {_type_name, type_config} ->
          type = Keyword.get(type_config, :type)
          type && is_embedded_resource?(type)
        end)

      Ash.Type.Struct ->
        instance_of = Keyword.get(constraints, :instance_of)
        instance_of && is_embedded_resource?(instance_of)

      {:array, Ash.Type.Struct} ->
        items_constraints = Keyword.get(constraints, :items, [])
        instance_of = Keyword.get(items_constraints, :instance_of)
        instance_of && is_embedded_resource?(instance_of)

      module when is_atom(module) ->
        is_embedded_resource?(module)

      {:array, module} when is_atom(module) ->
        is_embedded_resource?(module)

      _ ->
        false
    end
  end

  defp is_embedded_resource_attribute?(_), do: false

  defp is_typed_struct_attribute?(%Ash.Resource.Attribute{
         type: type,
         constraints: constraints
       }) do
    case type do
      Ash.Type.Union ->
        union_types = Keyword.get(constraints, :types, [])

        Enum.any?(union_types, fn {_type_name, type_config} ->
          type = Keyword.get(type_config, :type)
          type && is_typed_struct?(type)
        end)

      {:array, Ash.Type.Union} ->
        items_constraints = Keyword.get(constraints, :items, [])
        union_types = Keyword.get(items_constraints, :types, [])

        Enum.any?(union_types, fn {_type_name, type_config} ->
          type = Keyword.get(type_config, :type)
          type && is_typed_struct?(type)
        end)

      module when is_atom(module) ->
        is_typed_struct?(module)

      {:array, module} when is_atom(module) ->
        is_typed_struct?(module)

      _ ->
        false
    end
  end

  defp is_typed_struct_attribute?(_), do: false

  defp extract_typed_struct_modules(%Ash.Resource.Attribute{type: type, constraints: constraints}) do
    case type do
      Ash.Type.Union ->
        union_types = Keyword.get(constraints, :types, [])

        Enum.flat_map(union_types, fn {_type_name, type_config} ->
          type = Keyword.get(type_config, :type)
          if type && is_typed_struct?(type), do: [type], else: []
        end)

      {:array, Ash.Type.Union} ->
        items_constraints = Keyword.get(constraints, :items, [])
        union_types = Keyword.get(items_constraints, :types, [])

        Enum.flat_map(union_types, fn {_type_name, type_config} ->
          type = Keyword.get(type_config, :type)
          if type && is_typed_struct?(type), do: [type], else: []
        end)

      module when is_atom(module) ->
        if is_typed_struct?(module), do: [module], else: []

      {:array, module} when is_atom(module) ->
        if is_typed_struct?(module), do: [module], else: []

      _ ->
        []
    end
  end

  defp extract_embedded_modules(%Ash.Resource.Attribute{type: type, constraints: constraints}) do
    case type do
      Ash.Type.Union ->
        union_types = Keyword.get(constraints, :types, [])

        Enum.flat_map(union_types, fn {_type_name, type_config} ->
          type = Keyword.get(type_config, :type)
          if type && is_embedded_resource?(type), do: [type], else: []
        end)

      {:array, Ash.Type.Union} ->
        items_constraints = Keyword.get(constraints, :items, [])
        union_types = Keyword.get(items_constraints, :types, [])

        Enum.flat_map(union_types, fn {_type_name, type_config} ->
          type = Keyword.get(type_config, :type)
          if type && is_embedded_resource?(type), do: [type], else: []
        end)

      Ash.Type.Struct ->
        module = Keyword.get(constraints, :instance_of)
        if module && is_embedded_resource?(module), do: [module], else: []

      {:array, Ash.Type.Struct} ->
        items_constraints = Keyword.get(constraints, :items, [])
        module = Keyword.get(items_constraints, :instance_of)
        if module && is_embedded_resource?(module), do: [module], else: []

      module when is_atom(module) ->
        if is_embedded_resource?(module), do: [module], else: []

      {:array, module} when is_atom(module) ->
        if is_embedded_resource?(module), do: [module], else: []

      _ ->
        []
    end
  end

  defp extract_embedded_modules(_), do: []

  @doc """
  Checks if a module is an embedded resource.
  """
  def is_embedded_resource?(module) when is_atom(module) do
    Ash.Resource.Info.resource?(module) and Ash.Resource.Info.embedded?(module)
  end

  def is_embedded_resource?(_), do: false

  def generate_ash_type_aliases(resources, actions) do
    embedded_resources = find_embedded_resources(resources)
    all_resources = resources ++ embedded_resources

    resource_types =
      Enum.reduce(all_resources, MapSet.new(), fn resource, types ->
        types =
          resource
          |> Ash.Resource.Info.public_attributes()
          |> Enum.reduce(types, fn attr, types -> MapSet.put(types, attr.type) end)

        types =
          resource
          |> Ash.Resource.Info.public_calculations()
          |> Enum.reduce(types, fn calc, types -> MapSet.put(types, calc.type) end)

        resource
        |> Ash.Resource.Info.public_aggregates()
        |> Enum.reduce(types, fn agg, types ->
          type =
            case agg.kind do
              :sum ->
                resource
                |> lookup_aggregate_type(agg.relationship_path, agg.field)

              :first ->
                resource
                |> lookup_aggregate_type(agg.relationship_path, agg.field)

              _ ->
                agg.kind
            end

          if Ash.Type.ash_type?(type) do
            MapSet.put(types, type)
          else
            types
          end
        end)
      end)

    types =
      Enum.reduce(actions, resource_types, fn action, types ->
        types =
          action.arguments
          |> Enum.reduce(types, fn argument, types ->
            if Ash.Type.ash_type?(argument.type) do
              MapSet.put(types, argument.type)
            else
              types
            end
          end)

        if action.type == :action do
          if Ash.Type.ash_type?(action.returns) do
            case action.returns do
              {:array, type} -> MapSet.put(types, type)
              _ -> MapSet.put(types, action.returns)
            end
          else
            types
          end
        else
          types
        end
      end)

    types
    |> Enum.map(fn type ->
      case type do
        {:array, type} -> type
        type -> type
      end
    end)
    |> Enum.uniq()
    |> Enum.map(&generate_ash_type_alias/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp generate_ash_type_alias(Ash.Type.Struct), do: ""
  defp generate_ash_type_alias(Ash.Type.Union), do: ""
  defp generate_ash_type_alias(Ash.Type.Atom), do: ""
  defp generate_ash_type_alias(Ash.Type.Boolean), do: ""
  defp generate_ash_type_alias(Ash.Type.Integer), do: ""
  defp generate_ash_type_alias(Ash.Type.Float), do: ""
  defp generate_ash_type_alias(Ash.Type.Map), do: ""
  defp generate_ash_type_alias(Ash.Type.Keyword), do: ""
  defp generate_ash_type_alias(Ash.Type.Tuple), do: ""
  defp generate_ash_type_alias(Ash.Type.String), do: ""
  defp generate_ash_type_alias(Ash.Type.CiString), do: ""
  defp generate_ash_type_alias(Ash.Type.UUID), do: "export type UUID = string;"
  defp generate_ash_type_alias(Ash.Type.UUIDv7), do: "export type UUIDv7 = string;"
  defp generate_ash_type_alias(Ash.Type.Decimal), do: "export type Decimal = string;"
  defp generate_ash_type_alias(Ash.Type.Date), do: "export type AshDate = string;"
  defp generate_ash_type_alias(Ash.Type.Time), do: "export type Time = string;"
  defp generate_ash_type_alias(Ash.Type.TimeUsec), do: "export type TimeUsec = string;"
  defp generate_ash_type_alias(Ash.Type.UtcDatetime), do: "export type UtcDateTime = string;"

  defp generate_ash_type_alias(Ash.Type.UtcDatetimeUsec),
    do: "export type UtcDateTimeUsec = string;"

  defp generate_ash_type_alias(Ash.Type.DateTime), do: "export type DateTime = string;"
  defp generate_ash_type_alias(Ash.Type.NaiveDatetime), do: "export type NaiveDateTime = string;"
  defp generate_ash_type_alias(Ash.Type.Duration), do: "export type Duration = string;"
  defp generate_ash_type_alias(Ash.Type.DurationName), do: "export type DurationName = string;"
  defp generate_ash_type_alias(Ash.Type.Binary), do: "export type Binary = string;"

  defp generate_ash_type_alias(Ash.Type.UrlEncodedBinary),
    do: "export type UrlEncodedBinary = string;"

  defp generate_ash_type_alias(Ash.Type.File), do: "export type File = any;"
  defp generate_ash_type_alias(Ash.Type.Function), do: "export type Function = any;"
  defp generate_ash_type_alias(Ash.Type.Module), do: "export type ModuleName = string;"
  defp generate_ash_type_alias(AshDoubleEntry.ULID), do: "export type ULID = string;"

  defp generate_ash_type_alias(AshPostgres.Ltree),
    do:
      "export type AshPostgresLtreeFlexible = string | string[];\nexport type AshPostgresLtreeArray = string[];"

  defp generate_ash_type_alias(AshMoney.Types.Money),
    do: "export type Money = { amount: string; currency: string };"

  defp generate_ash_type_alias(type) do
    cond do
      is_custom_type?(type) ->
        ""

      Ash.Type.NewType.new_type?(type) or Spark.implements_behaviour?(type, Ash.Type.Enum) ->
        ""

      is_embedded_resource?(type) ->
        ""

      true ->
        raise "Unknown type: #{type}"
    end
  end

  defp is_custom_type?(type) do
    is_atom(type) and
      Code.ensure_loaded?(type) and
      function_exported?(type, :typescript_type_name, 0) and
      Spark.implements_behaviour?(type, Ash.Type)
  end

  @doc """
  Checks if a type is a TypedStruct using simplified Spark DSL detection.
  """
  def is_typed_struct?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and
      function_exported?(module, :spark_is, 0) and
      is_ash_typed_struct?(module)
  end

  def is_typed_struct?(_), do: false

  defp is_ash_typed_struct?(module) do
    module.spark_is() == Ash.TypedStruct
  rescue
    _ -> false
  end

  @doc """
  Gets the field information from a TypedStruct module using Ash's DSL pattern.
  Returns a list of field definitions.
  """
  def get_typed_struct_fields(module) do
    if is_typed_struct?(module) do
      Spark.Dsl.Extension.get_entities(module, [:typed_struct])
    else
      []
    end
  rescue
    _ -> []
  end

  def generate_all_schemas_for_resources(resources, allowed_resources) do
    resources
    |> Enum.map_join("\n\n", &generate_all_schemas_for_resource(&1, allowed_resources))
  end

  def generate_all_schemas_for_resource(resource, allowed_resources) do
    resource_name = build_resource_type_name(resource)
    unified_schema = generate_unified_resource_schema(resource, allowed_resources)

    input_schema =
      if is_embedded_resource?(resource) do
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
    resource_name = build_resource_type_name(resource)

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
      |> Enum.filter(&is_simple_calculation/1)
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
          not is_embedded_resource?(atom_type) and not is_typed_struct?(atom_type)

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
      |> Enum.filter(&is_simple_calculation/1)

    attr_defs =
      Enum.map(primitive_attrs, fn attr ->
        mapped_name = AshTypescript.Resource.Info.get_mapped_field_name(resource, attr.name)

        formatted_name =
          AshTypescript.FieldFormatter.format_field(
            mapped_name,
            AshTypescript.Rpc.output_field_formatter()
          )

        type_str = get_ts_type(attr)

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

        type_str = get_ts_type(calc)

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
              |> lookup_aggregate_type(agg.relationship_path, agg.field)
              |> get_ts_type()

            :first ->
              resource
              |> lookup_aggregate_type(agg.relationship_path, agg.field)
              |> get_ts_type()

            _ ->
              get_ts_type(agg.kind)
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

      related_resource_name = build_resource_type_name(rel.destination)

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
      embedded_resource_name = build_resource_type_name(embedded_resource)

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
    |> Enum.reject(&is_simple_calculation/1)
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

      ts_type = get_ts_type(attr, nil)

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

  defp is_embedded_attribute?(%{type: type}) when is_atom(type), do: is_embedded_resource?(type)

  defp is_embedded_attribute?(%{type: {:array, type}}) when is_atom(type),
    do: is_embedded_resource?(type)

  defp is_embedded_attribute?(_), do: false

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
            resource_name = build_resource_type_name(instance_of)
            "#{resource_name}ResourceSchema"
          else
            "any"
          end

        {:array, Ash.Type.Struct} ->
          constraints = calc.constraints || []
          items_constraints = Keyword.get(constraints, :items, [])
          instance_of = Keyword.get(items_constraints, :instance_of)

          if instance_of && Ash.Resource.Info.resource?(instance_of) do
            resource_name = build_resource_type_name(instance_of)
            "Array<#{resource_name}ResourceSchema>"
          else
            "any[]"
          end

        _ ->
          get_ts_type(calc)
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
          base_type = get_ts_type(arg)

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
          is_embedded_resource?(type) ->
            resource_name = build_resource_type_name(type)
            "#{formatted_name}?: #{resource_name}ResourceSchema"

          is_typed_struct?(type) ->
            "#{formatted_name}?: any"

          true ->
            ts_type = get_ts_type(%{type: type, constraints: constraints})
            "#{formatted_name}?: #{ts_type}"
        end
      end)

    if member_fields == "" do
      "{ __type: \"Union\"; __primitiveFields: #{primitive_union}; }"
    else
      "{ __type: \"Union\"; __primitiveFields: #{primitive_union}; #{member_fields}; }"
    end
  end

  def generate_input_schema(resource) do
    resource_name = build_resource_type_name(resource)

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

        base_type = get_ts_input_type(attr)

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

  def get_ts_input_type(%{type: type} = attr) do
    case type do
      Ash.Type.Map ->
        constraints = Map.get(attr, :constraints, [])

        case Keyword.get(constraints, :fields) do
          nil -> "Record<string, any>"
          fields -> build_map_input_type_inline(fields)
        end

      Ash.Type.Union ->
        constraints = Map.get(attr, :constraints, [])

        case Keyword.get(constraints, :types) do
          nil -> "any"
          types -> build_union_input_type(types)
        end

      embedded_type when is_atom(embedded_type) and not is_nil(embedded_type) ->
        cond do
          is_embedded_resource?(embedded_type) ->
            resource_name = build_resource_type_name(embedded_type)
            "#{resource_name}InputSchema"

          is_typed_struct?(embedded_type) ->
            build_typed_struct_input_type(embedded_type)

          true ->
            get_ts_type(attr)
        end

      {:array, Ash.Type.Union} ->
        constraints = Map.get(attr, :constraints, [])
        items_constraints = Keyword.get(constraints, :items, [])

        case Keyword.get(items_constraints, :types) do
          nil -> "Array<any>"
          types -> "Array<#{build_union_input_type(types)}>"
        end

      {:array, embedded_type} when is_atom(embedded_type) ->
        if is_embedded_resource?(embedded_type) do
          resource_name = build_resource_type_name(embedded_type)
          "Array<#{resource_name}InputSchema>"
        else
          inner_ts = get_ts_input_type(%{type: embedded_type, constraints: []})
          "Array<#{inner_ts}>"
        end

      _ ->
        get_ts_type(attr)
    end
  end

  defp build_map_input_type_inline(fields) do
    field_types =
      fields
      |> Enum.map_join(", ", fn {field_name, field_config} ->
        field_attr = %{type: field_config[:type], constraints: field_config[:constraints] || []}
        field_type = get_ts_input_type(field_attr)

        formatted_field_name =
          AshTypescript.FieldFormatter.format_field(
            field_name,
            AshTypescript.Rpc.output_field_formatter()
          )

        allow_nil = Keyword.get(field_config, :allow_nil?, true)
        optional = if allow_nil, do: "| null", else: ""
        "#{formatted_field_name}: #{field_type}#{optional}"
      end)

    "{#{field_types}}"
  end

  def get_ts_type(type_and_constraints, select_and_loads \\ nil)
  def get_ts_type(:count, _), do: "number"
  def get_ts_type(:sum, _), do: "number"
  def get_ts_type(:exists, _), do: "boolean"
  def get_ts_type(:avg, _), do: "number"
  def get_ts_type(:min, _), do: "any"
  def get_ts_type(:max, _), do: "any"
  def get_ts_type(:first, _), do: "any"
  def get_ts_type(:last, _), do: "any"
  def get_ts_type(:list, _), do: "any[]"
  def get_ts_type(:custom, _), do: "any"
  def get_ts_type(:integer, _), do: "number"
  def get_ts_type(%{type: nil}, _), do: "null"
  def get_ts_type(%{type: :sum}, _), do: "number"
  def get_ts_type(%{type: :count}, _), do: "number"
  def get_ts_type(%{type: :map}, _), do: "Record<string, any>"

  def get_ts_type(%{type: Ash.Type.Atom, constraints: constraints}, _) when constraints != [] do
    case Keyword.get(constraints, :one_of) do
      nil -> "string"
      values -> values |> Enum.map_join(" | ", &"\"#{to_string(&1)}\"")
    end
  end

  def get_ts_type(%{type: Ash.Type.Atom}, _), do: "string"
  def get_ts_type(%{type: Ash.Type.String}, _), do: "string"
  def get_ts_type(%{type: Ash.Type.CiString}, _), do: "string"
  def get_ts_type(%{type: Ash.Type.Integer}, _), do: "number"
  def get_ts_type(%{type: Ash.Type.Float}, _), do: "number"
  def get_ts_type(%{type: Ash.Type.Decimal}, _), do: "Decimal"
  def get_ts_type(%{type: Ash.Type.Boolean}, _), do: "boolean"
  def get_ts_type(%{type: Ash.Type.UUID}, _), do: "UUID"
  def get_ts_type(%{type: Ash.Type.UUIDv7}, _), do: "UUIDv7"
  def get_ts_type(%{type: Ash.Type.Date}, _), do: "AshDate"
  def get_ts_type(%{type: Ash.Type.Time}, _), do: "Time"
  def get_ts_type(%{type: Ash.Type.TimeUsec}, _), do: "TimeUsec"
  def get_ts_type(%{type: Ash.Type.UtcDatetime}, _), do: "UtcDateTime"
  def get_ts_type(%{type: Ash.Type.UtcDatetimeUsec}, _), do: "UtcDateTimeUsec"
  def get_ts_type(%{type: Ash.Type.DateTime}, _), do: "DateTime"
  def get_ts_type(%{type: Ash.Type.NaiveDatetime}, _), do: "NaiveDateTime"
  def get_ts_type(%{type: Ash.Type.Duration}, _), do: "Duration"
  def get_ts_type(%{type: Ash.Type.DurationName}, _), do: "DurationName"
  def get_ts_type(%{type: Ash.Type.Binary}, _), do: "Binary"
  def get_ts_type(%{type: Ash.Type.UrlEncodedBinary}, _), do: "UrlEncodedBinary"
  def get_ts_type(%{type: Ash.Type.File}, _), do: "File"
  def get_ts_type(%{type: Ash.Type.Function}, _), do: "Function"
  def get_ts_type(%{type: Ash.Type.Term}, _), do: "any"
  def get_ts_type(%{type: Ash.Type.Vector}, _), do: "number[]"
  def get_ts_type(%{type: Ash.Type.Module}, _), do: "ModuleName"

  def get_ts_type(%{type: Ash.Type.Map, constraints: constraints}, select)
      when constraints != [] do
    case Keyword.get(constraints, :fields) do
      nil -> "Record<string, any>"
      fields -> build_map_type(fields, select, nil)
    end
  end

  def get_ts_type(%{type: Ash.Type.Map}, _), do: "Record<string, any>"

  def get_ts_type(%{type: Ash.Type.Keyword, constraints: constraints}, _)
      when constraints != [] do
    case Keyword.get(constraints, :fields) do
      nil -> "Record<string, any>"
      fields -> build_map_type(fields, nil, nil)
    end
  end

  def get_ts_type(%{type: Ash.Type.Keyword, constraints: constraints}, _) do
    case Keyword.get(constraints, :fields) do
      nil -> "Record<string, any>"
      fields -> build_map_type(fields, nil, nil)
    end
  end

  def get_ts_type(%{type: Ash.Type.Tuple, constraints: constraints}, _) do
    case Keyword.get(constraints, :fields) do
      nil -> "Record<string, any>"
      fields -> build_map_type(fields, nil, nil)
    end
  end

  def get_ts_type(%{type: Ash.Type.Struct, constraints: constraints}, select_and_loads) do
    instance_of = Keyword.get(constraints, :instance_of)
    fields = Keyword.get(constraints, :fields)

    cond do
      instance_of != nil and is_typed_struct?(instance_of) ->
        field_name_mappings =
          if function_exported?(instance_of, :typescript_field_names, 0) do
            instance_of.typescript_field_names()
          else
            nil
          end

        map_fields =
          if fields != nil do
            fields
          else
            typed_struct_fields = get_typed_struct_fields(instance_of)

            Enum.map(typed_struct_fields, fn field ->
              {field.name,
               [
                 type: field.type,
                 constraints: Map.get(field, :constraints, []),
                 allow_nil?: Map.get(field, :allow_nil?, true)
               ]}
            end)
          end

        build_map_type(map_fields, nil, field_name_mappings)

      instance_of != nil and Spark.Dsl.is?(instance_of, Ash.Resource) ->
        resource_name = build_resource_type_name(instance_of)
        "#{resource_name}ResourceSchema"

      instance_of != nil ->
        build_resource_type(instance_of, select_and_loads)

      fields != nil ->
        build_map_type(fields)

      true ->
        "Record<string, any>"
    end
  end

  def get_ts_type(%{type: Ash.Type.Union, constraints: constraints}, _) do
    case Keyword.get(constraints, :types) do
      nil -> "any"
      types -> build_union_type(types)
    end
  end

  def get_ts_type(%{type: {:array, inner_type}, constraints: constraints}, _) do
    inner_ts_type = get_ts_type(%{type: inner_type, constraints: constraints[:items] || []})
    "Array<#{inner_ts_type}>"
  end

  def get_ts_type(%{type: AshDoubleEntry.ULID}, _), do: "ULID"

  def get_ts_type(%{type: AshPostgres.Ltree, constraints: constraints}, _) do
    escape = Keyword.get(constraints, :escape?, false)

    if escape do
      "AshPostgresLtreeArray"
    else
      "AshPostgresLtreeFlexible"
    end
  end

  def get_ts_type(%{type: AshPostgres.Ltree}, _), do: "AshPostgresLtreeFlexible"
  def get_ts_type(%{type: AshMoney.Types.Money}, _), do: "Money"

  def get_ts_type(%{type: :string}, _), do: "string"
  def get_ts_type(%{type: :integer}, _), do: "number"
  def get_ts_type(%{type: :float}, _), do: "number"
  def get_ts_type(%{type: :decimal}, _), do: "Decimal"
  def get_ts_type(%{type: :boolean}, _), do: "boolean"
  def get_ts_type(%{type: :uuid}, _), do: "UUID"
  def get_ts_type(%{type: :date}, _), do: "Date"
  def get_ts_type(%{type: :time}, _), do: "Time"
  def get_ts_type(%{type: :datetime}, _), do: "DateTime"
  def get_ts_type(%{type: :naive_datetime}, _), do: "NaiveDateTime"
  def get_ts_type(%{type: :utc_datetime}, _), do: "UtcDateTime"
  def get_ts_type(%{type: :utc_datetime_usec}, _), do: "UtcDateTimeUsec"
  def get_ts_type(%{type: :binary}, _), do: "Binary"

  def get_ts_type(%{type: type, constraints: constraints} = attr, _) do
    cond do
      is_custom_type?(type) ->
        type.typescript_type_name()

      is_embedded_resource?(type) ->
        resource_name = build_resource_type_name(type)
        "#{resource_name}ResourceSchema"

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

        # If it's a map/keyword/tuple type with field mappings, handle specially
        if field_name_mappings && subtype in [Ash.Type.Map, Ash.Type.Keyword, Ash.Type.Tuple] do
          case Keyword.get(sub_type_constraints, :fields) do
            nil ->
              get_ts_type(%{attr | type: subtype, constraints: sub_type_constraints})

            fields ->
              build_map_type(fields, nil, field_name_mappings)
          end
        else
          get_ts_type(%{attr | type: subtype, constraints: sub_type_constraints})
        end

      Spark.implements_behaviour?(type, Ash.Type.Enum) ->
        case type do
          module when is_atom(module) ->
            try do
              Enum.map_join(module.values(), " | ", &"\"#{to_string(&1)}\"")
            rescue
              _ -> "string"
            end

          _ ->
            "string"
        end

      true ->
        raise "unsupported type #{inspect(type)}"
    end
  end

  def build_map_type(fields, select \\ nil, field_name_mappings \\ nil) do
    selected_fields =
      if select do
        Enum.filter(fields, fn {field_name, _} -> to_string(field_name) in select end)
      else
        fields
      end

    field_types =
      selected_fields
      |> Enum.map_join(", ", fn {field_name, field_config} ->
        field_type =
          get_ts_type(%{type: field_config[:type], constraints: field_config[:constraints] || []})

        formatted_field_name =
          if field_name_mappings && Keyword.has_key?(field_name_mappings, field_name) do
            Keyword.get(field_name_mappings, field_name) |> to_string()
          else
            field_name
          end
          |> AshTypescript.FieldFormatter.format_field(AshTypescript.Rpc.output_field_formatter())

        allow_nil = Keyword.get(field_config, :allow_nil?, true)
        optional = if allow_nil, do: " | null", else: ""
        "#{formatted_field_name}: #{field_type}#{optional}"
      end)

    primitive_fields_union =
      if Enum.empty?(selected_fields) do
        "never"
      else
        selected_fields
        |> Enum.map_join(" | ", fn {field_name, _field_config} ->
          formatted_field_name =
            if field_name_mappings && Keyword.has_key?(field_name_mappings, field_name) do
              Keyword.get(field_name_mappings, field_name) |> to_string()
            else
              field_name
            end
            |> AshTypescript.FieldFormatter.format_field(
              AshTypescript.Rpc.output_field_formatter()
            )

          "\"#{formatted_field_name}\""
        end)
      end

    "{#{field_types}, __type: \"TypedMap\", __primitiveFields: #{primitive_fields_union}}"
  end

  def build_typed_struct_input_type(typed_struct_module) do
    fields = get_typed_struct_fields(typed_struct_module)

    field_name_mappings =
      if function_exported?(typed_struct_module, :typescript_field_names, 0) do
        typed_struct_module.typescript_field_names()
      else
        nil
      end

    field_types =
      fields
      |> Enum.map_join(", ", fn field ->
        field_name = field.name
        field_type = field.type
        allow_nil = Map.get(field, :allow_nil?, false)
        constraints = Map.get(field, :constraints, [])

        field_attr = %{type: field_type, constraints: constraints}
        ts_type = get_ts_input_type(field_attr)

        mapped_field_name =
          if field_name_mappings && Keyword.has_key?(field_name_mappings, field_name) do
            Keyword.get(field_name_mappings, field_name)
          else
            field_name
          end

        formatted_field_name =
          AshTypescript.FieldFormatter.format_field(
            mapped_field_name,
            AshTypescript.Rpc.output_field_formatter()
          )

        optional = if allow_nil, do: "| null", else: ""
        "#{formatted_field_name}: #{ts_type}#{optional}"
      end)

    "{#{field_types}}"
  end

  def build_union_type(types) do
    primitive_fields = get_union_primitive_fields(types)
    primitive_union = generate_primitive_fields_union(primitive_fields)

    member_properties =
      types
      |> Enum.map_join("; ", fn {type_name, type_config} ->
        formatted_name =
          AshTypescript.FieldFormatter.format_field(
            type_name,
            AshTypescript.Rpc.output_field_formatter()
          )

        ts_type =
          get_union_member_type(%{
            type: type_config[:type],
            constraints: type_config[:constraints] || []
          })

        "#{formatted_name}?: #{ts_type}"
      end)

    case member_properties do
      "" -> "{ __type: \"Union\"; __primitiveFields: #{primitive_union}; }"
      properties -> "{ __type: \"Union\"; __primitiveFields: #{primitive_union}; #{properties}; }"
    end
  end

  defp get_union_member_type(%{type: type, constraints: constraints}) do
    cond do
      is_typed_struct?(type) ->
        resource_name = build_resource_type_name(type)
        "#{resource_name}TypedStructFieldSelection"

      is_embedded_resource?(type) ->
        resource_name = build_resource_type_name(type)
        "#{resource_name}ResourceSchema"

      true ->
        get_ts_type(%{type: type, constraints: constraints})
    end
  end

  defp get_union_member_input_type(%{type: type, constraints: constraints}) do
    cond do
      is_typed_struct?(type) ->
        resource_name = build_resource_type_name(type)
        "#{resource_name}TypedStructInputSchema"

      is_embedded_resource?(type) ->
        resource_name = build_resource_type_name(type)
        "#{resource_name}InputSchema"

      type == Ash.Type.Map ->
        get_ts_input_type(%{type: type, constraints: constraints})

      true ->
        get_ts_type(%{type: type, constraints: constraints})
    end
  end

  def build_union_input_type(types) do
    member_objects =
      types
      |> Enum.map_join(" | ", fn {type_name, type_config} ->
        formatted_name =
          AshTypescript.FieldFormatter.format_field(
            type_name,
            AshTypescript.Rpc.output_field_formatter()
          )

        ts_type =
          get_union_member_input_type(%{
            type: type_config[:type],
            constraints: type_config[:constraints] || []
          })

        "{ #{formatted_name}: #{ts_type} }"
      end)

    case member_objects do
      "" -> "any"
      objects -> objects
    end
  end

  def build_resource_type(resource, select_and_loads \\ nil)

  def build_resource_type(resource, nil) do
    field_types =
      Ash.Resource.Info.public_attributes(resource)
      |> Enum.map_join("\n", fn attr ->
        get_resource_field_spec(attr.name, resource)
      end)

    "{#{field_types}}"
  end

  def build_resource_type(resource, select_and_loads) do
    field_types =
      select_and_loads
      |> Enum.map_join("\n", fn attr ->
        get_resource_field_spec(attr, resource)
      end)

    "{#{field_types}}"
  end

  def get_resource_field_spec(field, resource) when is_atom(field) do
    attributes =
      if field == :id,
        do: [Ash.Resource.Info.attribute(resource, :id)],
        else: Ash.Resource.Info.public_attributes(resource)

    calculations = Ash.Resource.Info.public_calculations(resource)
    aggregates = Ash.Resource.Info.public_aggregates(resource)

    with nil <- Enum.find(attributes, &(&1.name == field)),
         nil <- Enum.find(calculations, &(&1.name == field)),
         nil <- Enum.find(aggregates, &(&1.name == field)) do
      throw("Field not found: #{resource}.#{field}" |> String.replace("Elixir.", ""))
    else
      %Ash.Resource.Attribute{} = attr ->
        formatted_field =
          AshTypescript.FieldFormatter.format_field(
            field,
            AshTypescript.Rpc.output_field_formatter()
          )

        if attr.allow_nil? do
          "  #{formatted_field}: #{get_ts_type(attr)} | null;"
        else
          "  #{formatted_field}: #{get_ts_type(attr)};"
        end

      %Ash.Resource.Calculation{} = calc ->
        formatted_field =
          AshTypescript.FieldFormatter.format_field(
            field,
            AshTypescript.Rpc.output_field_formatter()
          )

        if calc.allow_nil? do
          "  #{formatted_field}: #{get_ts_type(calc)} | null;"
        else
          "  #{formatted_field}: #{get_ts_type(calc)};"
        end

      %Ash.Resource.Aggregate{} = agg ->
        type =
          case agg.kind do
            :sum ->
              resource
              |> lookup_aggregate_type(agg.relationship_path, agg.field)
              |> get_ts_type()

            :first ->
              resource
              |> lookup_aggregate_type(agg.relationship_path, agg.field)
              |> get_ts_type()

            _ ->
              get_ts_type(agg.kind)
          end

        formatted_field =
          AshTypescript.FieldFormatter.format_field(
            field,
            AshTypescript.Rpc.output_field_formatter()
          )

        if agg.include_nil? do
          "  #{formatted_field}: #{type} | null;"
        else
          "  #{formatted_field}: #{type};"
        end

      field ->
        throw("Unknown field type: #{inspect(field)}")
    end
  end

  def get_resource_field_spec({field_name, fields}, resource) do
    relationships = Ash.Resource.Info.public_relationships(resource)

    case Enum.find(relationships, &(&1.name == field_name)) do
      nil ->
        throw(
          "Relationship not found on #{resource}: #{field_name}"
          |> String.replace("Elixir.", "")
        )

      %Ash.Resource.Relationships.HasMany{} = rel ->
        id_fields = Ash.Resource.Info.primary_key(resource)
        fields = Enum.uniq(fields ++ id_fields)

        "  #{field_name}: {#{Enum.map_join(fields, "\n", &get_resource_field_spec(&1, rel.destination))}\n}[];\n"

      %Ash.Resource.Relationships.ManyToMany{} = rel ->
        id_fields = Ash.Resource.Info.primary_key(resource)
        fields = Enum.uniq(fields ++ id_fields)

        "  #{field_name}: {#{Enum.map_join(fields, "\n", &get_resource_field_spec(&1, rel.destination))}\n}[];\n"

      rel ->
        id_fields = Ash.Resource.Info.primary_key(resource)
        fields = Enum.uniq(fields ++ id_fields)

        if rel.allow_nil? do
          "  #{field_name}: {#{Enum.map_join(fields, "\n", &get_resource_field_spec(&1, rel.destination))}} | null;"
        else
          "  #{field_name}: {#{Enum.map_join(fields, "\n", &get_resource_field_spec(&1, rel.destination))}};\n"
        end
    end
  end

  def lookup_aggregate_type(current_resource, [], field) do
    Ash.Resource.Info.attribute(current_resource, field)
  end

  def lookup_aggregate_type(current_resource, relationship_path, field) do
    [next_resource | rest] = relationship_path

    relationship =
      Enum.find(Ash.Resource.Info.relationships(current_resource), &(&1.name == next_resource))

    lookup_aggregate_type(relationship.destination, rest, field)
  end

  defp is_simple_calculation(%Ash.Resource.Calculation{} = calc) do
    has_arguments = length(calc.arguments) > 0
    has_complex_return_type = is_complex_return_type(calc.type, calc.constraints)

    not has_arguments and not has_complex_return_type
  end

  defp is_complex_return_type(Ash.Type.Struct, constraints) do
    instance_of = Keyword.get(constraints, :instance_of)
    instance_of != nil
  end

  defp is_complex_return_type(Ash.Type.Map, constraints) do
    fields = Keyword.get(constraints, :fields)
    fields != nil
  end

  defp is_complex_return_type(Ash.Type.Keyword, _constraints), do: true
  defp is_complex_return_type(Ash.Type.Tuple, _constraints), do: true

  defp is_complex_return_type(_, _), do: false

  def build_resource_type_name(resource_module) do
    case AshTypescript.Resource.Info.typescript_type_name(resource_module) do
      {:ok, name} ->
        name

      _ ->
        resource_module
        |> Module.split()
        |> then(fn [first | rest] = list ->
          if first == "Elixir" do
            Enum.join(rest, "")
          else
            Enum.join(list, "")
          end
        end)
    end
  end
end
