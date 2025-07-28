defmodule AshTypescript.Rpc.RequestedFieldsProcessor do
  @moduledoc """
  Processes requested fields for Ash resources, determining which fields should be selected
  vs loaded, and building extraction templates for result processing.

  This module handles different action types:
  - CRUD actions (:read, :create, :update, :destroy) return resource records
  - Generic actions (:action) return arbitrary types as specified in their `returns` field
  """

  @doc """
  Processes requested fields for a given resource and action.

  Returns `{:ok, {select_fields, load_fields, extraction_template}}` or `{:error, error}`.

  ## Parameters

  - `resource` - The Ash resource module
  - `action` - The action name (atom)
  - `requested_fields` - List of field atoms or maps for relationships

  ## Examples

      iex> process(MyApp.Todo, :read, [:id, :title, %{user: [:id, :name]}])
      {:ok, {[:id, :title], [{:user, [:id, :name]}], [:id, :title, [user: [:id, :name]]]}}

      iex> process(MyApp.Todo, :read, [%{user: [:invalid_field]}])
      {:error, %{type: :invalid_field, field: "user.invalidField"}}
  """
  def process(resource, action_name, requested_fields) do
    try do
      # Get the action definition
      action = Ash.Resource.Info.action(resource, action_name)

      unless action do
        raise ArgumentError, "Action #{action_name} not found on resource #{resource}"
      end

      # Determine what type this action returns
      return_type = determine_return_type(resource, action)

      # Process fields based on the return type
      {select, load, template} = process_fields_for_type(return_type, requested_fields, [])

      {:ok, {select, load, template}}
    rescue
      e in ArgumentError -> {:error, %{type: :invalid_field, field: e.message}}
    end
  end

  # Determine what type an action returns for field processing
  defp determine_return_type(resource, action) do
    case action.type do
      type when type in [:read, :create, :update, :destroy] ->
        # CRUD actions return the resource type (or array for reads)
        case type do
          :read -> {:array, {:resource, resource}}
          _ -> {:resource, resource}
        end

      :action ->
        # Generic actions have their return type specified in the `returns` field
        case action.returns do
          # No specific return type specified
          nil -> :any
          return_type -> {:ash_type, return_type, action.constraints || []}
        end
    end
  end

  # Process fields based on the determined return type
  defp process_fields_for_type(return_type, requested_fields, path) do
    case return_type do
      {:resource, resource} ->
        # Process as resource fields
        process_resource_fields(resource, requested_fields, path)

      {:array, {:resource, resource}} ->
        # Array of resources - same field processing as single resource
        process_resource_fields(resource, requested_fields, path)

      {:ash_type, Ash.Type.Map, constraints} ->
        # Map type with field constraints - validate requested fields against map structure
        process_map_fields(constraints, requested_fields, path)

      {:ash_type, {:array, inner_type}, constraints} ->
        # Array type - validate array constraints but field processing depends on inner type
        array_constraints = Keyword.get(constraints, :items, [])
        inner_return_type = {:ash_type, inner_type, array_constraints}
        process_fields_for_type(inner_return_type, requested_fields, path)

      {:ash_type, Ash.Type.Struct, constraints} ->
        # Struct type - check if it has instance_of to determine the struct module
        case Keyword.get(constraints, :instance_of) do
          resource_module when is_atom(resource_module) ->
            # If it's a resource struct, process as resource
            process_resource_fields(resource_module, requested_fields, path)

          _ ->
            # Generic struct - can't validate fields without knowing the struct
            process_generic_fields(requested_fields, path)
        end

      :any ->
        # No type information - can't validate, just pass through
        process_generic_fields(requested_fields, path)

      _ ->
        # Other Ash types (primitives, etc.) - no field selection possible
        if requested_fields != [] do
          raise ArgumentError, "Cannot select fields from primitive type #{inspect(return_type)}"
        end

        {[], [], []}
    end
  end

  # Process fields for resource types (the original logic)
  defp process_resource_fields(resource, fields, path) do
    Enum.reduce(fields, {[], [], []}, fn field, {select, load, template} ->
      case field do
        # Simple field (atom)
        field_name when is_atom(field_name) ->
          case classify_field(resource, field_name, path) do
            :attribute ->
              {select ++ [field_name], load, template ++ [field_name]}

            :loadable ->
              {select, load ++ [{field_name, []}], template ++ [field_name]}

            {:error, :not_found} ->
              field_path = build_field_path(path, field_name)
              raise ArgumentError, field_path
          end

        # Relationship with nested fields (map)
        %{} = field_map ->
          # Process each relationship in the map
          {new_select, new_load, new_template} =
            Enum.reduce(field_map, {select, load, template}, fn {rel_name, nested_fields},
                                                                {s, l, t} ->
              # Verify the relationship exists
              case classify_field(resource, rel_name, path) do
                :loadable ->
                  # Get the destination resource for this relationship
                  relationship = Ash.Resource.Info.relationship(resource, rel_name)
                  dest_resource = relationship && relationship.destination

                  if dest_resource do
                    # Process nested fields recursively
                    new_path = path ++ [rel_name]

                    {nested_select, nested_load, nested_template} =
                      process_resource_fields(dest_resource, nested_fields, new_path)

                    # Build load specification including nested loads
                    # Combine direct fields with nested relationship loads
                    load_fields = case nested_load do
                      [] -> nested_select
                      _ -> nested_select ++ nested_load
                    end
                    
                    load_spec = {rel_name, load_fields}
                    template_kw = [{rel_name, nested_template}]

                    {s, l ++ [load_spec], t ++ [template_kw]}
                  else
                    field_path = build_field_path(path, rel_name)
                    raise ArgumentError, field_path
                  end

                {:error, :not_found} ->
                  field_path = build_field_path(path, rel_name)
                  raise ArgumentError, field_path
              end
            end)

          {new_select, new_load, new_template}
      end
    end)
  end

  # Process fields for map types with field constraints
  defp process_map_fields(constraints, requested_fields, path) do
    field_specs = Keyword.get(constraints, :fields, [])

    Enum.reduce(requested_fields, {[], [], []}, fn field, {select, load, template} ->
      case field do
        field_name when is_atom(field_name) ->
          # Check if this field exists in the map specification
          if Keyword.has_key?(field_specs, field_name) do
            # Map fields are not selected/loaded in the Ash sense, just included in template
            {select, load, template ++ [field_name]}
          else
            field_path = build_field_path(path, field_name)
            raise ArgumentError, field_path
          end

        %{} = _field_map ->
          # Maps generally don't support nested field selection unless they contain embedded resources
          raise ArgumentError,
                "Nested field selection not supported for map fields at #{build_field_path(path, "nested")}"
      end
    end)
  end

  # Process fields for generic/unknown types - no validation possible
  defp process_generic_fields(requested_fields, _path) do
    # For unknown types, we can't validate fields, so we just build a template
    # This is primarily for testing or when return types are not specified
    template =
      Enum.map(requested_fields, fn
        field_name when is_atom(field_name) ->
          field_name

        %{} = field_map ->
          Enum.map(field_map, fn {k, v} -> {k, v} end)
      end)

    {[], [], List.flatten(template)}
  end

  # Classify a field as :attribute, :loadable, or {:error, :not_found}
  defp classify_field(resource, field_name, _path) do
    cond do
      # Check if it's an attribute
      Ash.Resource.Info.attribute(resource, field_name) ->
        :attribute

      # Check if it's a relationship, calculation, or aggregate (all loadable)
      Ash.Resource.Info.relationship(resource, field_name) ||
        Ash.Resource.Info.calculation(resource, field_name) ||
          Ash.Resource.Info.aggregate(resource, field_name) ->
        :loadable

      true ->
        {:error, :not_found}
    end
  end

  # Build a field path for error messages, converting to camelCase
  defp build_field_path(path, field_name) do
    all_parts = path ++ [field_name]
    formatter = AshTypescript.Rpc.output_field_formatter()

    case all_parts do
      [single] ->
        AshTypescript.FieldFormatter.format_field(single, formatter)

      [first | rest] ->
        "#{first}.#{Enum.map_join(rest, ".", fn field -> AshTypescript.FieldFormatter.format_field(field, formatter) end)}"
    end
  end
end
