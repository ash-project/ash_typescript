defmodule AshTypescript.TS.Codegen do
  def get_ts_type(type_and_constraints, select_and_loads \\ nil)
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
  def get_ts_type(%{type: Ash.Type.Decimal}, _), do: "string"
  def get_ts_type(%{type: Ash.Type.Boolean}, _), do: "boolean"
  def get_ts_type(%{type: Ash.Type.UUID}, _), do: "string"
  def get_ts_type(%{type: Ash.Type.UUIDv7}, _), do: "string"
  def get_ts_type(%{type: Ash.Type.Date}, _), do: "string"
  def get_ts_type(%{type: Ash.Type.Time}, _), do: "string"
  def get_ts_type(%{type: Ash.Type.TimeUsec}, _), do: "string"
  def get_ts_type(%{type: Ash.Type.UtcDatetime}, _), do: "string"
  def get_ts_type(%{type: Ash.Type.UtcDatetimeUsec}, _), do: "string"
  def get_ts_type(%{type: Ash.Type.DateTime}, _), do: "string"
  def get_ts_type(%{type: Ash.Type.NaiveDatetime}, _), do: "string"
  def get_ts_type(%{type: Ash.Type.Duration}, _), do: "string"
  def get_ts_type(%{type: Ash.Type.DurationName}, _), do: "string"
  def get_ts_type(%{type: Ash.Type.Binary}, _), do: "string"
  def get_ts_type(%{type: Ash.Type.UrlEncodedBinary}, _), do: "string"
  def get_ts_type(%{type: Ash.Type.File}, _), do: "File"
  def get_ts_type(%{type: Ash.Type.Function}, _), do: "Function"
  def get_ts_type(%{type: Ash.Type.Term}, _), do: "any"
  def get_ts_type(%{type: Ash.Type.Vector}, _), do: "number[]"
  def get_ts_type(%{type: Ash.Type.Module}, _), do: "string"

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
        build_resource_type(instance_of, select_and_loads)

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

  def get_ts_type(%{type: AshDoubleEntry.ULID}, _), do: "string"
  def get_ts_type(%{type: AshMoney.Types.Money}, _), do: "{currency: string, amount: string}"

  # Handle atom types (shorthand versions)
  def get_ts_type(%{type: :string}, _), do: "string"
  def get_ts_type(%{type: :integer}, _), do: "number"
  def get_ts_type(%{type: :float}, _), do: "number"
  def get_ts_type(%{type: :decimal}, _), do: "string"
  def get_ts_type(%{type: :boolean}, _), do: "boolean"
  def get_ts_type(%{type: :uuid}, _), do: "string"
  def get_ts_type(%{type: :date}, _), do: "string"
  def get_ts_type(%{type: :time}, _), do: "string"
  def get_ts_type(%{type: :datetime}, _), do: "string"
  def get_ts_type(%{type: :naive_datetime}, _), do: "string"
  def get_ts_type(%{type: :utc_datetime}, _), do: "string"
  def get_ts_type(%{type: :utc_datetime_usec}, _), do: "string"
  def get_ts_type(%{type: :binary}, _), do: "string"

  def get_ts_type(%{type: type, constraints: constraints} = attr, _) do
    cond do
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

        allow_nil = Keyword.get(field_config, :allow_nil?, true)
        optional = if allow_nil, do: "?", else: ""
        "#{field_name}#{optional}: #{field_type}"
      end)
      |> Enum.join(", ")

    "{#{field_types}}"
  end

  def build_union_type(types) do
    type_strings =
      types
      |> Enum.map(fn {_type_name, type_config} ->
        get_ts_type(%{type: type_config[:type], constraints: type_config[:constraints] || []})
      end)
      |> Enum.uniq()
      |> Enum.join(" | ")

    case type_strings do
      "" -> "any"
      single -> single
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
        if attr.allow_nil? do
          "  #{field}?: #{get_ts_type(attr)} | null;"
        else
          "  #{field}: #{get_ts_type(attr)};"
        end

      %Ash.Resource.Calculation{} = calc ->
        if calc.allow_nil? do
          "  #{field}?: #{get_ts_type(calc)} | null;"
        else
          "  #{field}: #{get_ts_type(calc)};"
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

        if agg.include_nil? do
          "  #{field}?: #{type} | null;"
        else
          "  #{field}: #{type};"
        end

      field ->
        throw("Unknown field type: #{inspect(field)}")
    end
  end

  def get_resource_field_spec({field_name, fields}, resource) do
    relationships = Ash.Resource.Info.public_relationships(resource)

    case Enum.find(relationships, &(&1.name == field_name)) do
      nil ->
        throw("Relationship not found on #{resource}: #{field_name}")

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
end
