# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.TypeMapper do
  @moduledoc """
  Maps Ash types to TypeScript types using unified type-driven dispatch.

  This module provides a unified approach to type mapping with a single core
  dispatcher (`map_type/3`) that handles both input and output directions.
  """

  alias AshTypescript.Codegen.Helpers

  # ─────────────────────────────────────────────────────────────────
  # Type Constants
  # ─────────────────────────────────────────────────────────────────

  # Kind → TypeScript type mapping for %AshApiSpec.Type{} dispatch.
  # Used as a fallback when the module isn't a direct Ash primitive
  # (e.g., NewTypes wrapping primitives).
  @kind_to_ts %{
    :string => "string",
    :ci_string => "string",
    :integer => "number",
    :float => "number",
    :decimal => "Decimal",
    :boolean => "boolean",
    :uuid => "UUID",
    :date => "AshDate",
    :time => "Time",
    :time_usec => "TimeUsec",
    :datetime => "DateTime",
    :utc_datetime => "UtcDateTime",
    :utc_datetime_usec => "UtcDateTimeUsec",
    :naive_datetime => "NaiveDateTime",
    :duration => "Duration",
    :binary => "Binary",
    :term => "any",
    :atom => "string",
    :unknown => "any"
  }

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
  def get_ts_input_type(%AshApiSpec.Field{type: type}) do
    map_type(type, [], :input)
  end

  def get_ts_input_type(%AshApiSpec.Argument{type: type}) do
    map_type(type, [], :input)
  end

  def get_ts_input_type(%{type: type, constraints: constraints}) do
    map_type(type, constraints, :input)
  end

  @doc """
  Maps an Ash type to a TypeScript type for output schemas.
  Backward compatible wrapper around map_type/3.
  """
  def get_ts_type(type_and_constraints, select_and_loads \\ nil)

  def get_ts_type(%AshApiSpec.Field{type: type}, _select_and_loads) do
    map_type(type, [], :output)
  end

  def get_ts_type(%AshApiSpec.Argument{type: type}, _select_and_loads) do
    map_type(type, [], :output)
  end

  def get_ts_type(%AshApiSpec.Metadata{type: type}, _select_and_loads) do
    map_type(type, [], :output)
  end

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
  @spec map_type(atom() | tuple() | AshApiSpec.Type.t(), keyword(), direction()) :: String.t()
  def map_type(type, constraints, direction)

  # Nil type
  def map_type(nil, _constraints, _direction), do: "null"

  # ── %AshApiSpec.Type{} dispatch ──────────────────────────────────
  # Eliminates unwrap_new_type + cond cascade when pre-resolved types
  # are available (e.g., from ResourceBuilder or persisted Resource specs).
  def map_type(%AshApiSpec.Type{} = type_info, _constraints, direction) do
    case type_info.kind do
      :array ->
        inner_ts = map_type(type_info.item_type, [], direction)
        wrap_array(inner_ts)

      kind when kind in [:resource, :embedded_resource] ->
        resource = type_info.resource_module || type_info.module
        map_resource(resource, direction)

      :enum ->
        map_enum_from_type(type_info)

      :union ->
        map_union(type_info.constraints || [], direction)

      :struct ->
        map_struct(ensure_codegen_instance_of(type_info), direction)

      kind when kind in [:map, :keyword, :tuple] ->
        mod = kind_to_container_module(kind)
        map_typed_container(mod, ensure_codegen_instance_of(type_info), direction)

      _ ->
        # For primitive kinds: check module lookup, custom types, then kind fallback
        cond do
          (ts = Map.get(@primitives, type_info.module)) != nil ->
            ts

          is_atom(type_info.module) and not is_nil(type_info.module) and
              is_custom_type?(type_info.module) ->
            type_info.module.typescript_type_name()

          (override = get_type_mapping_override(type_info.module)) != nil ->
            override

          (ts = Map.get(@kind_to_ts, type_info.kind)) != nil ->
            ts

          type_info.kind == :atom ->
            case Keyword.get(type_info.constraints || [], :one_of) do
              nil -> "string"
              values -> Enum.map_join(values, " | ", &"\"#{to_string(&1)}\"")
            end

          true ->
            "any"
        end
    end
  end

  # Aggregate kind atoms (e.g., :count, :sum) are not real Ash types
  # and are not handled by TypeResolver. Handle them directly.
  def map_type(type, _constraints, _direction)
      when is_atom(type) and is_map_key(@aggregate_kinds, type) do
    Map.get(@aggregate_kinds, type)
  end

  # :map atom (Ecto shorthand, not Ash.Type.Map) is not handled by TypeResolver.
  def map_type(:map, _constraints, _direction), do: AshTypescript.untyped_map_type()

  def map_type(type, constraints, direction) do
    # Build an %AshApiSpec.Type{} from raw Ash types for backward compatibility
    type_info = AshApiSpec.Generator.TypeResolver.resolve(type, constraints)
    map_type(type_info, constraints, direction)
  end

  # ─────────────────────────────────────────────────────────────────
  # Type-Specific Handlers
  # ─────────────────────────────────────────────────────────────────

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

      # instance_of pointing to TypedStruct (output only uses this)
      # Note: resource instance_of types are already handled as kind: :resource
      # by the TypeResolver, so they never reach this :struct branch
      instance_of && direction == :output ->
        field_name_mappings = get_field_name_mappings(Ash.Type.Struct, constraints)
        build_map_type(fields || [], nil, field_name_mappings)

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
      embedded_resource?(type) ->
        map_resource(type, direction)

      # Other types - recurse
      true ->
        map_type(type, constraints, direction)
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Selection-Aware Type Mapping (for output with select_and_loads)
  # ─────────────────────────────────────────────────────────────────

  defp map_type_with_selection(type, constraints, select_and_loads) do
    # Unwrap NewTypes first
    {unwrapped_type, full_constraints} =
      AshTypescript.TypeSystem.Introspection.unwrap_new_type(type, constraints)

    cond do
      # Struct with instance_of - use build_resource_type with selection
      unwrapped_type == Ash.Type.Struct and Keyword.has_key?(full_constraints, :instance_of) ->
        instance_of = Keyword.get(full_constraints, :instance_of)

        if Spark.Dsl.is?(instance_of, Ash.Resource) do
          resource_name = Helpers.build_resource_type_name(instance_of)
          "#{resource_name}ResourceSchema"
        else
          field_name_mappings = get_field_name_mappings(Ash.Type.Struct, full_constraints)

          build_map_type(
            Keyword.get(full_constraints, :fields, []),
            select_and_loads,
            field_name_mappings
          )
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

      true ->
        nil
    end
  end

  @doc """
  Maps an Ash type to a TypeScript type for channel event payloads.

  Like `map_type/3` with `:output` direction, but typed containers (maps/structs
  with `:fields` constraint) generate plain object types without the
  `__type`/`__primitiveFields` metadata that the RPC field-selection system needs.
  """
  @spec map_channel_payload_type(atom() | tuple(), keyword()) :: String.t()
  def map_channel_payload_type(type, constraints) do
    {unwrapped_type, full_constraints} = Introspection.unwrap_new_type(type, constraints)

    cond do
      unwrapped_type in [Ash.Type.Map, Ash.Type.Keyword, Ash.Type.Tuple] ->
        fields = Keyword.get(full_constraints, :fields, [])

        if fields == [] do
          AshTypescript.untyped_map_type()
        else
          field_name_mappings = get_field_name_mappings(unwrapped_type, full_constraints)
          build_plain_map_type(fields, field_name_mappings)
        end

      unwrapped_type == Ash.Type.Struct ->
        fields = Keyword.get(full_constraints, :fields)

        if fields do
          field_name_mappings = get_field_name_mappings(Ash.Type.Struct, full_constraints)
          build_plain_map_type(fields, field_name_mappings)
        else
          map_type(type, constraints, :output)
        end

      true ->
        map_type(type, constraints, :output)
    end
  end

  @doc """
  Builds a TypeScript map type with optional field filtering and name mapping.
  """
  def build_map_type(fields, select \\ nil, field_name_mappings \\ nil) do
    selected_fields =
      if select do
        Enum.filter(fields, fn
          {field_name, _} -> to_string(field_name) in select
          %{name: field_name} -> to_string(field_name) in select
        end)
      else
        fields
      end

    field_types =
      selected_fields
      |> Enum.map_join(", ", fn field ->
        {field_name, field_type_str, allow_nil} = extract_field_info(field)

        formatted_field_name =
          if field_name_mappings && Keyword.has_key?(field_name_mappings, field_name) do
            Keyword.get(field_name_mappings, field_name) |> to_string()
          else
            field_name
          end
          |> AshTypescript.FieldFormatter.format_field_name(
            AshTypescript.Rpc.output_field_formatter()
          )

        optional = if allow_nil, do: " | null", else: ""
        "#{formatted_field_name}: #{field_type_str}#{optional}"
      end)

    primitive_fields_union =
      if Enum.empty?(selected_fields) do
        "never"
      else
        primitive_only_fields =
          selected_fields
          |> Enum.filter(fn field ->
            # Only include truly primitive fields, not nested TypedMaps
            !is_nested_typed_map_field?(field)
          end)

        if Enum.empty?(primitive_only_fields) do
          "never"
        else
          primitive_only_fields
          |> Enum.map_join(" | ", fn field ->
            field_name = extract_field_name(field)

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

  # Extracts field info from both legacy {name, config} tuples and spec field maps
  defp extract_field_info({field_name, field_config}) do
    field_type = map_type(field_config[:type], field_config[:constraints] || [], :output)
    allow_nil = Keyword.get(field_config, :allow_nil?, true)
    {field_name, field_type, allow_nil}
  end

  defp extract_field_info(%{
         name: field_name,
         type: %AshApiSpec.Type{} = type,
         allow_nil?: allow_nil
       }) do
    field_type = map_type(type, [], :output)
    {field_name, field_type, allow_nil}
  end

  defp extract_field_info(%{name: field_name, type: type, allow_nil?: allow_nil}) do
    field_type = map_type(type, [], :output)
    {field_name, field_type, allow_nil}
  end

  defp extract_field_name({field_name, _}), do: field_name
  defp extract_field_name(%{name: field_name}), do: field_name

  defp is_nested_typed_map_field?({_name, field_config}), do: is_nested_typed_map?(field_config)

  defp is_nested_typed_map_field?(%{type: %AshApiSpec.Type{kind: kind}}),
    do: kind in [:map, :struct, :keyword, :tuple]

  defp is_nested_typed_map_field?(_), do: false

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
  def is_primitive_union_member?(%AshApiSpec.Type{} = type_info) do
    case type_info.kind do
      kind when kind in [:embedded_resource, :resource, :union] -> false
      :struct -> !(type_info.instance_of || has_type_fields?(type_info))
      kind when kind in [:map, :keyword, :tuple] -> !has_type_fields?(type_info)
      _ -> true
    end
  end

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
      is_atom(type) and embedded_resource?(type) ->
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

  defp embedded_resource?(module) when is_atom(module) and not is_nil(module) do
    Ash.Resource.Info.resource?(module) and Ash.Resource.Info.embedded?(module)
  end

  defp embedded_resource?(_), do: false

  defp is_custom_type?(type) when is_atom(type) and not is_nil(type) do
    Code.ensure_loaded?(type) and
      function_exported?(type, :typescript_type_name, 0) and
      Spark.implements_behaviour?(type, Ash.Type)
  end

  defp is_custom_type?(_), do: false

  defp has_typescript_field_names?(nil), do: false

  defp has_typescript_field_names?(module) when is_atom(module) do
    Code.ensure_loaded?(module) && function_exported?(module, :typescript_field_names, 0)
  end

  defp has_typescript_field_names?(_), do: false

  # Ensures instance_of is in constraints for %Type{} structs (bridges
  # TypeResolver compile-time output and map_struct/map_typed_container expectations).
  # Checks both type_info.instance_of and type_info.module for typescript_field_names.
  defp ensure_codegen_instance_of(%AshApiSpec.Type{} = type_info) do
    constraints = type_info.constraints || []

    if Keyword.has_key?(constraints, :instance_of) do
      constraints
    else
      # Prefer instance_of, fall back to module if it has typescript_field_names
      instance =
        type_info.instance_of ||
          if is_atom(type_info.module) and not is_nil(type_info.module) and
               has_typescript_field_names?(type_info.module) do
            type_info.module
          end

      if instance do
        Keyword.put(constraints, :instance_of, instance)
      else
        constraints
      end
    end
  end

  defp kind_to_container_module(:map), do: Ash.Type.Map
  defp kind_to_container_module(:keyword), do: Ash.Type.Keyword
  defp kind_to_container_module(:tuple), do: Ash.Type.Tuple

  defp map_enum_from_type(%AshApiSpec.Type{values: values})
       when is_list(values) and values != [] do
    Enum.map_join(values, " | ", &"\"#{to_string(&1)}\"")
  end

  defp map_enum_from_type(_), do: "string"

  defp has_type_fields?(%AshApiSpec.Type{fields: fields})
       when is_list(fields) and fields != [],
       do: true

  defp has_type_fields?(%AshApiSpec.Type{constraints: constraints}) do
    Keyword.has_key?(constraints || [], :fields)
  end

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
      {inner_type, inner_constraints} =
        AshTypescript.TypeSystem.Introspection.unwrap_new_type(type, constraints)

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
