# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.ResultProcessor do
  @moduledoc """
  Extracts requested fields from RPC results using type-driven dispatch.

  All type dispatch uses `%AshApiSpec.Type{}` — no raw Ash type atoms or
  `{:array, _}` tuples in the primary dispatch path.

  ## Type-Driven Extraction

  ```
  extract_value/5 (unified type-driven dispatch)
     │
     ├─> extract_resource_value/4    (Ash Resources)
     ├─> extract_typed_struct_value/4 (TypedStruct/NewType with field name mapping)
     ├─> extract_typed_map_value/4   (Map/Struct/Tuple/Keyword with fields)
     ├─> extract_union_value/4       (Ash.Type.Union)
     ├─> extract_array_value/5       (Arrays - recurse)
     └─> normalize_primitive/1       (Primitives)
  ```
  """

  alias AshApiSpec.Type
  alias AshTypescript.Helpers
  alias AshTypescript.Rpc.FieldExtractor

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

  @spec get_field_or_relationship(module() | nil, atom(), map() | nil) ::
          AshApiSpec.Field.t() | AshApiSpec.Relationship.t() | nil
  def get_field_or_relationship(nil, _field_name, _lookups), do: nil

  def get_field_or_relationship(resource, field_name, resource_lookups)
      when is_atom(resource) and is_map(resource_lookups) do
    AshApiSpec.get_field_or_relationship(resource_lookups, resource, field_name)
  end

  def get_field_or_relationship(_resource, _field_name, _lookups), do: nil

  # ─────────────────────────────────────────────────────────────────────────────
  # Type-Driven Extraction Dispatcher
  # ─────────────────────────────────────────────────────────────────────────────

  @spec extract_value(
          term(),
          atom() | tuple() | AshApiSpec.Type.t() | nil,
          keyword(),
          list(),
          map() | nil
        ) :: term()
  def extract_value(value, type, constraints, template, resource_lookups \\ nil)

  def extract_value(nil, _type, _constraints, _template, _resource_lookups), do: nil

  def extract_value(%Ash.ForbiddenField{}, _type, _constraints, _template, _resource_lookups),
    do: nil

  def extract_value(%Ash.NotLoaded{}, _type, _constraints, _template, _resource_lookups),
    do: :skip

  # %AshApiSpec.Field{} — extract type and delegate
  def extract_value(value, %AshApiSpec.Field{type: type}, _constraints, template, resource_lookups) do
    extract_value(value, type, [], template, resource_lookups)
  end

  # %AshApiSpec.Relationship{} — delegate to resource/array handler
  def extract_value(value, %AshApiSpec.Relationship{destination: dest, cardinality: :many}, _constraints, template, resource_lookups) do
    extract_array_value(
      value,
      %AshApiSpec.Type{kind: :resource, module: dest, resource_module: dest},
      template,
      resource_lookups
    )
  end

  def extract_value(value, %AshApiSpec.Relationship{destination: dest}, _constraints, template, resource_lookups) do
    extract_resource_value(value, dest, template, resource_lookups)
  end

  # nil/unknown types
  def extract_value(value, nil, _constraints, template, _resource_lookups)
      when is_map(value) and template != [] do
    extract_plain_map_value(value, template)
  end

  def extract_value(value, nil, _constraints, _template, _resource_lookups),
    do: normalize_primitive(value)

  # %AshApiSpec.Type{} — primary dispatch
  def extract_value(
        value,
        %AshApiSpec.Type{} = type_info,
        _constraints,
        template,
        resource_lookups
      ) do
    inst = Type.effective_module(type_info)

    case type_info.kind do
      :type_ref ->
        full_type = AshApiSpec.Generator.TypeResolver.resolve_definition(type_info.module)
        extract_value(value, full_type, [], template, resource_lookups)

      :array ->
        extract_array_value(value, type_info.item_type, template, resource_lookups)

      kind when kind in [:resource, :embedded_resource] ->
        resource = Type.effective_resource(type_info)
        extract_resource_value(value, resource, template, resource_lookups)

      :union ->
        extract_union_value(value, type_info, template, resource_lookups)

      kind when kind in [:struct, :map] ->
        cond do
          inst && is_atom(inst) && Helpers.ash_resource?(inst) ->
            extract_resource_value(value, inst, template, resource_lookups)

          Helpers.has_typescript_field_names?(inst) ->
            extract_typed_struct_value(value, type_info, template, resource_lookups)

          true ->
            extract_typed_map_value(value, type_info, template, resource_lookups)
        end

      kind when kind in [:tuple, :keyword] ->
        if Helpers.has_typescript_field_names?(inst) do
          extract_typed_struct_value(value, type_info, template, resource_lookups)
        else
          extract_typed_map_value(value, type_info, template, resource_lookups)
        end

      _ ->
        normalize_primitive(value)
    end
  end

  # Catch-all for unrecognized types
  def extract_value(value, _type, _constraints, _template, _resource_lookups),
    do: normalize_primitive(value)

  # (Type checking helpers are now in AshTypescript.Helpers and AshApiSpec.Type)

  # ─────────────────────────────────────────────────────────────────────────────
  # Type-Specific Handlers
  # ─────────────────────────────────────────────────────────────────────────────

  # Resource Handler
  defp extract_resource_value(value, resource, template, resource_lookups) when is_map(value) do
    value_is_resource_instance =
      is_struct(value) && value.__struct__ == resource

    if value_is_resource_instance do
      if template == [] do
        normalize_resource_struct(value, resource, resource_lookups)
      else
        normalized = FieldExtractor.normalize_for_extraction(value, template)

        Enum.reduce(template, %{}, fn field_spec, acc ->
          case field_spec do
            field_atom when is_atom(field_atom) ->
              extract_resource_field(normalized, resource, field_atom, acc, resource_lookups)

            {field_atom, nested_template} when is_atom(field_atom) ->
              extract_resource_nested_field(
                normalized,
                resource,
                field_atom,
                nested_template,
                acc,
                resource_lookups
              )

            %{field_name: field_name, index: _index} ->
              extract_resource_field(normalized, resource, field_name, acc, resource_lookups)

            _ ->
              acc
          end
        end)
      end
    else
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
        extracted = extract_value(value, field_or_rel, [], nested_template, resource_lookups)
        Map.put(acc, field_atom, extracted)
    end
  end

  # Union Handler — uses type_info.members (hydrated with tag/tag_value and %AshApiSpec.Type{})
  defp extract_union_value(
         %Ash.Union{type: active_type, value: union_value},
         type_info,
         template,
         resource_lookups
       ) do
    members = type_info.members || []
    member_in_template = template == [] or member_in_template?(template, active_type)

    if member_in_template do
      member_template = find_member_template(template, active_type)

      case Enum.find(members, fn m -> m.name == active_type end) do
        nil ->
          %{active_type => normalize_primitive(union_value)}

        member ->
          extracted =
            extract_value(union_value, member.type, [], member_template, resource_lookups)

          %{active_type => extracted}
      end
    else
      nil
    end
  end

  defp extract_union_value(value, _type_info, _template, _resource_lookups),
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

  # Array Handler
  defp extract_array_value(value, inner_type, template, resource_lookups)
       when is_list(value) do
    value
    |> Enum.map(fn item ->
      case extract_value(item, inner_type, [], template, resource_lookups) do
        :skip -> nil
        result -> result
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_array_value(value, _inner_type, _template, _resource_lookups), do: value

  # TypedStruct Handler — types with typescript_field_names
  defp extract_typed_struct_value(value, type_info, template, resource_lookups)
       when is_list(value) do
    map_value = Enum.into(value, %{})
    extract_typed_struct_value(map_value, type_info, template, resource_lookups)
  end

  defp extract_typed_struct_value(value, type_info, template, resource_lookups)
       when is_map(value) do
    normalized = FieldExtractor.normalize_for_extraction(value, template)

    Enum.reduce(template, %{}, fn field_spec, acc ->
      case field_spec do
        field_atom when is_atom(field_atom) ->
          field_value = Map.get(normalized, field_atom)
          sub_type = Type.find_field_type(type_info, field_atom)
          extracted = extract_value(field_value, sub_type, [], [], resource_lookups)
          Map.put(acc, field_atom, extracted)

        {field_atom, nested_template} when is_atom(field_atom) ->
          field_value = Map.get(normalized, field_atom)
          sub_type = Type.find_field_type(type_info, field_atom)

          extracted =
            extract_value(field_value, sub_type, [], nested_template, resource_lookups)

          Map.put(acc, field_atom, extracted)

        _ ->
          acc
      end
    end)
  end

  defp extract_typed_struct_value(value, _type_info, _template, _resource_lookups),
    do: normalize_primitive(value)

  # Typed Map Handler
  defp extract_typed_map_value(value, type_info, template, resource_lookups)
       when is_list(value) do
    map_value = Enum.into(value, %{})
    extract_typed_map_value(map_value, type_info, template, resource_lookups)
  end

  defp extract_typed_map_value(value, type_info, template, resource_lookups)
       when is_map(value) do
    fields = Type.get_fields(type_info)
    normalized = FieldExtractor.normalize_for_extraction(value, template)

    cond do
      template == [] and fields == [] ->
        normalize_primitive(value)

      template == [] ->
        Enum.reduce(fields, %{}, fn field_desc, acc ->
          field_value = Map.get(normalized, field_desc.name)
          extracted = extract_value(field_value, field_desc.type, [], [], resource_lookups)
          Map.put(acc, field_desc.name, extracted)
        end)

      true ->
        Enum.reduce(template, %{}, fn field_spec, acc ->
          case field_spec do
            field_atom when is_atom(field_atom) ->
              field_value = Map.get(normalized, field_atom)
              sub_type = Type.find_field_type(type_info, field_atom)
              extracted = extract_value(field_value, sub_type, [], [], resource_lookups)
              Map.put(acc, field_atom, extracted)

            {field_atom, nested_template} when is_atom(field_atom) ->
              field_value = Map.get(normalized, field_atom)
              sub_type = Type.find_field_type(type_info, field_atom)

              extracted =
                extract_value(field_value, sub_type, [], nested_template, resource_lookups)

              Map.put(acc, field_atom, extracted)

            %{field_name: field_name, index: _index} ->
              field_value = Map.get(normalized, field_name)
              sub_type = Type.find_field_type(type_info, field_name)
              extracted = extract_value(field_value, sub_type, [], [], resource_lookups)
              Map.put(acc, field_name, extracted)

            _ ->
              acc
          end
        end)
    end
  end

  defp extract_typed_map_value(value, _type_info, template, resource_lookups)
       when is_tuple(value) do
    normalized = FieldExtractor.normalize_for_extraction(value, template)
    extract_typed_map_value(normalized, _type_info, template, resource_lookups)
  end

  defp extract_typed_map_value(value, _type_info, _template, resource_lookups)
       when is_list(value) do
    if value != [] and Keyword.keyword?(value) do
      normalized = Map.new(value)
      extract_typed_map_value(normalized, _type_info, _template, resource_lookups)
    else
      normalize_primitive(value)
    end
  end

  defp extract_typed_map_value(value, _type_info, _template, _resource_lookups),
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

  def normalize_value_for_json(value), do: normalize_primitive(value)

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

      is_struct(value) && Helpers.ash_resource?(value.__struct__) ->
        # Resource structs: filter to public fields only
        # Uses Ash introspection since normalize_primitive doesn't have resource_lookups
        normalize_resource_struct_primitive(value)

      is_struct(value) ->
        value
        |> Map.from_struct()
        |> Enum.reduce(%{}, fn {key, val}, acc ->
          Map.put(acc, key, normalize_primitive(val))
        end)

      is_list(value) ->
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

  defp normalize_resource_struct(value, resource, resource_lookups)
       when is_map(resource_lookups) do
    case Map.get(resource_lookups, resource) do
      %AshApiSpec.Resource{fields: fields} when is_map(fields) ->
        public_field_names = MapSet.new(Map.keys(fields))

        value
        |> Map.from_struct()
        |> Enum.reduce(%{}, fn {key, val}, acc ->
          if MapSet.member?(public_field_names, key) do
            Map.put(acc, key, normalize_primitive(val))
          else
            acc
          end
        end)

      _ ->
        normalize_primitive(value)
    end
  end

  defp normalize_resource_struct(value, _resource, _nil_lookups) do
    normalize_resource_struct_primitive(value)
  end

  # Normalize a resource struct by filtering to public fields.
  defp normalize_resource_struct_primitive(value) when is_struct(value) do
    resource = value.__struct__
    resource_lookups = AshTypescript.resource_lookup()

    case Map.get(resource_lookups, resource) do
      %AshApiSpec.Resource{fields: fields} when is_map(fields) ->
        public_field_names = MapSet.new(Map.keys(fields))

        value
        |> Map.from_struct()
        |> Enum.reduce(%{}, fn {key, val}, acc ->
          if MapSet.member?(public_field_names, key) do
            Map.put(acc, key, normalize_primitive(val))
          else
            acc
          end
        end)

      _ ->
        # Resource not in spec — normalize all fields as a plain struct
        value
        |> Map.from_struct()
        |> Enum.reduce(%{}, fn {key, val}, acc ->
          Map.put(acc, key, normalize_primitive(val))
        end)
    end
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
    type = determine_data_type(List.first(results), resource, resource_lookups)
    Enum.map(results, fn item ->
      case extract_value(item, type, [], extraction_template, resource_lookups) do
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
      type = determine_data_type(data, resource, resource_lookups)
      extract_value(data, type, [], extraction_template, resource_lookups)
    end
  end

  defp extract_single_result(data, _template, _resource, _resource_lookups) do
    case data do
      %_struct{} = struct_data -> Map.from_struct(struct_data)
      other -> other
    end
  end

  @doc """
  Determines the `%AshApiSpec.Type{}` for a given data value.
  Returns nil for unknown/primitive types.
  """
  def determine_data_type(nil, resource, resource_lookups) do
    resolve_resource_type(resource, resource_lookups)
  end

  def determine_data_type(data, resource, resource_lookups) do
    cond do
      is_struct(data) && Helpers.ash_resource?(data.__struct__) ->
        resolve_resource_type(data.__struct__, resource_lookups)

      is_struct(data) && Helpers.has_typescript_field_names?(data.__struct__) ->
        AshApiSpec.Generator.TypeResolver.resolve(Ash.Type.Struct, instance_of: data.__struct__)

      match?(%Ash.Union{}, data) ->
        resolve_union_type(resource, resource_lookups)

      is_list(data) && data != [] && Keyword.keyword?(data) ->
        %AshApiSpec.Type{kind: :keyword, module: Ash.Type.Keyword, constraints: []}

      is_tuple(data) ->
        %AshApiSpec.Type{kind: :tuple, module: Ash.Type.Tuple, constraints: []}

      is_map(data) && not is_struct(data) ->
        nil

      resource && Helpers.ash_resource?(resource) && is_struct(data) ->
        resolve_resource_type(resource, resource_lookups)

      true ->
        nil
    end
  end

  defp resolve_resource_type(nil, _resource_lookups), do: nil

  defp resolve_resource_type(resource, _resource_lookups) when is_atom(resource) do
    if Helpers.ash_resource?(resource) do
      %AshApiSpec.Type{
        kind: :resource,
        name: "Resource",
        module: resource,
        resource_module: resource,
        constraints: []
      }
    else
      nil
    end
  end

  defp resolve_union_type(resource, resource_lookups) when is_atom(resource) and is_map(resource_lookups) do
    case Map.get(resource_lookups, resource) do
      %AshApiSpec.Resource{fields: fields} when is_map(fields) ->
        # Find the first union field's type from the spec
        union_field = Enum.find_value(fields, fn {_name, field} ->
          case field.type do
            %AshApiSpec.Type{kind: :union} = t -> t
            %AshApiSpec.Type{kind: :type_ref} = t ->
              resolved = AshApiSpec.Generator.TypeResolver.resolve_definition(t.module)
              if resolved.kind == :union, do: resolved, else: nil
            _ -> nil
          end
        end)

        union_field || %AshApiSpec.Type{kind: :union, module: Ash.Type.Union, constraints: []}

      _ ->
        %AshApiSpec.Type{kind: :union, module: Ash.Type.Union, constraints: []}
    end
  end

  defp resolve_union_type(_resource, _resource_lookups) do
    %AshApiSpec.Type{kind: :union, module: Ash.Type.Union, constraints: []}
  end
end
