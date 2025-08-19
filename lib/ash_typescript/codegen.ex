defmodule AshTypescript.Codegen do
  # Embedded resource discovery functions

  @doc """
  Discovers embedded resources from a list of regular resources by scanning their attributes.
  Returns a list of unique embedded resource modules.
  """
  def find_embedded_resources(resources) do
    resources
    |> Enum.flat_map(&extract_embedded_from_resource/1)
    |> Enum.uniq()
  end

  defp extract_embedded_from_resource(resource) do
    resource
    |> Ash.Resource.Info.public_attributes()
    |> Enum.filter(&is_embedded_resource_attribute?/1)
    |> Enum.flat_map(&extract_embedded_modules/1)
    # Remove nils
    |> Enum.filter(& &1)
  end

  defp is_embedded_resource_attribute?(%Ash.Resource.Attribute{
         type: type,
         constraints: constraints
       }) do
    case type do
      # Handle union types FIRST (before general atom patterns)
      Ash.Type.Union ->
        union_types = Keyword.get(constraints, :types, [])

        Enum.any?(union_types, fn {_type_name, type_config} ->
          type = Keyword.get(type_config, :type)
          type && is_embedded_resource?(type)
        end)

      # Handle array of union types FIRST (before general array patterns)
      {:array, Ash.Type.Union} ->
        items_constraints = Keyword.get(constraints, :items, [])
        union_types = Keyword.get(items_constraints, :types, [])

        Enum.any?(union_types, fn {_type_name, type_config} ->
          type = Keyword.get(type_config, :type)
          type && is_embedded_resource?(type)
        end)

      # Handle Ash.Type.Struct with instance_of constraint
      Ash.Type.Struct ->
        instance_of = Keyword.get(constraints, :instance_of)
        instance_of && is_embedded_resource?(instance_of)

      # Handle array of Ash.Type.Struct
      {:array, Ash.Type.Struct} ->
        items_constraints = Keyword.get(constraints, :items, [])
        instance_of = Keyword.get(items_constraints, :instance_of)
        instance_of && is_embedded_resource?(instance_of)

      # Handle direct embedded resource module (what Ash actually stores)
      module when is_atom(module) ->
        is_embedded_resource?(module)

      # Handle array of direct embedded resource module
      {:array, module} when is_atom(module) ->
        is_embedded_resource?(module)

      _ ->
        false
    end
  end

  defp is_embedded_resource_attribute?(_), do: false

  # New function that returns a list of embedded modules (handles union types)
  defp extract_embedded_modules(%Ash.Resource.Attribute{type: type, constraints: constraints}) do
    case type do
      # Handle union types FIRST (before general atom patterns)
      Ash.Type.Union ->
        union_types = Keyword.get(constraints, :types, [])

        Enum.flat_map(union_types, fn {_type_name, type_config} ->
          type = Keyword.get(type_config, :type)
          if type && is_embedded_resource?(type), do: [type], else: []
        end)

      # Handle array of union types FIRST (before general array patterns)
      {:array, Ash.Type.Union} ->
        items_constraints = Keyword.get(constraints, :items, [])
        union_types = Keyword.get(items_constraints, :types, [])

        Enum.flat_map(union_types, fn {_type_name, type_config} ->
          type = Keyword.get(type_config, :type)
          if type && is_embedded_resource?(type), do: [type], else: []
        end)

      # Handle Ash.Type.Struct with instance_of constraint
      Ash.Type.Struct ->
        module = Keyword.get(constraints, :instance_of)
        if module && is_embedded_resource?(module), do: [module], else: []

      # Handle array of Ash.Type.Struct
      {:array, Ash.Type.Struct} ->
        items_constraints = Keyword.get(constraints, :items, [])
        module = Keyword.get(items_constraints, :instance_of)
        if module && is_embedded_resource?(module), do: [module], else: []

      # Handle direct embedded resource module
      module when is_atom(module) ->
        if is_embedded_resource?(module), do: [module], else: []

      # Handle array of direct embedded resource module
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
    # Discover embedded resources from regular resources
    embedded_resources = find_embedded_resources(resources)

    # Include embedded resources in type discovery process
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
  defp generate_ash_type_alias(Ash.Type.String), do: ""
  defp generate_ash_type_alias(Ash.Type.CiString), do: ""
  defp generate_ash_type_alias(Ash.Type.UUID), do: "type UUID = string;"
  defp generate_ash_type_alias(Ash.Type.UUIDv7), do: "type UUIDv7 = string;"
  defp generate_ash_type_alias(Ash.Type.Decimal), do: "type Decimal = string;"
  defp generate_ash_type_alias(Ash.Type.Date), do: "type AshDate = string;"
  defp generate_ash_type_alias(Ash.Type.Time), do: "type Time = string;"
  defp generate_ash_type_alias(Ash.Type.TimeUsec), do: "type TimeUsec = string;"
  defp generate_ash_type_alias(Ash.Type.UtcDatetime), do: "type UtcDateTime = string;"
  defp generate_ash_type_alias(Ash.Type.UtcDatetimeUsec), do: "type UtcDateTimeUsec = string;"
  defp generate_ash_type_alias(Ash.Type.DateTime), do: "type DateTime = string;"
  defp generate_ash_type_alias(Ash.Type.NaiveDatetime), do: "type NaiveDateTime = string;"
  defp generate_ash_type_alias(Ash.Type.Duration), do: "type Duration = string;"
  defp generate_ash_type_alias(Ash.Type.DurationName), do: "type DurationName = string;"
  defp generate_ash_type_alias(Ash.Type.Binary), do: "type Binary = string;"
  defp generate_ash_type_alias(Ash.Type.UrlEncodedBinary), do: "type UrlEncodedBinary = string;"
  defp generate_ash_type_alias(Ash.Type.File), do: "type File = any;"
  defp generate_ash_type_alias(Ash.Type.Function), do: "type Function = any;"
  defp generate_ash_type_alias(Ash.Type.Module), do: "type ModuleName = string;"
  defp generate_ash_type_alias(AshDoubleEntry.ULID), do: "type ULID = string;"

  defp generate_ash_type_alias(AshMoney.Types.Money),
    do: "type Money = { amount: string; currency: string };"

  defp generate_ash_type_alias(type) do
    cond do
      # Custom types no longer generate type aliases - they are imported from external files
      is_custom_type?(type) ->
        ""

      Ash.Type.NewType.new_type?(type) or Spark.implements_behaviour?(type, Ash.Type.Enum) ->
        ""

      is_embedded_resource?(type) ->
        # Embedded resources don't need type aliases - they get full schema generation
        ""

      true ->
        raise "Unknown type: #{type}"
    end
  end

  # Checks if a type is a custom type that implements the required TypeScript callbacks.
  # Custom types must implement Ash.Type behaviour and provide typescript_type_name/0.
  defp is_custom_type?(type) do
    is_atom(type) and
      Code.ensure_loaded?(type) and
      function_exported?(type, :typescript_type_name, 0) and
      Spark.implements_behaviour?(type, Ash.Type)
  end

  # Custom types no longer generate type aliases - they are imported from external files

  # TypedStruct discovery functions

  @doc """
  Checks if a type is a TypedStruct using simplified Spark DSL detection.
  """
  def is_typed_struct?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and
      function_exported?(module, :spark_is, 0) and
      is_ash_typed_struct?(module)
  end

  def is_typed_struct?(_), do: false

  # Check if the module's spark_is/0 returns Ash.TypedStruct
  defp is_ash_typed_struct?(module) do
    try do
      module.spark_is() == Ash.TypedStruct
    rescue
      _ -> false
    end
  end

  @doc """
  Gets the field information from a TypedStruct module using Ash's DSL pattern.
  Returns a list of field definitions.
  """
  def get_typed_struct_fields(module) do
    try do
      # Use Ash's standard way to get entities from DSL sections
      if is_typed_struct?(module) do
        Spark.Dsl.Extension.get_entities(module, [:typed_struct])
      else
        []
      end
    rescue
      _ -> []
    end
  end

  def generate_all_schemas_for_resources(resources, allowed_resources) do
    resources
    |> Enum.map(&generate_all_schemas_for_resource(&1, allowed_resources))
    |> Enum.join("\n\n")
  end

  def generate_all_schemas_for_resource(resource, allowed_resources) do
    resource_name = build_resource_type_name(resource)

    # Generate the new unified schema
    unified_schema = generate_unified_resource_schema(resource, allowed_resources)

    # Generate input schema for embedded resources
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

    if input_schema != "" do
      base_schemas <> "\n\n" <> input_schema
    else
      base_schemas
    end
  end

  defp is_typed_struct_attribute?(%Ash.Resource.Attribute{type: type, constraints: constraints}) do
    case type do
      # Handle union types FIRST (before general atom patterns)
      Ash.Type.Union ->
        union_types = Keyword.get(constraints, :types, [])

        Enum.any?(union_types, fn {_type_name, type_config} ->
          type = Keyword.get(type_config, :type)
          type && is_typed_struct?(type)
        end)

      # Handle array of union types FIRST (before general array patterns)
      {:array, Ash.Type.Union} ->
        items_constraints = Keyword.get(constraints, :items, [])
        union_types = Keyword.get(items_constraints, :types, [])

        Enum.any?(union_types, fn {_type_name, type_config} ->
          type = Keyword.get(type_config, :type)
          type && is_typed_struct?(type)
        end)

      # Handle direct TypedStruct module
      module when is_atom(module) ->
        is_typed_struct?(module)

      # Handle array of TypedStruct
      {:array, module} when is_atom(module) ->
        is_typed_struct?(module)

      _ ->
        false
    end
  end

  defp is_typed_struct_attribute?(_), do: false

  @doc """
  Generates a unified resource schema with metadata fields and direct field access.
  This replaces the multiple separate schemas with a single, metadata-driven schema.
  """
  def generate_unified_resource_schema(resource, allowed_resources) do
    resource_name = build_resource_type_name(resource)

    # Get all primitive fields
    primitive_fields = get_primitive_fields(resource)
    primitive_fields_union = generate_primitive_fields_union(primitive_fields)

    # Add metadata fields
    metadata_fields = [
      "  __type: \"Resource\";",
      "  __primitiveFields: #{primitive_fields_union};"
    ]

    # Add primitive fields directly
    primitive_field_defs = generate_primitive_field_definitions(resource)

    # Add relationships with metadata
    relationship_field_defs = generate_relationship_field_definitions(resource, allowed_resources)

    # Add embedded resources with metadata
    embedded_field_defs = generate_embedded_field_definitions(resource, allowed_resources)

    # Add complex calculations with metadata
    complex_calc_field_defs = generate_complex_calculation_field_definitions(resource)

    # Add union fields with metadata
    union_field_defs = generate_union_field_definitions(resource)

    # Combine all fields
    all_field_lines =
      metadata_fields ++
        primitive_field_defs ++
        relationship_field_defs ++
        embedded_field_defs ++
        complex_calc_field_defs ++
        union_field_defs

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

    # Filter to only primitive fields (not embedded, union, or complex calculations)
    primitive_attrs =
      attributes
      |> Enum.reject(fn attr ->
        is_union_attribute?(attr) or
          is_embedded_attribute?(attr) or
          is_typed_struct_attribute?(attr)
      end)
      |> Enum.map(& &1.name)

    # Simple calculations (no args, simple return type)
    simple_calcs =
      calculations
      |> Enum.filter(&is_simple_calculation/1)
      |> Enum.map(& &1.name)

    # All aggregates are primitive
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

  defp generate_primitive_fields_union(fields) do
    if Enum.empty?(fields) do
      "never"
    else
      fields
      |> Enum.map(fn field_name ->
        formatted =
          AshTypescript.FieldFormatter.format_field(
            field_name,
            AshTypescript.Rpc.output_field_formatter()
          )

        "\"#{formatted}\""
      end)
      |> Enum.join(" | ")
    end
  end

  defp generate_primitive_field_definitions(resource) do
    attributes = Ash.Resource.Info.public_attributes(resource)
    calculations = Ash.Resource.Info.public_calculations(resource)
    aggregates = Ash.Resource.Info.public_aggregates(resource)

    # Filter to only primitive attributes
    primitive_attrs =
      attributes
      |> Enum.reject(fn attr ->
        is_union_attribute?(attr) or
          is_embedded_attribute?(attr) or
          is_typed_struct_attribute?(attr)
      end)

    # Simple calculations
    simple_calcs =
      calculations
      |> Enum.filter(&is_simple_calculation/1)

    # Generate field definitions
    attr_defs =
      Enum.map(primitive_attrs, fn attr ->
        formatted_name =
          AshTypescript.FieldFormatter.format_field(
            attr.name,
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
        formatted_name =
          AshTypescript.FieldFormatter.format_field(
            calc.name,
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
        formatted_name =
          AshTypescript.FieldFormatter.format_field(
            agg.name,
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
      formatted_name =
        AshTypescript.FieldFormatter.format_field(
          rel.name,
          AshTypescript.Rpc.output_field_formatter()
        )

      related_resource_name = build_resource_type_name(rel.destination)

      # Handle nullability by modifying the __resource field
      resource_type =
        if rel.type in [:has_many, :many_to_many] do
          # Array relationships are never null
          "#{related_resource_name}ResourceSchema"
        else
          # Single relationships can be null
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
      formatted_name =
        AshTypescript.FieldFormatter.format_field(
          attr.name,
          AshTypescript.Rpc.output_field_formatter()
        )

      embedded_resource = get_embedded_resource_from_attr(attr)
      embedded_resource_name = build_resource_type_name(embedded_resource)

      # Handle nullability by modifying the __resource field
      resource_type =
        case attr.type do
          {:array, _} ->
            # Array embedded resources are never null
            "#{embedded_resource_name}ResourceSchema"

          _ ->
            # Single embedded resources can be null
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
      formatted_name =
        AshTypescript.FieldFormatter.format_field(
          calc.name,
          AshTypescript.Rpc.output_field_formatter()
        )

      # Generate metadata based on calculation type (nullability goes in return type)
      return_type = get_calculation_return_type_for_metadata(calc, calc.allow_nil?)

      metadata =
        if Enum.empty?(calc.arguments) do
          "{ __type: \"ComplexCalculation\"; __returnType: #{return_type}; }"
        else
          args_type = generate_calculation_args_type(calc.arguments)

          "{ __type: \"ComplexCalculation\"; __returnType: #{return_type}; __args: #{args_type}; }"
        end

      # Field itself is never nullable - nullability is in __returnType
      "  #{formatted_name}: #{metadata};"
    end)
  end

  defp generate_union_field_definitions(resource) do
    attributes = Ash.Resource.Info.public_attributes(resource)

    attributes
    |> Enum.filter(&is_union_attribute?/1)
    |> Enum.map(fn attr ->
      formatted_name =
        AshTypescript.FieldFormatter.format_field(
          attr.name,
          AshTypescript.Rpc.output_field_formatter()
        )

      union_metadata = generate_union_metadata(attr)

      if attr.allow_nil? do
        "  #{formatted_name}: #{union_metadata} | null;"
      else
        "  #{formatted_name}: #{union_metadata};"
      end
    end)
  end

  # Helper functions for the new unified schema generation
  defp is_union_attribute?(%{type: Ash.Type.Union}), do: true
  defp is_union_attribute?(%{type: {:array, Ash.Type.Union}}), do: true
  defp is_union_attribute?(_), do: false

  defp is_embedded_attribute?(%{type: type}) when is_atom(type), do: is_embedded_resource?(type)

  defp is_embedded_attribute?(%{type: {:array, type}}) when is_atom(type),
    do: is_embedded_resource?(type)

  defp is_embedded_attribute?(_), do: false

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

    # Add nullability to the return type itself if allow_nil? is true
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
        |> Enum.map(fn arg ->
          formatted_name =
            AshTypescript.FieldFormatter.format_field(
              arg.name,
              AshTypescript.Rpc.output_field_formatter()
            )

          # Field is optional if it has a default value (even if that default is nil)
          has_default = Map.has_key?(arg, :default)
          # Field can be null if allow_nil? is true
          allows_null = arg.allow_nil?

          base_type = get_ts_type(arg)

          # Add | null if the field allows null
          type_str =
            if allows_null do
              "#{base_type} | null"
            else
              base_type
            end

          # Make field optional if it has a default
          if has_default do
            "#{formatted_name}?: #{type_str}"
          else
            "#{formatted_name}: #{type_str}"
          end
        end)
        |> Enum.join("; ")

      "{ #{args} }"
    end
  end

  defp generate_union_metadata(attr) do
    constraints = attr.constraints || []

    # Handle both regular unions and array unions
    union_types =
      case attr.type do
        {:array, Ash.Type.Union} ->
          # For array unions, types are under items
          items_constraints = Keyword.get(constraints, :items, [])
          Keyword.get(items_constraints, :types, [])

        Ash.Type.Union ->
          # For regular unions, types are directly under constraints
          Keyword.get(constraints, :types, [])

        _ ->
          []
      end

    # Get primitive fields from union using helper
    primitive_fields = get_union_primitive_fields(union_types)
    primitive_union = generate_primitive_fields_union(primitive_fields)

    # Generate union member fields
    member_fields =
      union_types
      |> Enum.map(fn {name, config} ->
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
            # For embedded resources in unions, reference the resource schema
            "#{formatted_name}?: #{resource_name}ResourceSchema"

          is_typed_struct?(type) ->
            # Handle TypedStruct in union
            "#{formatted_name}?: any"

          true ->
            ts_type = get_ts_type(%{type: type, constraints: constraints})
            "#{formatted_name}?: #{ts_type}"
        end
      end)
      |> Enum.join("; ")

    # Handle empty member fields properly
    if member_fields == "" do
      "{ __type: \"Union\"; __primitiveFields: #{primitive_union}; }"
    else
      "{ __type: \"Union\"; __primitiveFields: #{primitive_union}; #{member_fields}; }"
    end
  end

  def generate_input_schema(resource) do
    resource_name = build_resource_type_name(resource)

    # Only include settable public attributes (no calculations, relationships, or private fields)
    input_fields =
      resource
      |> Ash.Resource.Info.public_attributes()
      |> Enum.map(fn attr ->
        formatted_name =
          AshTypescript.FieldFormatter.format_field(
            attr.name,
            AshTypescript.Rpc.output_field_formatter()
          )

        # For input types, use input-specific type mapping
        base_type = get_ts_input_type(attr)

        # Handle optionality for input types:
        # - Field is optional if it allows nil OR has a default value
        # - For input, we don't want | null for optional fields with defaults
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
      |> Enum.join("\n")

    """
    export type #{resource_name}InputSchema = {
    #{input_fields}
    };
    """
  end

  # Input-specific type mapping for embedded resources
  def get_ts_input_type(%{type: type} = attr) do
    case type do
      # Handle Map types FIRST - before the general atom pattern
      Ash.Type.Map ->
        # Handle Map types in input - use input version without metadata
        constraints = Map.get(attr, :constraints, [])

        case Keyword.get(constraints, :fields) do
          nil -> "Record<string, any>"
          fields -> build_map_input_type_inline(fields)
        end

      # Handle Union types FIRST - before the general atom pattern
      Ash.Type.Union ->
        # Handle union types in input - use InputSchema for embedded resources
        constraints = Map.get(attr, :constraints, [])

        case Keyword.get(constraints, :types) do
          nil -> "any"
          types -> build_union_input_type(types)
        end

      # Handle embedded resource atoms (after specific Ash types)
      embedded_type when is_atom(embedded_type) and not is_nil(embedded_type) ->
        cond do
          is_embedded_resource?(embedded_type) ->
            # Handle direct embedded resource types (e.g., attribute :metadata, TodoMetadata)
            resource_name = build_resource_type_name(embedded_type)
            "#{resource_name}InputSchema"

          is_typed_struct?(embedded_type) ->
            # Handle TypedStruct types - generate input version without metadata
            build_typed_struct_input_type(embedded_type)

          true ->
            # For all other atomic types, use the regular type mapping
            get_ts_type(attr)
        end

      {:array, embedded_type} when is_atom(embedded_type) ->
        if is_embedded_resource?(embedded_type) do
          # Handle array of embedded resources (e.g., attribute :metadata_history, {:array, TodoMetadata})
          resource_name = build_resource_type_name(embedded_type)
          "Array<#{resource_name}InputSchema>"
        else
          # Handle regular array types
          inner_ts = get_ts_input_type(%{type: embedded_type, constraints: []})
          "Array<#{inner_ts}>"
        end

      _ ->
        # For all other types, use the regular type mapping
        get_ts_type(attr)
    end
  end

  # Inline version to avoid function visibility issues
  defp build_map_input_type_inline(fields) do
    field_types =
      fields
      |> Enum.map(fn {field_name, field_config} ->
        # Use get_ts_input_type for nested fields to ensure no metadata in nested Maps
        field_attr = %{type: field_config[:type], constraints: field_config[:constraints] || []}
        field_type = get_ts_input_type(field_attr)

        # Apply field formatter to field name
        formatted_field_name =
          AshTypescript.FieldFormatter.format_field(
            field_name,
            AshTypescript.Rpc.output_field_formatter()
          )

        allow_nil = Keyword.get(field_config, :allow_nil?, true)
        optional = if allow_nil, do: "| null", else: ""
        "#{formatted_field_name}: #{field_type}#{optional}"
      end)
      |> Enum.join(", ")

    # No metadata fields for input schemas
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
      values -> values |> Enum.map(&"\"#{to_string(&1)}\"") |> Enum.join(" | ")
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
      fields -> build_map_type(fields, select)
    end
  end

  def get_ts_type(%{type: Ash.Type.Map}, _), do: "Record<string, any>"

  def get_ts_type(%{type: Ash.Type.Keyword, constraints: constraints}, _)
      when constraints != [] do
    case Keyword.get(constraints, :fields) do
      nil -> "Record<string, any>"
      fields -> build_map_type(fields)
    end
  end

  def get_ts_type(%{type: Ash.Type.Keyword}, _), do: "Record<string, any>"

  def get_ts_type(%{type: Ash.Type.Tuple, constraints: constraints}, _) do
    case Keyword.get(constraints, :fields) do
      nil -> "Record<string, any>"
      fields -> build_map_type(fields)
    end
  end

  def get_ts_type(%{type: Ash.Type.Struct, constraints: constraints}, select_and_loads) do
    instance_of = Keyword.get(constraints, :instance_of)
    fields = Keyword.get(constraints, :fields)

    cond do
      fields != nil ->
        # If fields are defined, create a typed object
        build_map_type(fields)

      instance_of != nil ->
        # Check if instance_of is an Ash resource
        if Spark.Dsl.is?(instance_of, Ash.Resource) do
          # Return reference to the resource schema type
          resource_name = build_resource_type_name(instance_of)
          "#{resource_name}ResourceSchema"
        else
          build_resource_type(instance_of, select_and_loads)
        end

      true ->
        # Fallback to generic record type
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
  def get_ts_type(%{type: AshMoney.Types.Money}, _), do: "Money"

  # Handle atom types (shorthand versions)
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
      # NEW: Custom type support - check first
      is_custom_type?(type) ->
        apply(type, :typescript_type_name, [])

      is_embedded_resource?(type) ->
        # Handle direct embedded resource types (e.g., attribute :metadata, TodoMetadata)
        resource_name = build_resource_type_name(type)
        "#{resource_name}ResourceSchema"

      Ash.Type.NewType.new_type?(type) ->
        sub_type_constraints = Ash.Type.NewType.constraints(type, constraints)
        subtype = Ash.Type.NewType.subtype_of(type)
        get_ts_type(%{attr | type: subtype, constraints: sub_type_constraints})

      Spark.implements_behaviour?(type, Ash.Type.Enum) ->
        case type do
          module when is_atom(module) ->
            try do
              values = apply(module, :values, [])
              values |> Enum.map(&"\"#{to_string(&1)}\"") |> Enum.join(" | ")
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

  def build_map_type(fields, select \\ nil) do
    selected_fields =
      if select do
        Enum.filter(fields, fn {field_name, _} -> to_string(field_name) in select end)
      else
        fields
      end

    field_types =
      selected_fields
      |> Enum.map(fn {field_name, field_config} ->
        field_type =
          get_ts_type(%{type: field_config[:type], constraints: field_config[:constraints] || []})

        # Apply field formatter to field name
        formatted_field_name =
          AshTypescript.FieldFormatter.format_field(
            field_name,
            AshTypescript.Rpc.output_field_formatter()
          )

        allow_nil = Keyword.get(field_config, :allow_nil?, true)
        optional = if allow_nil, do: "| null", else: ""
        "#{formatted_field_name}: #{field_type}#{optional}"
      end)
      |> Enum.join(", ")

    # Generate primitive fields union for TypedMap metadata
    primitive_fields_union =
      if Enum.empty?(selected_fields) do
        "never"
      else
        selected_fields
        |> Enum.map(fn {field_name, _field_config} ->
          formatted_field_name =
            AshTypescript.FieldFormatter.format_field(
              field_name,
              AshTypescript.Rpc.output_field_formatter()
            )

          "\"#{formatted_field_name}\""
        end)
        |> Enum.join(" | ")
      end

    "{#{field_types}, __type: \"TypedMap\", __primitiveFields: #{primitive_fields_union}}"
  end

  def build_typed_struct_input_type(typed_struct_module) do
    fields = get_typed_struct_fields(typed_struct_module)

    field_types =
      fields
      |> Enum.map(fn field ->
        field_name = field.name
        field_type = field.type
        allow_nil = Map.get(field, :allow_nil?, false)
        constraints = Map.get(field, :constraints, [])

        # Use get_ts_input_type to ensure no metadata in nested fields
        field_attr = %{type: field_type, constraints: constraints}
        ts_type = get_ts_input_type(field_attr)

        # Apply field formatter to field name
        formatted_field_name =
          AshTypescript.FieldFormatter.format_field(
            field_name,
            AshTypescript.Rpc.output_field_formatter()
          )

        optional = if allow_nil, do: "| null", else: ""
        "#{formatted_field_name}: #{ts_type}#{optional}"
      end)
      |> Enum.join(", ")

    # No metadata fields for input schemas
    "{#{field_types}}"
  end

  def build_union_type(types) do
    # Get primitive fields from union using helper
    primitive_fields = get_union_primitive_fields(types)
    primitive_union = generate_primitive_fields_union(primitive_fields)

    member_properties =
      types
      |> Enum.map(fn {type_name, type_config} ->
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
      |> Enum.join("; ")

    case member_properties do
      "" -> "{ __type: \"Union\"; __primitiveFields: #{primitive_union}; }"
      properties -> "{ __type: \"Union\"; __primitiveFields: #{primitive_union}; #{properties}; }"
    end
  end

  # Special function for union member types - uses ResourceSchema for embedded resources
  defp get_union_member_type(%{type: type, constraints: constraints}) do
    cond do
      is_typed_struct?(type) ->
        # TypedStruct in union supports field selection
        resource_name = build_resource_type_name(type)
        "#{resource_name}TypedStructFieldSelection"

      is_embedded_resource?(type) ->
        # For union members, use ResourceSchema instead of the old FieldsSchema
        resource_name = build_resource_type_name(type)
        "#{resource_name}ResourceSchema"

      # For all other types, use the regular get_ts_type function
      true ->
        get_ts_type(%{type: type, constraints: constraints})
    end
  end

  # Special function for union member input types - uses InputSchema for embedded resources
  defp get_union_member_input_type(%{type: type, constraints: constraints}) do
    cond do
      is_typed_struct?(type) ->
        # For TypedStruct union member inputs, use InputSchema
        resource_name = build_resource_type_name(type)
        "#{resource_name}TypedStructInputSchema"

      is_embedded_resource?(type) ->
        # For union member inputs, use InputSchema (not the old FieldsSchema)
        resource_name = build_resource_type_name(type)
        "#{resource_name}InputSchema"

      # For TypedMaps, use input-specific type generation (no metadata fields)
      type == Ash.Type.Map ->
        get_ts_input_type(%{type: type, constraints: constraints})

      # For all other types, use the regular get_ts_type function
      true ->
        get_ts_type(%{type: type, constraints: constraints})
    end
  end

  # Build union type for input schemas
  def build_union_input_type(types) do
    member_properties =
      types
      |> Enum.map(fn {type_name, type_config} ->
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

        "#{formatted_name}?: #{ts_type}"
      end)
      |> Enum.join("; ")

    case member_properties do
      "" -> "any"
      properties -> "{ #{properties} }"
    end
  end

  def build_resource_type(resource, select_and_loads \\ nil)

  def build_resource_type(resource, nil) do
    field_types =
      Ash.Resource.Info.public_attributes(resource)
      |> Enum.map(fn attr ->
        get_resource_field_spec(attr.name, resource)
      end)
      |> Enum.join("\n")

    "{#{field_types}}"
  end

  def build_resource_type(resource, select_and_loads) do
    field_types =
      select_and_loads
      |> Enum.map(fn attr ->
        get_resource_field_spec(attr, resource)
      end)
      |> Enum.join("\n")

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

  # Helper function to determine if a calculation is simple (no arguments, simple return type)
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
