# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.TypeMapper do
  @moduledoc """
  Maps Ash types to TypeScript types using unified type-driven dispatch.

  This module provides a unified approach to type mapping with a single core
  dispatcher (`map_type/3`) that handles both input and output directions.
  """

  alias AshTypescript.Codegen.Helpers
  alias AshTypescript.TypeSystem.Introspection

  # ─────────────────────────────────────────────────────────────────
  # Type Constants
  # ─────────────────────────────────────────────────────────────────

  @primitives %{
    Ash.Type.String => "string",
    Ash.Type.CiString => "string",
    Ash.Type.Integer => "number",
    Ash.Type.Float => "number",
    Ash.Type.Decimal => "Decimal",
    Ash.Type.Boolean => "boolean",
    Ash.Type.UUID => "UUID",
    Ash.Type.UUIDv7 => "UUIDv7",
    Ash.Type.Date => "AshDate",
    Ash.Type.Time => "Time",
    Ash.Type.TimeUsec => "TimeUsec",
    Ash.Type.DateTime => "DateTime",
    Ash.Type.UtcDatetime => "UtcDateTime",
    Ash.Type.UtcDatetimeUsec => "UtcDateTimeUsec",
    Ash.Type.NaiveDatetime => "NaiveDateTime",
    Ash.Type.Duration => "Duration",
    Ash.Type.DurationName => "DurationName",
    Ash.Type.Binary => "Binary",
    Ash.Type.UrlEncodedBinary => "UrlEncodedBinary",
    Ash.Type.File => "File",
    Ash.Type.Function => "Function",
    Ash.Type.Term => "any",
    Ash.Type.Vector => "number[]",
    Ash.Type.Module => "ModuleName"
  }

  @atom_primitives %{
    :string => "string",
    :integer => "number",
    :float => "number",
    :decimal => "Decimal",
    :boolean => "boolean",
    :uuid => "UUID",
    :date => "AshDate",
    :time => "Time",
    :datetime => "UtcDateTime",
    :naive_datetime => "NaiveDateTime",
    :utc_datetime => "UtcDateTime",
    :utc_datetime_usec => "UtcDateTimeUsec",
    :duration => "Duration",
    :binary => "Binary",
    :map => nil,
    :sum => "number",
    :count => "number"
  }

  @aggregate_kinds %{
    :count => "number",
    :sum => "number",
    :avg => "number",
    :exists => "boolean",
    :min => "any",
    :max => "any",
    :first => "any",
    :last => "any",
    :list => "any[]",
    :custom => "any"
  }

  @aggregate_atoms Map.keys(@aggregate_kinds)

  # ─────────────────────────────────────────────────────────────────
  # Public API (backward compatible)
  # ─────────────────────────────────────────────────────────────────

  @type direction :: :input | :output

  @doc """
  Maps an Ash type to a TypeScript type for input schemas.
  Backward compatible wrapper around map_type/3.
  """
  def get_ts_input_type(%{type: type, constraints: constraints}) do
    map_type(type, constraints, :input)
  end

  @doc """
  Maps an Ash type to a TypeScript type for output schemas.
  Backward compatible wrapper around map_type/3.
  """
  def get_ts_type(type_and_constraints, select_and_loads \\ nil)

  # Handle aggregate kind atoms directly
  def get_ts_type(kind, _) when is_atom(kind) and kind in @aggregate_atoms do
    Map.get(@aggregate_kinds, kind)
  end

  # Handle nil type
  def get_ts_type(%{type: nil}, _), do: "null"

  # Handle maps without constraints key (legacy format)
  def get_ts_type(%{type: type} = attr, select_and_loads)
      when not is_map_key(attr, :constraints) do
    get_ts_type(%{type: type, constraints: []}, select_and_loads)
  end

  # Handle maps with type/constraints
  def get_ts_type(%{type: type, constraints: constraints}, select_and_loads) do
    # If select_and_loads provided, use specialized path for field filtering
    if select_and_loads do
      map_type_with_selection(type, constraints, select_and_loads)
    else
      map_type(type, constraints, :output)
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Core Dispatcher
  # ─────────────────────────────────────────────────────────────────

  @doc """
  Maps an Ash type to a TypeScript type string.

  ## Parameters
  - `type` - The Ash type (atom, tuple, or map with :type/:constraints)
  - `constraints` - Type constraints
  - `direction` - :input or :output

  ## Returns
  A TypeScript type string.
  """
  @spec map_type(atom() | tuple(), keyword(), direction()) :: String.t()
  def map_type(type, constraints, direction)

  # Nil type
  def map_type(nil, _constraints, _direction), do: "null"

  def map_type(type, constraints, direction) do
    cond do
      # Arrays - check before unwrapped handling since arrays have special tuple format
      match?({:array, _}, type) ->
        map_array(type, constraints, direction)

      # Primitives - check original type FIRST (before unwrapping) to preserve specific types
      # like UtcDatetimeUsec that would otherwise unwrap to DateTime
      primitive_ts = map_primitive(type, constraints) ->
        primitive_ts

      # Now unwrap NewTypes for complex type handling
      true ->
        {unwrapped_type, full_constraints} = Introspection.unwrap_new_type(type, constraints)
        map_complex_type(unwrapped_type, full_constraints, direction)
    end
  end

  # Handle complex (non-primitive) types after NewType unwrapping
  defp map_complex_type(unwrapped_type, full_constraints, direction) do
    cond do
      # Check primitives again for unwrapped types (e.g., custom NewTypes wrapping primitives)
      primitive_ts = map_primitive(unwrapped_type, full_constraints) ->
        primitive_ts

      # Ash Resources (embedded)
      Introspection.is_embedded_resource?(unwrapped_type) ->
        map_resource(unwrapped_type, direction)

      # Ash.Type.Struct with instance_of or fields
      unwrapped_type == Ash.Type.Struct ->
        map_struct(full_constraints, direction)

      # Typed containers (Map, Keyword, Tuple with fields)
      unwrapped_type in [Ash.Type.Map, Ash.Type.Keyword, Ash.Type.Tuple] ->
        map_typed_container(unwrapped_type, full_constraints, direction)

      # Union
      unwrapped_type == Ash.Type.Union ->
        map_union(full_constraints, direction)

      # Enum types
      is_atom(unwrapped_type) and Spark.implements_behaviour?(unwrapped_type, Ash.Type.Enum) ->
        map_enum(unwrapped_type)

      # Custom types with typescript_type_name
      is_custom_type?(unwrapped_type) ->
        unwrapped_type.typescript_type_name()

      # Type mapping overrides
      type_override = get_type_mapping_override(unwrapped_type) ->
        type_override

      # Third-party types
      unwrapped_type == AshDoubleEntry.ULID ->
        "ULID"

      unwrapped_type == AshMoney.Types.Money ->
        "Money"

      unwrapped_type == AshPostgres.Ltree ->
        map_ltree(full_constraints)

      # Fallback
      true ->
        raise "unsupported type #{inspect(unwrapped_type)}"
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Type-Specific Handlers
  # ─────────────────────────────────────────────────────────────────

  defp map_primitive(type, constraints) do
    cond do
      # Module-based primitives
      Map.has_key?(@primitives, type) ->
        Map.get(@primitives, type)

      # Atom-based primitives (from Ecto)
      Map.has_key?(@atom_primitives, type) ->
        case Map.get(@atom_primitives, type) do
          nil -> AshTypescript.untyped_map_type()
          value -> value
        end

      # Aggregate kinds
      Map.has_key?(@aggregate_kinds, type) ->
        Map.get(@aggregate_kinds, type)

      # Ash.Type.Atom with one_of constraint
      type == Ash.Type.Atom ->
        case Keyword.get(constraints, :one_of) do
          nil -> "string"
          values -> values |> Enum.map_join(" | ", &"\"#{to_string(&1)}\"")
        end

      # Not a primitive
      true ->
        nil
    end
  end

  defp map_ltree(constraints) do
    if Keyword.get(constraints, :escape?, false) do
      "AshPostgresLtreeArray"
    else
      "AshPostgresLtreeFlexible"
    end
  end

  defp map_array({:array, inner_type}, constraints, direction) do
    items_constraints = Keyword.get(constraints, :items, [])

    # Special handling for Struct with instance_of inside arrays
    cond do
      inner_type == Ash.Type.Union ->
        case Keyword.get(items_constraints, :types) do
          nil -> "Array<any>"
          types -> "Array<#{build_union_type_for_direction(types, direction)}>"
        end

      inner_type == Ash.Type.Struct ->
        instance_of = Keyword.get(items_constraints, :instance_of)

        if instance_of && Spark.Dsl.is?(instance_of, Ash.Resource) do
          map_resource(instance_of, direction) |> wrap_array()
        else
          inner_ts = map_type(inner_type, items_constraints, direction)
          wrap_array(inner_ts)
        end

      Introspection.is_embedded_resource?(inner_type) ->
        map_resource(inner_type, direction) |> wrap_array()

      true ->
        inner_ts = map_type(inner_type, items_constraints, direction)
        wrap_array(inner_ts)
    end
  end

  defp wrap_array(inner_type), do: "Array<#{inner_type}>"

  defp map_resource(resource, direction) do
    resource_name = Helpers.build_resource_type_name(resource)
    suffix = type_suffix(direction)
    "#{resource_name}#{suffix}"
  end

  defp type_suffix(:input), do: "InputSchema"
  defp type_suffix(:output), do: "ResourceSchema"

  defp map_struct(constraints, direction) do
    instance_of = Keyword.get(constraints, :instance_of)
    fields = Keyword.get(constraints, :fields)

    cond do
      # Has fields constraint - treat as typed container
      fields != nil ->
        field_name_mappings = get_field_name_mappings(Ash.Type.Struct, constraints)

        case direction do
          :input -> build_field_input_type(fields, field_name_mappings)
          :output -> build_map_type(fields, nil, field_name_mappings)
        end

      # instance_of pointing to Ash Resource
      instance_of && Ash.Resource.Info.resource?(instance_of) ->
        map_resource(instance_of, direction)

      # instance_of pointing to TypedStruct (output only uses this)
      instance_of && direction == :output ->
        build_resource_type(instance_of, nil)

      # Fallback to untyped map
      true ->
        AshTypescript.untyped_map_type()
    end
  end

  defp map_typed_container(type, constraints, direction) do
    fields = Keyword.get(constraints, :fields, [])

    if fields == [] do
      AshTypescript.untyped_map_type()
    else
      field_name_mappings = get_field_name_mappings(type, constraints)

      case direction do
        :input -> build_field_input_type(fields, field_name_mappings)
        :output -> build_map_type(fields, nil, field_name_mappings)
      end
    end
  end

  defp map_union(constraints, direction) do
    case Keyword.get(constraints, :types) do
      nil -> "any"
      types -> build_union_type_for_direction(types, direction)
    end
  end

  defp build_union_type_for_direction(types, :input), do: build_union_input_type(types)
  defp build_union_type_for_direction(types, :output), do: build_union_type(types)

  defp map_union_member(type, constraints, direction) do
    cond do
      # Type with fields and instance_of (TypedStruct)
      Keyword.has_key?(constraints, :fields) and Keyword.has_key?(constraints, :instance_of) ->
        instance_of = Keyword.get(constraints, :instance_of)
        resource_name = Helpers.build_resource_type_name(instance_of)

        case direction do
          :input -> map_type(type, constraints, :input)
          :output -> "#{resource_name}TypedStructFieldSelection"
        end

      # Embedded resource
      Introspection.is_embedded_resource?(type) ->
        map_resource(type, direction)

      # Other types - recurse
      true ->
        map_type(type, constraints, direction)
    end
  end

  defp map_enum(type) when is_atom(type) do
    Enum.map_join(type.values(), " | ", &"\"#{to_string(&1)}\"")
  rescue
    _ -> "string"
  end

  defp map_enum(_), do: "string"

  # ─────────────────────────────────────────────────────────────────
  # Selection-Aware Type Mapping (for output with select_and_loads)
  # ─────────────────────────────────────────────────────────────────

  defp map_type_with_selection(type, constraints, select_and_loads) do
    # Unwrap NewTypes first
    {unwrapped_type, full_constraints} = Introspection.unwrap_new_type(type, constraints)

    cond do
      # Struct with instance_of - use build_resource_type with selection
      unwrapped_type == Ash.Type.Struct and Keyword.has_key?(full_constraints, :instance_of) ->
        instance_of = Keyword.get(full_constraints, :instance_of)

        if Spark.Dsl.is?(instance_of, Ash.Resource) do
          resource_name = Helpers.build_resource_type_name(instance_of)
          "#{resource_name}ResourceSchema"
        else
          build_resource_type(instance_of, select_and_loads)
        end

      # Map with fields - use build_map_type with selection
      unwrapped_type == Ash.Type.Map and Keyword.has_key?(full_constraints, :fields) ->
        fields = Keyword.get(full_constraints, :fields)
        field_name_mappings = get_field_name_mappings(Ash.Type.Map, full_constraints)
        build_map_type(fields, select_and_loads, field_name_mappings)

      # Other types - fall back to regular mapping
      true ->
        map_type(type, constraints, :output)
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Type Builders
  # ─────────────────────────────────────────────────────────────────

  defp build_field_input_type(fields, field_name_mappings) do
    field_types =
      fields
      |> Enum.map_join(", ", fn {field_name, field_config} ->
        field_type = map_type(field_config[:type], field_config[:constraints] || [], :input)

        # Apply field name mapping if available
        mapped_field_name =
          if field_name_mappings && Keyword.has_key?(field_name_mappings, field_name) do
            Keyword.get(field_name_mappings, field_name)
          else
            field_name
          end

        formatted_field_name =
          AshTypescript.FieldFormatter.format_field_name(
            mapped_field_name,
            AshTypescript.Rpc.output_field_formatter()
          )

        allow_nil = Keyword.get(field_config, :allow_nil?, true)
        optional_marker = if allow_nil, do: "?", else: ""
        null_type = if allow_nil, do: " | null", else: ""
        "#{formatted_field_name}#{optional_marker}: #{field_type}#{null_type}"
      end)

    "{#{field_types}}"
  end

  defp get_field_name_mappings(type, constraints) do
    instance_of = Keyword.get(constraints, :instance_of)

    cond do
      # Check instance_of first (for Ash.Type.Struct with instance_of constraint)
      instance_of && function_exported?(instance_of, :typescript_field_names, 0) ->
        instance_of.typescript_field_names()

      # Check the type itself (for NewTypes used directly as attribute types)
      is_atom(type) && not is_nil(type) && function_exported?(type, :typescript_field_names, 0) ->
        type.typescript_field_names()

      true ->
        nil
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
        field_type = map_type(field_config[:type], field_config[:constraints] || [], :output)

        formatted_field_name =
          if field_name_mappings && Keyword.has_key?(field_name_mappings, field_name) do
            Keyword.get(field_name_mappings, field_name) |> to_string()
          else
            field_name
          end
          |> AshTypescript.FieldFormatter.format_field_name(
            AshTypescript.Rpc.output_field_formatter()
          )

        allow_nil = Keyword.get(field_config, :allow_nil?, true)
        optional = if allow_nil, do: " | null", else: ""
        "#{formatted_field_name}: #{field_type}#{optional}"
      end)

    primitive_fields_union =
      if Enum.empty?(selected_fields) do
        "never"
      else
        primitive_only_fields =
          selected_fields
          |> Enum.filter(fn {_field_name, field_config} ->
            # Only include truly primitive fields, not nested TypedMaps
            !is_nested_typed_map?(field_config)
          end)

        if Enum.empty?(primitive_only_fields) do
          "never"
        else
          primitive_only_fields
          |> Enum.map_join(" | ", fn {field_name, _field_config} ->
            formatted_field_name =
              if field_name_mappings && Keyword.has_key?(field_name_mappings, field_name) do
                Keyword.get(field_name_mappings, field_name) |> to_string()
              else
                field_name
              end
              |> AshTypescript.FieldFormatter.format_field_name(
                AshTypescript.Rpc.output_field_formatter()
              )

            "\"#{formatted_field_name}\""
          end)
        end
      end

    "{#{field_types}, __type: \"TypedMap\", __primitiveFields: #{primitive_fields_union}}"
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
          AshTypescript.FieldFormatter.format_field_name(
            type_name,
            AshTypescript.Rpc.output_field_formatter()
          )

        ts_type = map_union_member(type_config[:type], type_config[:constraints] || [], :output)

        "#{formatted_name}?: #{ts_type}"
      end)

    case member_properties do
      "" -> "{ __type: \"Union\"; __primitiveFields: #{primitive_union}; }"
      properties -> "{ __type: \"Union\"; __primitiveFields: #{primitive_union}; #{properties}; }"
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
          AshTypescript.FieldFormatter.format_field_name(
            type_name,
            AshTypescript.Rpc.output_field_formatter()
          )

        ts_type = map_union_member(type_config[:type], type_config[:constraints] || [], :input)

        "{ #{formatted_name}: #{ts_type} }"
      end)

    case member_objects do
      "" -> "any"
      objects -> objects
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Union Primitive Detection (Consolidated)
  # ─────────────────────────────────────────────────────────────────

  @doc """
  Determines if a union member is a "primitive" (no selectable fields).
  """
  def is_primitive_union_member?(type, constraints) do
    cond do
      # Types with field constraints are not primitive
      Keyword.has_key?(constraints, :fields) ->
        false

      # Struct with instance_of is not primitive
      type == Ash.Type.Struct and Keyword.has_key?(constraints, :instance_of) ->
        false

      # :struct with instance_of is not primitive
      type == :struct and Keyword.has_key?(constraints, :instance_of) ->
        false

      # Union is not primitive
      type == Ash.Type.Union ->
        false

      # Embedded resources are not primitive
      is_atom(type) and Introspection.is_embedded_resource?(type) ->
        false

      # Everything else is primitive
      true ->
        true
    end
  end

  defp get_union_primitive_fields(union_types) do
    union_types
    |> Enum.filter(fn {_name, config} ->
      type = Keyword.get(config, :type)
      constraints = Keyword.get(config, :constraints, [])
      is_primitive_union_member?(type, constraints)
    end)
    |> Enum.map(fn {name, _} -> name end)
  end

  @doc """
  Generates a TypeScript union of primitive field names.
  """
  def generate_primitive_fields_union(fields) do
    if Enum.empty?(fields) do
      "never"
    else
      fields
      |> Enum.map_join(
        " | ",
        fn field_name ->
          formatted =
            AshTypescript.FieldFormatter.format_field_name(
              field_name,
              AshTypescript.Rpc.output_field_formatter()
            )

          "\"#{formatted}\""
        end
      )
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Resource Type Builder
  # ─────────────────────────────────────────────────────────────────

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
          AshTypescript.FieldFormatter.format_field_name(
            field,
            AshTypescript.Rpc.output_field_formatter()
          )

        ts_type = map_type(attr.type, attr.constraints, :output)

        if attr.allow_nil? do
          "  #{formatted_field}: #{ts_type} | null;"
        else
          "  #{formatted_field}: #{ts_type};"
        end

      %Ash.Resource.Calculation{} = calc ->
        formatted_field =
          AshTypescript.FieldFormatter.format_field_name(
            field,
            AshTypescript.Rpc.output_field_formatter()
          )

        ts_type = map_type(calc.type, calc.constraints, :output)

        if calc.allow_nil? do
          "  #{formatted_field}: #{ts_type} | null;"
        else
          "  #{formatted_field}: #{ts_type};"
        end

      %Ash.Resource.Aggregate{} = agg ->
        type =
          case agg.kind do
            :sum ->
              attr = Helpers.lookup_aggregate_type(resource, agg.relationship_path, agg.field)
              map_type(attr.type, attr.constraints, :output)

            :first ->
              attr = Helpers.lookup_aggregate_type(resource, agg.relationship_path, agg.field)
              map_type(attr.type, attr.constraints, :output)

            _ ->
              Map.get(@aggregate_kinds, agg.kind)
          end

        formatted_field =
          AshTypescript.FieldFormatter.format_field_name(
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

  # ─────────────────────────────────────────────────────────────────
  # Helpers
  # ─────────────────────────────────────────────────────────────────

  defp get_type_mapping_override(type) when is_atom(type) do
    type_mapping_overrides = AshTypescript.type_mapping_overrides()

    case List.keyfind(type_mapping_overrides, type, 0) do
      {^type, ts_type} -> ts_type
      nil -> nil
    end
  end

  defp get_type_mapping_override(_type), do: nil

  defp is_custom_type?(type), do: Introspection.is_custom_type?(type)

  # Helper to check if a field config represents a complex type that supports nested field selection
  # This includes: TypedMaps (maps with :fields), Unions, and NewTypes wrapping these
  defp is_nested_typed_map?(field_config) when is_list(field_config) do
    type = Keyword.get(field_config, :type)
    constraints = Keyword.get(field_config, :constraints, [])
    is_complex_field_type?(type, constraints)
  end

  defp is_nested_typed_map?(field_config) when is_map(field_config) do
    type = Map.get(field_config, :type)
    constraints = Map.get(field_config, :constraints, [])
    is_complex_field_type?(type, constraints)
  end

  defp is_nested_typed_map?(_), do: false

  # TypedMap: :map or Ash.Type.Map with :fields constraint
  defp is_complex_field_type?(:map, constraints) do
    Keyword.has_key?(constraints, :fields)
  end

  defp is_complex_field_type?(Ash.Type.Map, constraints) do
    Keyword.has_key?(constraints, :fields)
  end

  # Keyword and Tuple with :fields are also typed containers (generate TypedMap)
  defp is_complex_field_type?(Ash.Type.Keyword, constraints) do
    Keyword.has_key?(constraints, :fields)
  end

  defp is_complex_field_type?(Ash.Type.Tuple, constraints) do
    Keyword.has_key?(constraints, :fields)
  end

  # Union types are always complex
  defp is_complex_field_type?(Ash.Type.Union, _constraints), do: true

  # Arrays: check the inner type
  defp is_complex_field_type?({:array, inner_type}, constraints) do
    items_constraints = Keyword.get(constraints, :items, [])
    is_complex_field_type?(inner_type, items_constraints)
  end

  # NewTypes: unwrap and check the underlying type
  defp is_complex_field_type?(type, constraints) when is_atom(type) do
    if Code.ensure_loaded?(type) and Ash.Type.NewType.new_type?(type) do
      {inner_type, inner_constraints} = Introspection.unwrap_new_type(type, constraints)

      # If unwrapping changed the type, check the inner type
      if inner_type != type do
        is_complex_field_type?(inner_type, inner_constraints)
      else
        false
      end
    else
      false
    end
  end

  defp is_complex_field_type?(_type, _constraints), do: false
end
