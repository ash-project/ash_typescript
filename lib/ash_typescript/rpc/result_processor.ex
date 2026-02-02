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
  extract_value/4 (unified type-driven dispatch)
     │
     ├─> extract_resource_value/3    (Ash Resources)
     ├─> extract_typed_struct_value/3 (TypedStruct/NewType)
     ├─> extract_typed_map_value/3   (Map/Struct with fields)
     ├─> extract_union_value/3       (Ash.Type.Union)
     ├─> extract_array_value/4       (Arrays - recurse)
     └─> normalize_primitive/1       (Primitives)
  ```
  """

  alias AshTypescript.Rpc.FieldExtractor
  alias AshTypescript.TypeSystem.{Introspection, ResourceFields}

  @doc """
  Main entry point for processing Ash results.
  """
  @spec process(term(), map(), module() | nil) :: term()
  def process(result, extraction_template, resource \\ nil) do
    case result do
      %Ash.Page.Offset{results: results} = page ->
        processed_results = extract_list_fields(results, extraction_template, resource)

        page
        |> Map.take([:limit, :offset, :count])
        |> Map.put(:results, processed_results)
        |> Map.put(:has_more, page.more? || false)
        |> Map.put(:type, :offset)

      %Ash.Page.Keyset{results: results} = page ->
        processed_results = extract_list_fields(results, extraction_template, resource)

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
          extract_single_result(result, extraction_template, resource)
        else
          extract_list_fields(result, extraction_template, resource)
        end

      result ->
        extract_single_result(result, extraction_template, resource)
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
  @spec get_field_type_info(module() | nil, atom()) :: {atom() | tuple() | nil, keyword()}
  def get_field_type_info(nil, _field_name), do: {nil, []}

  def get_field_type_info(resource, field_name) when is_atom(resource) do
    cond do
      # For Ash resources, delegate to ResourceFields which handles all field types
      # including proper aggregate type resolution
      Ash.Resource.Info.resource?(resource) ->
        ResourceFields.get_field_type_info(resource, field_name)

      # For modules with typescript_field_names (TypedStruct wrappers)
      Code.ensure_loaded?(resource) && function_exported?(resource, :typescript_field_names, 0) ->
        # These are typically NewType wrappers - we may have field specs
        {nil, []}

      true ->
        {nil, []}
    end
  end

  def get_field_type_info(_resource, _field_name), do: {nil, []}

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
  @spec extract_value(term(), atom() | tuple() | nil, keyword(), list()) :: term()

  # Handle nil
  def extract_value(nil, _type, _constraints, _template), do: nil

  # Handle special Ash markers
  def extract_value(%Ash.ForbiddenField{}, _type, _constraints, _template), do: nil
  def extract_value(%Ash.NotLoaded{}, _type, _constraints, _template), do: :skip

  # Handle nil/unknown types
  # For maps with templates, filter to requested fields
  # For everything else, normalize as primitive
  def extract_value(value, nil, _constraints, template) when is_map(value) and template != [] do
    extract_plain_map_value(value, template)
  end

  def extract_value(value, nil, _constraints, _template), do: normalize_primitive(value)

  def extract_value(value, type, constraints, template) do
    # Unwrap NewTypes first (same pattern as ValueFormatter)
    {unwrapped_type, full_constraints} = Introspection.unwrap_new_type(type, constraints)

    cond do
      # Arrays - recurse into inner type
      match?({:array, _}, type) ->
        {:array, inner_type} = type
        inner_constraints = Keyword.get(constraints, :items, [])
        extract_array_value(value, inner_type, inner_constraints, template)

      # Ash Resources
      is_atom(unwrapped_type) && Ash.Resource.Info.resource?(unwrapped_type) ->
        extract_resource_value(value, unwrapped_type, template)

      # Ash.Type.Struct with resource instance_of
      unwrapped_type == Ash.Type.Struct &&
          Introspection.is_resource_instance_of?(full_constraints) ->
        instance_of = Keyword.get(full_constraints, :instance_of)
        extract_resource_value(value, instance_of, template)

      # TypedStruct/NewType with typescript_field_names
      Introspection.has_typescript_field_names?(full_constraints[:instance_of]) ->
        extract_typed_struct_value(value, full_constraints, template)

      # Ash.Type.Union
      unwrapped_type == Ash.Type.Union ->
        extract_union_value(value, full_constraints, template)

      # Ash.Type.Map/Struct/Tuple/Keyword with field constraints
      unwrapped_type in [Ash.Type.Map, Ash.Type.Struct, Ash.Type.Tuple, Ash.Type.Keyword] ->
        extract_typed_map_value(value, full_constraints, template)

      # Primitives and everything else
      true ->
        normalize_primitive(value)
    end
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # Type-Specific Handlers
  # ─────────────────────────────────────────────────────────────────────────────

  # Resource Handler
  defp extract_resource_value(value, resource, template) when is_map(value) do
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
              extract_resource_field(normalized, resource, field_atom, acc)

            # Nested field
            {field_atom, nested_template} when is_atom(field_atom) ->
              extract_resource_nested_field(
                normalized,
                resource,
                field_atom,
                nested_template,
                acc
              )

            # Tuple metadata (for tuple fields in templates)
            %{field_name: field_name, index: _index} ->
              extract_resource_field(normalized, resource, field_name, acc)

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

  defp extract_resource_value(value, _resource, _template), do: normalize_primitive(value)

  defp extract_resource_field(data, resource, field_atom, acc) do
    case Map.get(data, field_atom) do
      %Ash.ForbiddenField{} ->
        Map.put(acc, field_atom, nil)

      %Ash.NotLoaded{} ->
        acc

      value ->
        {field_type, field_constraints} = get_field_type_info(resource, field_atom)
        # Recurse with type info - NO template for simple fields
        extracted = extract_value(value, field_type, field_constraints, [])
        Map.put(acc, field_atom, extracted)
    end
  end

  defp extract_resource_nested_field(data, resource, field_atom, nested_template, acc) do
    case Map.get(data, field_atom) do
      %Ash.ForbiddenField{} ->
        Map.put(acc, field_atom, nil)

      %Ash.NotLoaded{} ->
        acc

      nil ->
        Map.put(acc, field_atom, nil)

      value ->
        {field_type, field_constraints} = get_field_type_info(resource, field_atom)
        # Recurse with both type info AND nested template
        extracted = extract_value(value, field_type, field_constraints, nested_template)
        Map.put(acc, field_atom, extracted)
    end
  end

  defp extract_union_value(
         %Ash.Union{type: active_type, value: union_value},
         constraints,
         template
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
          extracted = extract_value(union_value, member_type, member_constraints, member_template)
          %{active_type => extracted}
      end
    else
      nil
    end
  end

  defp extract_union_value(value, _constraints, _template), do: normalize_primitive(value)

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

  defp extract_array_value(value, inner_type, inner_constraints, template) when is_list(value) do
    value
    |> Enum.map(fn item ->
      case extract_value(item, inner_type, inner_constraints, template) do
        :skip -> nil
        result -> result
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_array_value(value, _inner_type, _inner_constraints, _template), do: value

  defp extract_typed_struct_value(value, constraints, template) when is_list(value) do
    map_value = Enum.into(value, %{})
    extract_typed_struct_value(map_value, constraints, template)
  end

  defp extract_typed_struct_value(value, constraints, template) when is_map(value) do
    field_specs = Keyword.get(constraints, :fields, [])
    normalized = FieldExtractor.normalize_for_extraction(value, template)

    Enum.reduce(template, %{}, fn field_spec, acc ->
      case field_spec do
        field_atom when is_atom(field_atom) ->
          field_value = Map.get(normalized, field_atom)

          {field_type, field_constraints} =
            Introspection.get_field_spec_type(field_specs, field_atom)

          extracted = extract_value(field_value, field_type, field_constraints, [])
          Map.put(acc, field_atom, extracted)

        {field_atom, nested_template} when is_atom(field_atom) ->
          field_value = Map.get(normalized, field_atom)

          {field_type, field_constraints} =
            Introspection.get_field_spec_type(field_specs, field_atom)

          extracted = extract_value(field_value, field_type, field_constraints, nested_template)
          Map.put(acc, field_atom, extracted)

        _ ->
          acc
      end
    end)
  end

  defp extract_typed_struct_value(value, _constraints, _template), do: normalize_primitive(value)

  defp extract_typed_map_value(value, constraints, template) when is_list(value) do
    map_value = Enum.into(value, %{})
    extract_typed_map_value(map_value, constraints, template)
  end

  defp extract_typed_map_value(value, constraints, template) when is_map(value) do
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
          extracted = extract_value(field_value, field_type, field_constraints, [])
          Map.put(acc, field_name, extracted)
        end)

      true ->
        Enum.reduce(template, %{}, fn field_spec, acc ->
          case field_spec do
            field_atom when is_atom(field_atom) ->
              field_value = Map.get(normalized, field_atom)

              {field_type, field_constraints} =
                Introspection.get_field_spec_type(field_specs, field_atom)

              extracted = extract_value(field_value, field_type, field_constraints, [])
              Map.put(acc, field_atom, extracted)

            {field_atom, nested_template} when is_atom(field_atom) ->
              field_value = Map.get(normalized, field_atom)

              {field_type, field_constraints} =
                Introspection.get_field_spec_type(field_specs, field_atom)

              extracted =
                extract_value(field_value, field_type, field_constraints, nested_template)

              Map.put(acc, field_atom, extracted)

            # Handle tuple field metadata
            %{field_name: field_name, index: _index} ->
              field_value = Map.get(normalized, field_name)

              {field_type, field_constraints} =
                Introspection.get_field_spec_type(field_specs, field_name)

              extracted = extract_value(field_value, field_type, field_constraints, [])
              Map.put(acc, field_name, extracted)

            _ ->
              acc
          end
        end)
    end
  end

  defp extract_typed_map_value(value, constraints, template) when is_tuple(value) do
    normalized = FieldExtractor.normalize_for_extraction(value, template)
    extract_typed_map_value(normalized, constraints, template)
  end

  defp extract_typed_map_value(value, constraints, template) when is_list(value) do
    # Empty lists should remain as arrays - Keyword.keyword?([]) returns true in Elixir
    if value != [] and Keyword.keyword?(value) do
      normalized = Map.new(value)
      extract_typed_map_value(normalized, constraints, template)
    else
      normalize_primitive(value)
    end
  end

  defp extract_typed_map_value(value, _constraints, _template), do: normalize_primitive(value)

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

      is_struct(value) && Ash.Resource.Info.resource?(value.__struct__) ->
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

  defp extract_list_fields(results, extraction_template, resource) do
    {type, constraints} = determine_data_type(List.first(results), resource)

    inner_type =
      case type do
        {:array, inner} -> inner
        _ -> type
      end

    Enum.map(results, fn item ->
      case extract_value(item, inner_type, constraints, extraction_template) do
        :skip -> nil
        result -> result
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_single_result(data, extraction_template, resource)
       when is_list(extraction_template) do
    if extraction_template == [] and is_primitive_value?(data) do
      normalize_primitive(data)
    else
      {type, constraints} = determine_data_type(data, resource)
      extract_value(data, type, constraints, extraction_template)
    end
  end

  defp extract_single_result(data, _template, _resource) do
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
    if resource && Ash.Resource.Info.resource?(resource) do
      {resource, []}
    else
      {nil, []}
    end
  end

  def determine_data_type(data, resource) do
    cond do
      is_struct(data) && Ash.Resource.Info.resource?(data.__struct__) ->
        {data.__struct__, []}

      is_struct(data) && function_exported?(data.__struct__, :typescript_field_names, 0) ->
        {Ash.Type.Struct, [instance_of: data.__struct__]}

      match?(%Ash.Union{}, data) ->
        if resource && Ash.Resource.Info.resource?(resource) do
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

      resource && Ash.Resource.Info.resource?(resource) && is_struct(data) ->
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
end
