# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.ResultProcessor do
  @moduledoc """
  Extracts requested fields from RPC results using type-driven dispatch.

  This module uses the same pattern as `ValueFormatter` and `FieldSelector`:
  type-driven recursive dispatch where each type is self-describing.

  ## Architecture

  The core insight is that both `ValueFormatter` and `ResultProcessor` need to
  understand type structure:
  - **ValueFormatter**: Formats field names (internal ↔ client)
  - **ResultProcessor**: Extracts requested fields (filtering)

  They share the need for type-driven recursive dispatch but have different concerns.

  ## Type-Driven Extraction

  ```
  extract_value/5 (unified type-driven dispatch)
     │
     ├─> extract_resource_value/4    (Ash Resources)
     ├─> extract_typed_struct_value/4 (TypedStruct/NewType)
     ├─> extract_typed_map_value/4   (Map/Struct with fields)
     ├─> extract_union_value/4       (Ash.Type.Union)
     ├─> extract_array_value/5       (Arrays - recurse)
     └─> normalize_primitive/1       (Primitives)
  ```
  """

  alias AshTypescript.Rpc.FieldExtractor
  alias AshTypescript.Rpc.TypeIndex

  @doc """
  Main entry point for processing Ash results.
  """
  @spec process(term(), map(), module() | nil, map() | nil, map()) :: term()
  def process(
        result,
        extraction_template,
        resource \\ nil,
        resource_lookups \\ nil,
        _type_index \\ %{}
      ) do
    case result do
      %Ash.Page.Offset{results: results} = page ->
        processed_results =
          extract_list_fields(results, extraction_template, resource, resource_lookups)

        page
        |> Map.take([:limit, :offset, :count])
        |> Map.put(:results, processed_results)
        |> Map.put(:has_more, page.more? || false)
        |> Map.put(:type, :offset)

      %Ash.Page.Keyset{results: results} = page ->
        processed_results =
          extract_list_fields(results, extraction_template, resource, resource_lookups)

        {previous_page_cursor, next_page_cursor} =
          if Enum.empty?(results) do
            {nil, nil}
          else
            {List.first(results).__metadata__.keyset, List.last(results).__metadata__.keyset}
          end

        page
        |> Map.take([:before, :after, :limit, :count])
        |> Map.put(:has_more, page.more? || false)
        |> Map.put(:results, processed_results)
        |> Map.put(:previous_page, previous_page_cursor)
        |> Map.put(:next_page, next_page_cursor)
        |> Map.put(:type, :keyset)

      [] ->
        []

      result when is_list(result) ->
        if Keyword.keyword?(result) do
          extract_single_result(result, extraction_template, resource, resource_lookups)
        else
          extract_list_fields(result, extraction_template, resource, resource_lookups)
        end

      result ->
        extract_single_result(result, extraction_template, resource, resource_lookups)
    end
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Unified Type Lookup
  # ─────────────────────────────────────────────────────────────────────────────

  @doc """
  Gets the type and constraints for a field, checking all field sources.

  This consolidates all the previous resource lookup functions into one.

  ## Parameters
  - `resource` - The Ash resource module, TypedStruct module, or nil
  - `field_name` - The field name (atom)

  ## Returns
  `{type, constraints}` or `{nil, []}` if not found.
  """
  @spec get_field_or_relationship(module() | nil, atom(), map() | nil) ::
          AshApiSpec.Field.t() | AshApiSpec.Relationship.t() | nil
  def get_field_or_relationship(nil, _field_name, _lookups), do: nil

  def get_field_or_relationship(resource, field_name, resource_lookups)
      when is_atom(resource) and is_map(resource_lookups) do
    case AshApiSpec.get_field(resource_lookups, resource, field_name) do
      %AshApiSpec.Field{} = field -> field
      nil -> AshApiSpec.get_relationship(resource_lookups, resource, field_name)
    end
  end

  def get_field_or_relationship(_resource, _field_name, _lookups), do: nil

  # ─────────────────────────────────────────────────────────────────────────────
  # Type-Driven Extraction Dispatcher
  # ─────────────────────────────────────────────────────────────────────────────

  @doc """
  Extracts and normalizes a value based on its type and template.

  This is the core recursive function that dispatches to type-specific
  handlers based on the type's characteristics. Mirrors the pattern
  used in `ValueFormatter.format/5`.

  ## Parameters
  - `value` - The value to extract from
  - `type` - The Ash type (or nil for unknown)
  - `constraints` - Type constraints
  - `template` - The extraction template (list of field specs)

  ## Returns
  The extracted and normalized value.
  """
  @spec extract_value(
          term(),
          atom() | tuple() | AshApiSpec.Type.t() | nil,
          keyword(),
          list(),
          map() | nil
        ) :: term()
  def extract_value(value, type, constraints, template, resource_lookups \\ nil)

  # Handle nil
  def extract_value(nil, _type, _constraints, _template, _resource_lookups), do: nil

  # Handle special Ash markers
  def extract_value(%Ash.ForbiddenField{}, _type, _constraints, _template, _resource_lookups),
    do: nil

  def extract_value(%Ash.NotLoaded{}, _type, _constraints, _template, _resource_lookups),
    do: :skip

  # Handle nil/unknown types
  # For maps with templates, filter to requested fields
  # For everything else, normalize as primitive
  # Handle AshApiSpec structs — extract type and delegate
  def extract_value(value, %AshApiSpec.Field{type: type}, _constraints, template, resource_lookups) do
    extract_value(value, type, [], template, resource_lookups)
  end

  def extract_value(value, %AshApiSpec.Relationship{destination: dest, cardinality: :many}, _constraints, template, resource_lookups) do
    extract_array_value(value, dest, [], template, resource_lookups)
  end

  def extract_value(value, %AshApiSpec.Relationship{destination: dest}, _constraints, template, resource_lookups) do
    extract_resource_value(value, dest, template, resource_lookups)
  end

  def extract_value(value, nil, _constraints, template, _resource_lookups)
      when is_map(value) and template != [] do
    extract_plain_map_value(value, template)
  end

  def extract_value(value, nil, _constraints, _template, _resource_lookups),
    do: normalize_primitive(value)

  # %Type{kind} dispatch — replaces unwrap_new_type + cond for the lookup path
  def extract_value(
        value,
        %AshApiSpec.Type{} = type_info,
        _constraints,
        template,
        resource_lookups
      ) do
    constraints = augment_type_constraints(type_info)
    inst = type_info.instance_of || type_info.module

    case type_info.kind do
      :type_ref ->
        full_type = AshApiSpec.Generator.TypeResolver.resolve_definition(type_info.module)
        extract_value(value, full_type, [], template, resource_lookups)

      :array ->
        extract_array_value(value, type_info.item_type, [], template, resource_lookups)

      kind when kind in [:resource, :embedded_resource] ->
        resource = type_info.resource_module || inst
        extract_resource_value(value, resource, template, resource_lookups)

      :union ->
        extract_union_value(value, constraints, template, resource_lookups)

      kind when kind in [:struct, :map] ->
        cond do
          inst && is_atom(inst) && TypeIndex.resource?(%{}, inst) ->
            extract_resource_value(value, inst, template, resource_lookups)

          TypeIndex.has_ts_field_names?(%{}, inst) ->
            extract_typed_struct_value(value, constraints, template, resource_lookups)

          true ->
            extract_typed_map_value(value, constraints, template, resource_lookups)
        end

      kind when kind in [:tuple, :keyword] ->
        if TypeIndex.has_ts_field_names?(%{}, inst) do
          extract_typed_struct_value(value, constraints, template, resource_lookups)
        else
          extract_typed_map_value(value, constraints, template, resource_lookups)
        end

      _ ->
        normalize_primitive(value)
    end
  end

  # {:array, inner_type} tuple form (from raw Ash types)
  def extract_value(value, {:array, inner_type}, constraints, template, resource_lookups) do
    inner_constraints = Keyword.get(constraints, :items, [])
    extract_array_value(value, inner_type, inner_constraints, template, resource_lookups)
  end

  def extract_value(value, type, constraints, template, resource_lookups) do
    # Unwrap NewTypes first (same pattern as ValueFormatter)
    {unwrapped_type, full_constraints} = TypeIndex.unwrap_new_type(%{}, type, constraints)

    cond do
      # Ash Resources
      TypeIndex.resource?(%{}, unwrapped_type) ->
        extract_resource_value(value, unwrapped_type, template, resource_lookups)

      # Ash.Type.Struct with resource instance_of
      unwrapped_type == Ash.Type.Struct &&
          TypeIndex.is_resource_instance_of?(%{}, full_constraints) ->
        instance_of = Keyword.get(full_constraints, :instance_of)
        extract_resource_value(value, instance_of, template, resource_lookups)

      # TypedStruct/NewType with typescript_field_names
      TypeIndex.has_ts_field_names?(%{}, full_constraints[:instance_of]) ->
        extract_typed_struct_value(value, full_constraints, template, resource_lookups)

      # Ash.Type.Union
      unwrapped_type == Ash.Type.Union ->
        extract_union_value(value, full_constraints, template, resource_lookups)

      # Ash.Type.Map/Struct/Tuple/Keyword with field constraints
      unwrapped_type in [Ash.Type.Map, Ash.Type.Struct, Ash.Type.Tuple, Ash.Type.Keyword] ->
        extract_typed_map_value(value, full_constraints, template, resource_lookups)

      # Primitives and everything else
      true ->
        normalize_primitive(value)
    end
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Type-Specific Handlers
  # ─────────────────────────────────────────────────────────────────────────────

  # Resource Handler
  defp extract_resource_value(value, resource, template, resource_lookups) when is_map(value) do
    # Check if the value is actually an instance of the expected resource
    # If not (e.g., we have a Date but expected a Todo), just normalize it
    value_is_resource_instance =
      is_struct(value) && value.__struct__ == resource

    if value_is_resource_instance do
      # For resource structs with empty template, extract all public fields
      # (Pipeline handles mutation empty-return case separately)
      if template == [] do
        normalize_resource_struct(value, resource)
      else
        normalized = FieldExtractor.normalize_for_extraction(value, template)

        Enum.reduce(template, %{}, fn field_spec, acc ->
          case field_spec do
            # Simple field
            field_atom when is_atom(field_atom) ->
              extract_resource_field(normalized, resource, field_atom, acc, resource_lookups)

            # Nested field
            {field_atom, nested_template} when is_atom(field_atom) ->
              extract_resource_nested_field(
                normalized,
                resource,
                field_atom,
                nested_template,
                acc,
                resource_lookups
              )

            # Tuple metadata (for tuple fields in templates)
            %{field_name: field_name, index: _index} ->
              extract_resource_field(normalized, resource, field_name, acc, resource_lookups)

            _ ->
              acc
          end
        end)
      end
    else
      # Value type doesn't match expected resource type - just normalize
      normalize_primitive(value)
    end
  end

  defp extract_resource_value(value, _resource, _template, _resource_lookups),
    do: normalize_primitive(value)

  defp extract_resource_field(data, resource, field_atom, acc, resource_lookups) do
    case Map.get(data, field_atom) do
      %Ash.ForbiddenField{} ->
        Map.put(acc, field_atom, nil)

      %Ash.NotLoaded{} ->
        acc

      value ->
        field_or_rel = get_field_or_relationship(resource, field_atom, resource_lookups)

        # Recurse with type info - NO template for simple fields
        extracted = extract_value(value, field_or_rel, [], [], resource_lookups)
        Map.put(acc, field_atom, extracted)
    end
  end

  defp extract_resource_nested_field(
         data,
         resource,
         field_atom,
         nested_template,
         acc,
         resource_lookups
       ) do
    case Map.get(data, field_atom) do
      %Ash.ForbiddenField{} ->
        Map.put(acc, field_atom, nil)

      %Ash.NotLoaded{} ->
        acc

      nil ->
        Map.put(acc, field_atom, nil)

      value ->
        field_or_rel = get_field_or_relationship(resource, field_atom, resource_lookups)

        # Recurse with both type info AND nested template
        extracted =
          extract_value(value, field_or_rel, [], nested_template, resource_lookups)

        Map.put(acc, field_atom, extracted)
    end
  end

  defp augment_type_constraints(type_info) do
    constraints = type_info.constraints || []
    inst = type_info.instance_of || type_info.module

    if inst && is_atom(inst) && !Keyword.has_key?(constraints, :instance_of) &&
         TypeIndex.has_ts_field_names?(%{}, inst) do
      Keyword.put(constraints, :instance_of, inst)
    else
      constraints
    end
  end

  defp extract_union_value(
         %Ash.Union{type: active_type, value: union_value},
         constraints,
         template,
         resource_lookups
       ) do
    union_types = Keyword.get(constraints, :types, [])
    member_in_template = template == [] or member_in_template?(template, active_type)

    if member_in_template do
      member_template = find_member_template(template, active_type)

      case Keyword.get(union_types, active_type) do
        nil ->
          %{active_type => normalize_primitive(union_value)}

        member_spec ->
          member_type = Keyword.get(member_spec, :type)
          member_constraints = Keyword.get(member_spec, :constraints, [])

          extracted =
            extract_value(
              union_value,
              member_type,
              member_constraints,
              member_template,
              resource_lookups
            )

          %{active_type => extracted}
      end
    else
      nil
    end
  end

  defp extract_union_value(value, _constraints, _template, _resource_lookups),
    do: normalize_primitive(value)

  defp member_in_template?(template, member_name) do
    Enum.any?(template, fn
      {member, _nested} -> member == member_name
      member when is_atom(member) -> member == member_name
      _ -> false
    end)
  end

  defp find_member_template(template, active_type) do
    Enum.find_value(template, [], fn
      {member, nested} when member == active_type -> nested
      member when member == active_type -> []
      _ -> nil
    end)
  end

  defp extract_array_value(value, inner_type, inner_constraints, template, resource_lookups)
       when is_list(value) do
    value
    |> Enum.map(fn item ->
      case extract_value(item, inner_type, inner_constraints, template, resource_lookups) do
        :skip -> nil
        result -> result
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_array_value(value, _inner_type, _inner_constraints, _template, _resource_lookups),
    do: value

  defp extract_typed_struct_value(value, constraints, template, resource_lookups)
       when is_list(value) do
    map_value = Enum.into(value, %{})
    extract_typed_struct_value(map_value, constraints, template, resource_lookups)
  end

  defp extract_typed_struct_value(value, constraints, template, resource_lookups)
       when is_map(value) do
    field_specs = Keyword.get(constraints, :fields, [])
    normalized = FieldExtractor.normalize_for_extraction(value, template)

    Enum.reduce(template, %{}, fn field_spec, acc ->
      case field_spec do
        field_atom when is_atom(field_atom) ->
          field_value = Map.get(normalized, field_atom)

          {field_type, field_constraints} =
            TypeIndex.get_field_spec_type(field_specs, field_atom)

          extracted =
            extract_value(field_value, field_type, field_constraints, [], resource_lookups)

          Map.put(acc, field_atom, extracted)

        {field_atom, nested_template} when is_atom(field_atom) ->
          field_value = Map.get(normalized, field_atom)

          {field_type, field_constraints} =
            TypeIndex.get_field_spec_type(field_specs, field_atom)

          extracted =
            extract_value(
              field_value,
              field_type,
              field_constraints,
              nested_template,
              resource_lookups
            )

          Map.put(acc, field_atom, extracted)

        _ ->
          acc
      end
    end)
  end

  defp extract_typed_struct_value(value, _constraints, _template, _resource_lookups),
    do: normalize_primitive(value)

  defp extract_typed_map_value(value, constraints, template, resource_lookups)
       when is_list(value) do
    map_value = Enum.into(value, %{})
    extract_typed_map_value(map_value, constraints, template, resource_lookups)
  end

  defp extract_typed_map_value(value, constraints, template, resource_lookups)
       when is_map(value) do
    field_specs = Keyword.get(constraints, :fields, [])
    normalized = FieldExtractor.normalize_for_extraction(value, template)

    cond do
      template == [] and field_specs == [] ->
        normalize_primitive(value)

      template == [] ->
        Enum.reduce(field_specs, %{}, fn {field_name, field_spec}, acc ->
          field_value = Map.get(normalized, field_name)
          field_type = Keyword.get(field_spec, :type)
          field_constraints = Keyword.get(field_spec, :constraints, [])

          extracted =
            extract_value(field_value, field_type, field_constraints, [], resource_lookups)

          Map.put(acc, field_name, extracted)
        end)

      true ->
        Enum.reduce(template, %{}, fn field_spec, acc ->
          case field_spec do
            field_atom when is_atom(field_atom) ->
              field_value = Map.get(normalized, field_atom)

              {field_type, field_constraints} =
                TypeIndex.get_field_spec_type(field_specs, field_atom)

              extracted =
                extract_value(field_value, field_type, field_constraints, [], resource_lookups)

              Map.put(acc, field_atom, extracted)

            {field_atom, nested_template} when is_atom(field_atom) ->
              field_value = Map.get(normalized, field_atom)

              {field_type, field_constraints} =
                TypeIndex.get_field_spec_type(field_specs, field_atom)

              extracted =
                extract_value(
                  field_value,
                  field_type,
                  field_constraints,
                  nested_template,
                  resource_lookups
                )

              Map.put(acc, field_atom, extracted)

            # Handle tuple field metadata
            %{field_name: field_name, index: _index} ->
              field_value = Map.get(normalized, field_name)

              {field_type, field_constraints} =
                TypeIndex.get_field_spec_type(field_specs, field_name)

              extracted =
                extract_value(field_value, field_type, field_constraints, [], resource_lookups)

              Map.put(acc, field_name, extracted)

            _ ->
              acc
          end
        end)
    end
  end

  defp extract_typed_map_value(value, constraints, template, resource_lookups)
       when is_tuple(value) do
    normalized = FieldExtractor.normalize_for_extraction(value, template)
    extract_typed_map_value(normalized, constraints, template, resource_lookups)
  end

  defp extract_typed_map_value(value, constraints, template, resource_lookups)
       when is_list(value) do
    # Empty lists should remain as arrays - Keyword.keyword?([]) returns true in Elixir
    if value != [] and Keyword.keyword?(value) do
      normalized = Map.new(value)
      extract_typed_map_value(normalized, constraints, template, resource_lookups)
    else
      normalize_primitive(value)
    end
  end

  defp extract_typed_map_value(value, _constraints, _template, _resource_lookups),
    do: normalize_primitive(value)

  defp extract_plain_map_value(value, template) when is_map(value) do
    Enum.reduce(template, %{}, fn field_spec, acc ->
      case field_spec do
        field_atom when is_atom(field_atom) ->
          field_value = Map.get(value, field_atom) || Map.get(value, to_string(field_atom))
          Map.put(acc, field_atom, normalize_primitive(field_value))

        {field_atom, nested_template} when is_atom(field_atom) ->
          field_value = Map.get(value, field_atom) || Map.get(value, to_string(field_atom))

          nested_extracted =
            if is_map(field_value) and nested_template != [] do
              extract_plain_map_value(field_value, nested_template)
            else
              normalize_primitive(field_value)
            end

          Map.put(acc, field_atom, nested_extracted)

        _ ->
          acc
      end
    end)
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Primitive Normalization
  # ─────────────────────────────────────────────────────────────────────────────

  @doc """
  Alias for normalize_primitive/1 for backwards compatibility.
  Normalizes a value for JSON serialization.
  """
  def normalize_value_for_json(value), do: normalize_primitive(value)

  @doc """
  Normalizes a value for JSON serialization.

  Handles DateTime, Date, Time, Decimal, CiString, atoms, keyword lists, nested maps,
  regular lists, and Ash.Union types. Recursively normalizes nested structures.
  """
  def normalize_primitive(nil), do: nil

  def normalize_primitive(value) do
    cond do
      is_nil(value) ->
        nil

      match?(%DateTime{}, value) ->
        DateTime.to_iso8601(value)

      match?(%Date{}, value) ->
        Date.to_iso8601(value)

      match?(%Time{}, value) ->
        Time.to_iso8601(value)

      match?(%NaiveDateTime{}, value) ->
        NaiveDateTime.to_iso8601(value)

      match?(%Duration{}, value) ->
        Duration.to_iso8601(value)

      match?(%Decimal{}, value) ->
        Decimal.to_string(value)

      match?(%Ash.CiString{}, value) ->
        to_string(value)

      match?(%Ash.Union{}, value) ->
        %Ash.Union{type: type_name, value: union_value} = value
        type_key = to_string(type_name)
        %{type_key => normalize_primitive(union_value)}

      is_atom(value) and not is_boolean(value) ->
        Atom.to_string(value)

      is_struct(value) && TypeIndex.resource?(%{}, value.__struct__) ->
        normalize_resource_struct(value, value.__struct__)

      is_struct(value) ->
        value
        |> Map.from_struct()
        |> Enum.reduce(%{}, fn {key, val}, acc ->
          Map.put(acc, key, normalize_primitive(val))
        end)

      is_list(value) ->
        # Empty lists should remain as empty arrays, not become empty objects.
        # Keyword.keyword?([]) returns true in Elixir, but an empty array in JSON
        # is distinctly different from an empty object.
        if value != [] and Keyword.keyword?(value) do
          Enum.reduce(value, %{}, fn {key, val}, acc ->
            string_key = to_string(key)
            Map.put(acc, string_key, normalize_primitive(val))
          end)
        else
          Enum.map(value, &normalize_primitive/1)
        end

      is_map(value) ->
        Enum.reduce(value, %{}, fn {key, val}, acc ->
          Map.put(acc, key, normalize_primitive(val))
        end)

      true ->
        value
    end
  end

  defp normalize_resource_struct(value, resource) do
    public_attrs = Ash.Resource.Info.public_attributes(resource)
    public_calcs = Ash.Resource.Info.public_calculations(resource)
    public_aggs = Ash.Resource.Info.public_aggregates(resource)

    public_field_names =
      (Enum.map(public_attrs, & &1.name) ++
         Enum.map(public_calcs, & &1.name) ++
         Enum.map(public_aggs, & &1.name))
      |> MapSet.new()

    value
    |> Map.from_struct()
    |> Enum.reduce(%{}, fn {key, val}, acc ->
      if MapSet.member?(public_field_names, key) do
        Map.put(acc, key, normalize_primitive(val))
      else
        acc
      end
    end)
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Helper Functions
  # ─────────────────────────────────────────────────────────────────────────────

  defp is_primitive_value?(value) do
    case value do
      %DateTime{} -> true
      %Date{} -> true
      %Time{} -> true
      %NaiveDateTime{} -> true
      %Decimal{} -> true
      %Ash.CiString{} -> true
      _ when is_binary(value) -> true
      _ when is_number(value) -> true
      _ when is_boolean(value) -> true
      _ when is_atom(value) and not is_nil(value) -> true
      _ -> false
    end
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Entry Points (using type-driven dispatch)
  # ─────────────────────────────────────────────────────────────────────────────

  defp extract_list_fields(results, extraction_template, resource, resource_lookups) do
    {type, constraints} = determine_data_type(List.first(results), resource)

    inner_type =
      case type do
        {:array, inner} -> inner
        _ -> type
      end

    # When we have resource_lookups and a resource type, try the fast path
    inner_type = maybe_resolve_to_api_type(inner_type, resource_lookups)

    Enum.map(results, fn item ->
      case extract_value(item, inner_type, constraints, extraction_template, resource_lookups) do
        :skip -> nil
        result -> result
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_single_result(data, extraction_template, resource, resource_lookups)

  defp extract_single_result(data, extraction_template, resource, resource_lookups)
       when is_list(extraction_template) do
    if extraction_template == [] and is_primitive_value?(data) do
      normalize_primitive(data)
    else
      {type, constraints} = determine_data_type(data, resource)
      type = maybe_resolve_to_api_type(type, resource_lookups)
      extract_value(data, type, constraints, extraction_template, resource_lookups)
    end
  end

  defp extract_single_result(data, _template, _resource, _resource_lookups) do
    normalize_data(data)
  end

  @doc """
  Determines the type and constraints for a given data value.

  This function infers type information from:
  1. The struct type of the data itself (if it's a struct)
  2. The provided resource context
  3. Falls back to nil for unknown types
  """
  def determine_data_type(nil, resource) do
    if resource && TypeIndex.resource?(%{}, resource) do
      {resource, []}
    else
      {nil, []}
    end
  end

  def determine_data_type(data, resource) do
    cond do
      is_struct(data) && TypeIndex.resource?(%{}, data.__struct__) ->
        {data.__struct__, []}

      is_struct(data) && TypeIndex.has_ts_field_names?(%{}, data.__struct__) ->
        {Ash.Type.Struct, [instance_of: data.__struct__]}

      match?(%Ash.Union{}, data) ->
        if resource && TypeIndex.resource?(%{}, resource) do
          {Ash.Type.Union, get_union_constraints_from_resource(resource)}
        else
          {Ash.Type.Union, []}
        end

      is_list(data) && data != [] && Keyword.keyword?(data) ->
        {Ash.Type.Keyword, []}

      is_tuple(data) ->
        {Ash.Type.Tuple, []}

      is_map(data) && not is_struct(data) ->
        {nil, []}

      resource && TypeIndex.resource?(%{}, resource) && is_struct(data) ->
        {resource, []}

      true ->
        {nil, []}
    end
  end

  defp get_union_constraints_from_resource(resource) do
    attrs = Ash.Resource.Info.attributes(resource)

    Enum.find_value(attrs, [], fn attr ->
      case attr.type do
        Ash.Type.Union ->
          Keyword.get(attr.constraints, :types, []) |> then(&[types: &1])

        {:array, Ash.Type.Union} ->
          items = Keyword.get(attr.constraints, :items, [])
          Keyword.get(items, :types, []) |> then(&[types: &1])

        _ ->
          nil
      end
    end)
  end

  defp normalize_data(data) do
    case data do
      %_struct{} = struct_data ->
        Map.from_struct(struct_data)

      other ->
        other
    end
  end

  # When we have resource_lookups and the type is a resource module,
  # build an %AshApiSpec.Type{} so extract_value hits the fast dispatch head.
  defp maybe_resolve_to_api_type(type, resource_lookups)
       when is_atom(type) and is_map(resource_lookups) do
    case Map.get(resource_lookups, type) do
      %AshApiSpec.Resource{} ->
        %AshApiSpec.Type{
          kind: :resource,
          name: "Resource",
          module: type,
          resource_module: type,
          constraints: []
        }

      nil ->
        type
    end
  end

  defp maybe_resolve_to_api_type(type, _), do: type
end
