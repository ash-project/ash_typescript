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
    if Ash.Resource.Info.resource?(module) do
      # Check if it's an embedded resource by checking the data layer
      data_layer = Ash.Resource.Info.data_layer(module)

      # Embedded resources can use different data layers but are defined with data_layer: :embedded
      # We need to check the resource definition itself
      embedded_config =
        try do
          # Try to get the embedded configuration from the resource
          module.__ash_dsl_config__()
          |> get_in([:resource, :data_layer])
        rescue
          _ -> nil
        end

      embedded_config == :embedded or data_layer == Ash.DataLayer.Simple
    else
      false
    end
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

    Enum.map(types, fn type ->
      case type do
        {:array, type} -> generate_ash_type_alias(type)
        type -> generate_ash_type_alias(type)
      end
    end)
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
      # NEW: Custom type detection - check before other patterns
      is_custom_type?(type) ->
        generate_custom_type_alias(type)

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
  # Custom types must implement Ash.Type behaviour and provide both typescript_type_name/0 and typescript_type_def/0.
  defp is_custom_type?(type) do
    is_atom(type) and
      Code.ensure_loaded?(type) and
      function_exported?(type, :typescript_type_name, 0) and
      function_exported?(type, :typescript_type_def, 0) and
      Spark.implements_behaviour?(type, Ash.Type)
  end

  # Generates a TypeScript type alias for a custom type.
  # Combines the type name and definition from the callbacks.
  defp generate_custom_type_alias(type) do
    type_name = apply(type, :typescript_type_name, [])
    type_def = apply(type, :typescript_type_def, [])
    "type #{type_name} = #{type_def};"
  end


  def generate_all_schemas_for_resources(resources, allowed_resources) do
    resources
    |> Enum.map(&generate_all_schemas_for_resource(&1, allowed_resources))
    |> Enum.join("\n\n")
  end

  def generate_all_schemas_for_resource(resource, allowed_resources) do
    resource_name = resource |> Module.split() |> List.last()

    attributes_schema = generate_attributes_schema(resource)
    complex_calculations_schema = generate_complex_calculations_schema(resource)
    relationship_schema = generate_relationship_schema(resource, allowed_resources)
    unions_schema = generate_unions_schema(resource)
    resource_schema = generate_resource_schema(resource)

    # Generate input schema for embedded resources
    input_schema =
      if is_embedded_resource?(resource) do
        generate_input_schema(resource)
      else
        ""
      end

    base_schemas = """
    // #{resource_name} Schemas
    #{attributes_schema}

    #{complex_calculations_schema}

    #{relationship_schema}

    #{unions_schema}

    #{resource_schema}
    """

    if input_schema != "" do
      base_schemas <> "\n\n" <> input_schema
    else
      base_schemas
    end
  end

  def generate_attributes_schema(resource) do
    resource_name = resource |> Module.split() |> List.last()

    attributes =
      resource
      |> Ash.Resource.Info.public_attributes()
      |> Enum.reject(fn attr ->
        case attr.type do
          # Exclude union types from fields schema FIRST - they go in unions section
          Ash.Type.Union ->
            true

          {:array, Ash.Type.Union} ->
            true

          # Also check for atom-based union types
          :union ->
            true

          {:array, :union} ->
            true

          # Exclude embedded resources from fields schema - they go in embedded section
          embedded_type when is_atom(embedded_type) ->
            is_embedded_resource?(embedded_type)

          {:array, embedded_type} when is_atom(embedded_type) ->
            is_embedded_resource?(embedded_type)

          _ ->
            false
        end
      end)

    calculations =
      resource
      |> Ash.Resource.Info.public_calculations()

    aggregates =
      resource
      |> Ash.Resource.Info.public_aggregates()

    # Filter out complex calculations (those with arguments or complex return types)
    {simple_calculations, _complex_calculations} =
      Enum.split_with(calculations, &is_simple_calculation/1)

    fields =
      Enum.concat([attributes, simple_calculations, aggregates])
      |> Enum.map(fn
        %Ash.Resource.Attribute{} = attr ->
          formatted_name =
            AshTypescript.FieldFormatter.format_field(
              attr.name,
              AshTypescript.Rpc.output_field_formatter()
            )

          if attr.allow_nil? do
            "  #{formatted_name}?: #{get_ts_type(attr)} | null;"
          else
            "  #{formatted_name}: #{get_ts_type(attr)};"
          end

        %Ash.Resource.Calculation{} = calc ->
          formatted_name =
            AshTypescript.FieldFormatter.format_field(
              calc.name,
              AshTypescript.Rpc.output_field_formatter()
            )

          if calc.allow_nil? do
            "  #{formatted_name}?: #{get_ts_type(calc)} | null;"
          else
            "  #{formatted_name}: #{get_ts_type(calc)};"
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

          formatted_name =
            AshTypescript.FieldFormatter.format_field(
              agg.name,
              AshTypescript.Rpc.output_field_formatter()
            )

          if agg.include_nil? do
            "  #{formatted_name}?: #{type} | null;"
          else
            "  #{formatted_name}: #{type};"
          end
      end)
      |> Enum.join("\n")

    """
    type #{resource_name}FieldsSchema = {
    #{fields}
    };
    """
  end

  def generate_calculated_fields_schema(resource) do
    resource_name = resource |> Module.split() |> List.last()

    calculations =
      resource
      |> Ash.Resource.Info.public_calculations()
      |> Enum.map(fn calc ->
        if calc.allow_nil? do
          "  #{calc.name}?: #{get_ts_type(calc)} | null;"
        else
          "  #{calc.name}: #{get_ts_type(calc)};"
        end
      end)

    if Enum.empty?(calculations) do
      "type #{resource_name}CalculatedFieldsSchema = {};"
    else
      """
      type #{resource_name}CalculatedFieldsSchema = {
      #{Enum.join(calculations, "\n")}
      };
      """
    end
  end

  def generate_aggregate_fields_schema(resource) do
    resource_name = resource |> Module.split() |> List.last()

    aggregates =
      resource
      |> Ash.Resource.Info.public_aggregates()
      |> Enum.map(fn agg ->
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

        if agg.include_nil? do
          "  #{agg.name}?: #{type} | null;"
        else
          "  #{agg.name}: #{type};"
        end
      end)

    if Enum.empty?(aggregates) do
      "type #{resource_name}AggregateFieldsSchema = {};"
    else
      """
      type #{resource_name}AggregateFieldsSchema = {
      #{Enum.join(aggregates, "\n")}
      };
      """
    end
  end

  def generate_relationship_schema(resource) do
    resource_name = resource |> Module.split() |> List.last()

    relationships =
      resource
      |> Ash.Resource.Info.public_relationships()
      |> Enum.map(fn rel ->
        related_resource_name = rel.destination |> Module.split() |> List.last()

        case rel.type do
          :belongs_to ->
            "  #{rel.name}: #{related_resource_name}Relationship;"

          :has_one ->
            "  #{rel.name}: #{related_resource_name}Relationship;"

          :has_many ->
            "  #{rel.name}: #{related_resource_name}ArrayRelationship;"

          :many_to_many ->
            "  #{rel.name}: #{related_resource_name}ArrayRelationship;"
        end
      end)

    if Enum.empty?(relationships) do
      "type #{resource_name}RelationshipSchema = {};"
    else
      """
      type #{resource_name}RelationshipSchema = {
      #{Enum.join(relationships, "\n")}
      };
      """
    end
  end

  def generate_relationship_schema(resource, allowed_resources) do
    resource_name = resource |> Module.split() |> List.last()

    # Get traditional relationships
    relationships =
      resource
      |> Ash.Resource.Info.public_relationships()
      |> Enum.filter(fn rel ->
        # Only include relationships to allowed resources
        Enum.member?(allowed_resources, rel.destination)
      end)
      |> Enum.map(fn rel ->
        related_resource_name = rel.destination |> Module.split() |> List.last()

        case rel.type do
          :belongs_to ->
            "  #{rel.name}: #{related_resource_name}Relationship;"

          :has_one ->
            "  #{rel.name}: #{related_resource_name}Relationship;"

          :has_many ->
            "  #{rel.name}: #{related_resource_name}ArrayRelationship;"

          :many_to_many ->
            "  #{rel.name}: #{related_resource_name}ArrayRelationship;"
        end
      end)

    # Get embedded resources and add them to relationships
    embedded_resources =
      resource
      |> Ash.Resource.Info.public_attributes()
      |> Enum.filter(fn attr ->
        case attr.type do
          embedded_type when is_atom(embedded_type) ->
            is_embedded_resource?(embedded_type) and
              Enum.member?(allowed_resources, embedded_type)

          {:array, embedded_type} when is_atom(embedded_type) ->
            is_embedded_resource?(embedded_type) and
              Enum.member?(allowed_resources, embedded_type)

          _ ->
            false
        end
      end)
      |> Enum.map(fn attr ->
        embedded_resource_name =
          case attr.type do
            embedded_type when is_atom(embedded_type) ->
              embedded_type |> Module.split() |> List.last()

            {:array, embedded_type} when is_atom(embedded_type) ->
              embedded_type |> Module.split() |> List.last()
          end

        # Apply field formatting to embedded resource field names
        formatted_attr_name =
          AshTypescript.FieldFormatter.format_field(
            attr.name,
            AshTypescript.Rpc.output_field_formatter()
          )

        case attr.type do
          embedded_type when is_atom(embedded_type) ->
            "  #{formatted_attr_name}: #{embedded_resource_name}Embedded;"

          {:array, _embedded_type} ->
            "  #{formatted_attr_name}: #{embedded_resource_name}ArrayEmbedded;"
        end
      end)

    # Combine relationships and embedded resources
    all_relations = relationships ++ embedded_resources

    if Enum.empty?(all_relations) do
      "type #{resource_name}RelationshipSchema = {};"
    else
      """
      type #{resource_name}RelationshipSchema = {
      #{Enum.join(all_relations, "\n")}
      };
      """
    end
  end

  def generate_unions_schema(resource) do
    resource_name = resource |> Module.split() |> List.last()

    # Find all union attributes in the resource
    union_attributes =
      resource
      |> Ash.Resource.Info.public_attributes()
      |> Enum.filter(fn attr ->
        case attr.type do
          Ash.Type.Union -> true
          {:array, Ash.Type.Union} -> true
          :union -> true
          {:array, :union} -> true
          _ -> false
        end
      end)

    if Enum.empty?(union_attributes) do
      "type #{resource_name}UnionsSchema = {};"
    else
      union_fields =
        union_attributes
        |> Enum.map(fn attr ->
          formatted_name =
            AshTypescript.FieldFormatter.format_field(
              attr.name,
              AshTypescript.Rpc.output_field_formatter()
            )

          # Generate the union field selection type - this allows either primitive strings or complex member objects
          "  #{formatted_name}: Record<string, any>;"
        end)
        |> Enum.join("\n")

      """
      type #{resource_name}UnionsSchema = {
      #{union_fields}
      };
      """
    end
  end


  def generate_resource_schema(resource) do
    resource_name = resource |> Module.split() |> List.last()

    """
    export type #{resource_name}ResourceSchema = {
      fields: #{resource_name}FieldsSchema;
      relationships: #{resource_name}RelationshipSchema;
      complexCalculations: #{resource_name}ComplexCalculationsSchema;
      unions: #{resource_name}UnionsSchema;
      __complexCalculationsInternal: __#{resource_name}ComplexCalculationsInternal;
    };
    """
  end

  def generate_input_schema(resource) do
    resource_name = resource |> Module.split() |> List.last()

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
      embedded_type when is_atom(embedded_type) and not is_nil(embedded_type) ->
        if is_embedded_resource?(embedded_type) do
          # Handle direct embedded resource types (e.g., attribute :metadata, TodoMetadata)
          resource_name = embedded_type |> Module.split() |> List.last()
          "#{resource_name}InputSchema"
        else
          # For all other atomic types, use the regular type mapping
          get_ts_type(attr)
        end

      {:array, embedded_type} when is_atom(embedded_type) ->
        if is_embedded_resource?(embedded_type) do
          # Handle array of embedded resources (e.g., attribute :metadata_history, {:array, TodoMetadata})
          resource_name = embedded_type |> Module.split() |> List.last()
          "Array<#{resource_name}InputSchema>"
        else
          # Handle regular array types
          inner_ts = get_ts_input_type(%{type: embedded_type, constraints: []})
          "Array<#{inner_ts}>"
        end

      Ash.Type.Union ->
        # Handle union types in input - use InputSchema for embedded resources
        constraints = Map.get(attr, :constraints, [])

        case Keyword.get(constraints, :types) do
          nil -> "any"
          types -> build_union_input_type(types)
        end

      _ ->
        # For all other types, use the regular type mapping
        get_ts_type(attr)
    end
  end

  def get_ts_type(type_and_constraints, select_and_loads \\ nil)
  def get_ts_type(:count, _), do: "number"
  def get_ts_type(:sum, _), do: "number"
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
          resource_name = instance_of |> Module.split() |> List.last()
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
        resource_name = type |> Module.split() |> List.last()
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
        optional = if allow_nil, do: "?", else: ""
        "#{formatted_field_name}#{optional}: #{field_type}"
      end)
      |> Enum.join(", ")

    "{#{field_types}}"
  end

  def build_union_type(types) do
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
      "" -> "any"
      properties -> "{ #{properties} }"
    end
  end

  # Special function for union member types - uses FieldsSchema for embedded resources
  defp get_union_member_type(%{type: type, constraints: constraints}) do
    cond do
      is_embedded_resource?(type) ->
        # For union members, use FieldsSchema instead of ResourceSchema
        resource_name = type |> Module.split() |> List.last()
        "#{resource_name}FieldsSchema"

      # For all other types, use the regular get_ts_type function
      true ->
        get_ts_type(%{type: type, constraints: constraints})
    end
  end

  # Special function for union member input types - uses InputSchema for embedded resources
  defp get_union_member_input_type(%{type: type, constraints: constraints}) do
    cond do
      is_embedded_resource?(type) ->
        # For union member inputs, use InputSchema instead of FieldsSchema
        resource_name = type |> Module.split() |> List.last()
        "#{resource_name}InputSchema"

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
          "  #{formatted_field}?: #{get_ts_type(attr)} | null;"
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
          "  #{formatted_field}?: #{get_ts_type(calc)} | null;"
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
          "  #{formatted_field}?: #{type} | null;"
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

  defp is_resource_calculation?(calc) do
    case calc.type do
      Ash.Type.Struct ->
        constraints = calc.constraints || []
        instance_of = Keyword.get(constraints, :instance_of)
        instance_of != nil and Ash.Resource.Info.resource?(instance_of)

      {:array, Ash.Type.Struct} ->
        constraints = calc.constraints || []
        items_constraints = Keyword.get(constraints, :items, [])
        instance_of = Keyword.get(items_constraints, :instance_of)
        instance_of != nil and Ash.Resource.Info.resource?(instance_of)

      Ash.Type.Map ->
        constraints = calc.constraints || []
        fields = Keyword.get(constraints, :fields)
        # Maps with field constraints need field selection
        fields != nil

      _ ->
        false
    end
  end

  # Determine if a return type is complex (struct with fields or map with field constraints)
  defp is_complex_return_type(Ash.Type.Struct, constraints) do
    instance_of = Keyword.get(constraints, :instance_of)
    fields = Keyword.get(constraints, :fields)

    # Complex if it's a resource instance or has field definitions
    instance_of != nil or fields != nil
  end

  defp is_complex_return_type(Ash.Type.Map, constraints) do
    fields = Keyword.get(constraints, :fields)
    # Complex if it has field constraints
    fields != nil
  end

  defp is_complex_return_type(_, _), do: false

  # Generate schema for complex calculations
  def generate_complex_calculations_schema(resource) do
    resource_name = resource |> Module.split() |> List.last()

    complex_calculations =
      resource
      |> Ash.Resource.Info.public_calculations()
      |> Enum.reject(&is_simple_calculation/1)

    # User-facing schema (what users configure)
    user_calculations =
      complex_calculations
      |> Enum.map(fn calc ->
        arguments_type = generate_calculation_arguments_type(calc)

        args_field =
          AshTypescript.FieldFormatter.format_field(
            :args,
            AshTypescript.Rpc.output_field_formatter()
          )

        # Only include fields for calculations that return resources
        if is_resource_calculation?(calc) do
          fields_type = generate_calculation_fields_type(calc)

          """
          #{calc.name}: {
            #{args_field}: #{arguments_type};
            fields: #{fields_type};
          };
          """
        else
          """
          #{calc.name}: {
            #{args_field}: #{arguments_type};
          };
          """
        end
      end)

    # Internal schema with return types for inference
    internal_calculations =
      complex_calculations
      |> Enum.map(fn calc ->
        arguments_type = generate_calculation_arguments_type(calc)
        return_type = get_ts_type(calc)

        args_field =
          AshTypescript.FieldFormatter.format_field(
            :args,
            AshTypescript.Rpc.output_field_formatter()
          )

        # Only include fields for calculations that return resources
        if is_resource_calculation?(calc) do
          fields_type = generate_calculation_fields_type(calc)

          """
          #{calc.name}: {
            #{args_field}: #{arguments_type};
            fields: #{fields_type};
            __returnType: #{return_type};
          };
          """
        else
          """
          #{calc.name}: {
            #{args_field}: #{arguments_type};
            __returnType: #{return_type};
          };
          """
        end
      end)

    user_schema =
      if Enum.empty?(user_calculations) do
        "type #{resource_name}ComplexCalculationsSchema = {};"
      else
        """
        type #{resource_name}ComplexCalculationsSchema = {
        #{Enum.join(user_calculations, "\n")}
        };
        """
      end

    internal_schema =
      if Enum.empty?(internal_calculations) do
        "type __#{resource_name}ComplexCalculationsInternal = {};"
      else
        """
        type __#{resource_name}ComplexCalculationsInternal = {
        #{Enum.join(internal_calculations, "\n")}
        };
        """
      end

    """
    #{user_schema}

    #{internal_schema}
    """
  end

  # Generate the arguments type for a calculation
  defp generate_calculation_arguments_type(calc) do
    if Enum.empty?(calc.arguments) do
      "{}"
    else
      args =
        calc.arguments
        |> Enum.map(fn arg ->
          optional = arg.allow_nil? || arg.default != nil

          formatted_name =
            AshTypescript.FieldFormatter.format_field(
              arg.name,
              AshTypescript.Rpc.output_field_formatter()
            )

          "#{formatted_name}#{if optional, do: "?", else: ""}: #{get_ts_type(arg)};"
        end)
        |> Enum.join("\n    ")

      "{\n    #{args}\n  }"
    end
  end

  # Generate the fields type for selecting from a calculation result
  defp generate_calculation_fields_type(%Ash.Resource.Calculation{
         type: Ash.Type.Struct,
         constraints: constraints
       }) do
    instance_of = Keyword.get(constraints, :instance_of)
    fields = Keyword.get(constraints, :fields)

    cond do
      instance_of != nil ->
        # If it's a resource instance, use field selection for that resource
        resource_name = instance_of |> Module.split() |> List.last()
        "UnifiedFieldSelection<#{resource_name}ResourceSchema>[]"

      fields != nil ->
        # If it has field definitions, use the field names as string literals
        field_names =
          Keyword.keys(fields)
          |> Enum.map(&to_string/1)
          |> Enum.map(&"\"#{&1}\"")
          |> Enum.join(" | ")

        "(#{field_names})[]"

      true ->
        "string[]"
    end
  end

  defp generate_calculation_fields_type(%Ash.Resource.Calculation{
         type: Ash.Type.Map,
         constraints: constraints
       }) do
    fields = Keyword.get(constraints, :fields)

    if fields do
      field_names =
        Keyword.keys(fields)
        |> Enum.map(&to_string/1)
        |> Enum.map(&"\"#{&1}\"")
        |> Enum.join(" | ")

      "(#{field_names})[]"
    else
      "string[]"
    end
  end

  defp generate_calculation_fields_type(_calc) do
    "string[]"
  end

end
