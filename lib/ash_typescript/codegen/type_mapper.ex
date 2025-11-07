# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.TypeMapper do
  @moduledoc """
  Maps Ash types to TypeScript types for both output and input schemas.
  """

  alias AshTypescript.Codegen.Helpers
  alias AshTypescript.TypeSystem.Introspection

  @doc """
  Maps an Ash type to a TypeScript type for input schemas.
  Handles embedded resources, unions, maps, and primitive types.
  """
  def get_ts_input_type(%{type: type} = attr) do
    case type do
      Ash.Type.Map ->
        constraints = Map.get(attr, :constraints, [])

        case Keyword.get(constraints, :fields) do
          nil -> AshTypescript.untyped_map_type()
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
          Introspection.is_embedded_resource?(embedded_type) ->
            resource_name = Helpers.build_resource_type_name(embedded_type)
            "#{resource_name}InputSchema"

          Introspection.is_typed_struct?(embedded_type) ->
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
        if Introspection.is_embedded_resource?(embedded_type) do
          resource_name = Helpers.build_resource_type_name(embedded_type)
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

  @doc """
  Maps an Ash type to a TypeScript type for output schemas.
  Second parameter is optional select_and_loads for filtering fields.
  """
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
  def get_ts_type(%{type: :map}, _), do: AshTypescript.untyped_map_type()

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
      nil -> AshTypescript.untyped_map_type()
      fields -> build_map_type(fields, select, nil)
    end
  end

  def get_ts_type(%{type: Ash.Type.Map}, _), do: AshTypescript.untyped_map_type()

  def get_ts_type(%{type: Ash.Type.Keyword, constraints: constraints}, _)
      when constraints != [] do
    case Keyword.get(constraints, :fields) do
      nil -> AshTypescript.untyped_map_type()
      fields -> build_map_type(fields, nil, nil)
    end
  end

  def get_ts_type(%{type: Ash.Type.Keyword, constraints: constraints}, _) do
    case Keyword.get(constraints, :fields) do
      nil -> AshTypescript.untyped_map_type()
      fields -> build_map_type(fields, nil, nil)
    end
  end

  def get_ts_type(%{type: Ash.Type.Tuple, constraints: constraints}, _) do
    case Keyword.get(constraints, :fields) do
      nil -> AshTypescript.untyped_map_type()
      fields -> build_map_type(fields, nil, nil)
    end
  end

  def get_ts_type(%{type: Ash.Type.Struct, constraints: constraints}, select_and_loads) do
    instance_of = Keyword.get(constraints, :instance_of)
    fields = Keyword.get(constraints, :fields)

    cond do
      instance_of != nil and Introspection.is_typed_struct?(instance_of) ->
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
            typed_struct_fields = Introspection.get_typed_struct_fields(instance_of)

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
        resource_name = Helpers.build_resource_type_name(instance_of)
        "#{resource_name}ResourceSchema"

      instance_of != nil ->
        build_resource_type(instance_of, select_and_loads)

      fields != nil ->
        build_map_type(fields)

      true ->
        AshTypescript.untyped_map_type()
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
      type_override = get_type_mapping_override(type) ->
        type_override

      is_custom_type?(type) ->
        type.typescript_type_name()

      Introspection.is_embedded_resource?(type) ->
        resource_name = Helpers.build_resource_type_name(type)
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

  @doc """
  Builds a TypeScript map type with optional field filtering and name mapping.
  """
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

  @doc """
  Builds an input schema type for a TypedStruct module.
  """
  def build_typed_struct_input_type(typed_struct_module) do
    fields = Introspection.get_typed_struct_fields(typed_struct_module)

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

  @doc """
  Builds a union type with metadata for field selection.
  """
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
      Introspection.is_typed_struct?(type) ->
        resource_name = Helpers.build_resource_type_name(type)
        "#{resource_name}TypedStructFieldSelection"

      Introspection.is_embedded_resource?(type) ->
        resource_name = Helpers.build_resource_type_name(type)
        "#{resource_name}ResourceSchema"

      true ->
        get_ts_type(%{type: type, constraints: constraints})
    end
  end

  defp get_union_member_input_type(%{type: type, constraints: constraints}) do
    cond do
      Introspection.is_typed_struct?(type) ->
        resource_name = Helpers.build_resource_type_name(type)
        "#{resource_name}TypedStructInputSchema"

      Introspection.is_embedded_resource?(type) ->
        resource_name = Helpers.build_resource_type_name(type)
        "#{resource_name}InputSchema"

      type == Ash.Type.Map ->
        get_ts_input_type(%{type: type, constraints: constraints})

      true ->
        get_ts_type(%{type: type, constraints: constraints})
    end
  end

  @doc """
  Builds an input type for unions (discriminated union syntax).
  """
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

  defp generate_primitive_fields_union(fields) do
    if Enum.empty?(fields) do
      "never"
    else
      fields
      |> Enum.map_join(
        " | ",
        fn field_name ->
          formatted =
            AshTypescript.FieldFormatter.format_field(
              field_name,
              AshTypescript.Rpc.output_field_formatter()
            )

          "\"#{formatted}\""
        end
      )
    end
  end

  @doc """
  Builds a resource type for non-Ash resources.
  """
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

  @doc """
  Gets the TypeScript field specification for a resource field.
  """
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
              |> Helpers.lookup_aggregate_type(agg.relationship_path, agg.field)
              |> get_ts_type()

            :first ->
              resource
              |> Helpers.lookup_aggregate_type(agg.relationship_path, agg.field)
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

  defp get_type_mapping_override(type) when is_atom(type) do
    type_mapping_overrides = AshTypescript.type_mapping_overrides()

    case List.keyfind(type_mapping_overrides, type, 0) do
      {^type, ts_type} -> ts_type
      nil -> nil
    end
  end

  defp get_type_mapping_override(_type), do: nil

  defp is_custom_type?(type) do
    is_atom(type) and
      Code.ensure_loaded?(type) and
      function_exported?(type, :typescript_type_name, 0) and
      Spark.implements_behaviour?(type, Ash.Type)
  end
end
