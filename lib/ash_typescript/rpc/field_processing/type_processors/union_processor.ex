# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.FieldProcessing.TypeProcessors.UnionProcessor do
  @moduledoc """
  Processes union attribute fields with member-specific field selection.

  Union types allow a field to hold values of different types, with each type
  (called a "member") potentially having its own nested structure and fields.
  """

  alias AshTypescript.Rpc.FieldProcessing.{Utilities, Validator}
  alias AshTypescript.TypeSystem.Introspection

  @doc """
  Processes a union attribute field with nested field selection.

  Union field selection format supports:
  - Simple member selection: [:member_name]
  - Member with fields: [%{member_name: member_fields}]
  - Shorthand: %{member_name: member_fields}

  ## Parameters

  - `process_fields_fn` - Function to recursively process nested fields

  ## Examples

      # Select simple members
      [:note, :priority_value]

      # Select member with nested fields
      [%{text: [:id, :text, :formatting]}]

      # Shorthand for single member
      %{text: [:id, :text, :formatting]}
  """
  def process_union_attribute(
        resource,
        field_name,
        nested_fields,
        path,
        select,
        load,
        template,
        process_fields_fn
      ) do
    # Union field selection format: [:member_name, %{member_name: member_fields}]
    # Example: [:note, %{text: [:id, :text, :formatting]}]
    # Also supports shorthand: %{member_name: member_fields} for single member selection

    normalized_fields = normalize_fields(nested_fields)

    Validator.validate_non_empty_fields(normalized_fields, field_name, path, "Union")
    Validator.check_for_duplicate_fields(normalized_fields, path ++ [field_name])

    attribute = Ash.Resource.Info.attribute(resource, field_name)
    union_types = get_union_types(attribute)

    {load_items, template_items} =
      process_union_members(
        normalized_fields,
        union_types,
        path ++ [field_name],
        process_fields_fn,
        :attribute
      )

    new_select = select ++ [field_name]

    new_load =
      if load_items != [] do
        load ++ [{field_name, load_items}]
      else
        load
      end

    {new_select, new_load, template ++ [{field_name, template_items}]}
  end

  @doc """
  Processes union fields given the union types directly.

  This is used for calculations or other contexts where we have union types
  but not an attribute to extract them from.

  ## Parameters

  - `union_types` - Keyword list of union member configurations
  - `requested_fields` - Field selection for union members
  - `path` - Current field path for error messages
  - `process_fields_fn` - Function to recursively process nested fields

  ## Returns

  `{select, load, template}` tuple for the processed union fields
  """
  def process_union_fields(union_types, requested_fields, path, process_fields_fn) do
    normalized_fields = normalize_fields(requested_fields)

    Validator.validate_non_empty_fields(normalized_fields, "union", path, "Union")
    Validator.check_for_duplicate_fields(normalized_fields, path)

    {load_items, template_items} =
      process_union_members(
        normalized_fields,
        union_types,
        path,
        process_fields_fn,
        :union_type
      )

    {[], load_items, template_items}
  end

  # Normalizes field selection format from shorthand map to list format
  defp normalize_fields(fields) do
    case fields do
      %{} = field_map when map_size(field_map) > 0 ->
        # Convert map to list format: %{member: fields} -> [%{member: fields}]
        [field_map]

      fields when is_list(fields) ->
        fields

      _ ->
        fields
    end
  end

  # Processes union members with a unified approach for both attributes and union types
  defp process_union_members(normalized_fields, union_types, path, process_fields_fn, context) do
    Enum.reduce(normalized_fields, {[], []}, fn field_item, {load_acc, template_acc} ->
      case field_item do
        member when is_atom(member) ->
          # Simple union member selection (like :note, :priority_value, :url)
          process_simple_member(member, union_types, path, context, load_acc, template_acc)

        %{} = member_map ->
          # Union member(s) with field selection - process each member in the map
          process_member_map(member_map, union_types, path, process_fields_fn, context, load_acc, template_acc)

        _ ->
          # Invalid field item type
          field_path = build_error_path(path, context)
          error_type = if context == :attribute, do: :invalid_union_field_format, else: :invalid_field_format
          throw({error_type, field_item, field_path})
      end
    end)
  end

  # Process a map of union members with field selection
  defp process_member_map(member_map, union_types, path, process_fields_fn, context, load_acc, template_acc) do
    Enum.reduce(member_map, {load_acc, template_acc}, fn {member, member_fields}, {l_acc, t_acc} ->
      if Keyword.has_key?(union_types, member) do
        member_config = Keyword.get(union_types, member)
        member_return_type = union_member_to_return_type(member_config)
        new_path = path ++ [member]

        # Use the provided field processing function
        {_nested_select, nested_load, nested_template} =
          process_fields_fn.(member_return_type, member_fields, new_path)

        # For union types, only embedded resources with loadable fields (calculations,
        # aggregates) require explicit load statements. The union field selection itself
        # ensures the entire union value is returned by Ash.
        combined_load_fields =
          case member_return_type do
            {:resource, _resource} ->
              # Embedded resource - only load loadable fields (calculations/aggregates)
              nested_load

            _ ->
              # All other types - no load statements needed
              []
          end

        # Different accumulation strategies for attributes vs union types
        case context do
          :attribute ->
            if combined_load_fields != [] do
              {l_acc ++ [{member, combined_load_fields}], t_acc ++ [{member, nested_template}]}
            else
              {l_acc, t_acc ++ [{member, nested_template}]}
            end

          :union_type ->
            {l_acc ++ combined_load_fields, t_acc ++ [{member, nested_template}]}
        end
      else
        field_path = build_error_path(path, context, member)
        error_context = if context == :attribute, do: "union_attribute", else: "union_type"
        throw({:unknown_field, member, error_context, field_path})
      end
    end)
  end

  # Process a simple member selection (atom without nested fields)
  defp process_simple_member(member, union_types, path, context, load_acc, template_acc) do
    if Keyword.has_key?(union_types, member) do
      member_config = Keyword.get(union_types, member)
      member_return_type = union_member_to_return_type(member_config)

      case member_return_type do
        {:ash_type, map_like, constraints}
        when map_like in [Ash.Type.Map, Ash.Type.Keyword, Ash.Type.Tuple] ->
          # Map type with field constraints requires field selection
          field_specs = Keyword.get(constraints, :fields, [])

          if field_specs != [] do
            field_path = build_error_path(path, context, member)
            throw({:requires_field_selection, :complex_type, field_path})
          else
            # Map with no field constraints - simple type
            {load_acc, template_acc ++ [member]}
          end

        {:ash_type, _type, _constraints} ->
          # Simple type - no field selection needed
          {load_acc, template_acc ++ [member]}

        {:resource, _resource} ->
          # Embedded resource requires field selection
          field_path = build_error_path(path, context, member)
          throw({:requires_field_selection, :complex_type, field_path})
      end
    else
      field_path = build_error_path(path, context, member)
      error_context = if context == :attribute, do: "union_attribute", else: "union_type"
      throw({:unknown_field, member, error_context, field_path})
    end
  end

  # Build error path based on context
  defp build_error_path(path, :attribute), do: Utilities.build_field_path(path, nil)
  defp build_error_path(path, :union_type), do: Utilities.build_field_path(path, "union")
  defp build_error_path(path, :attribute, member), do: Utilities.build_field_path(path, member)
  defp build_error_path(path, :union_type, member), do: Utilities.build_field_path(path, member)

  # Helper function to extract union types from attribute constraints
  # Handles both direct union types and array union types
  defp get_union_types(attribute) do
    Introspection.get_union_types(attribute)
  end

  @doc """
  Convert union member configuration to a return type descriptor that
  can be processed by the existing field processing logic.
  """
  def union_member_to_return_type(member_config) do
    member_type = Keyword.get(member_config, :type)
    member_constraints = Keyword.get(member_config, :constraints, [])

    case member_type do
      type when is_atom(type) and type != :map ->
        # Check if it's an embedded resource
        if Introspection.is_embedded_resource?(type) do
          {:resource, type}
        else
          # Regular Ash type (like :string, :integer, etc.)
          {:ash_type, type, member_constraints}
        end

      :map ->
        # Map type - check if it has field constraints
        {:ash_type, Ash.Type.Map, member_constraints}

      _ ->
        # Fallback for other types
        {:ash_type, member_type, member_constraints}
    end
  end
end
