defmodule AshTypescript.Rpc.RequestedFieldsProcessor do
  @moduledoc """
  Processes requested fields for Ash resources, determining which fields should be selected
  vs loaded, and building extraction templates for result processing.

  This module handles different action types:
  - CRUD actions (:read, :create, :update, :destroy) return resource records
  - Generic actions (:action) return arbitrary types as specified in their `returns` field
  """

  @doc """
  Atomizes requested fields by converting standalone strings to atoms and map keys to atoms.

  Uses the configured input field formatter to properly parse field names from client format
  to internal format before converting to atoms.

  ## Parameters

  - `requested_fields` - List of strings/atoms or maps for relationships

  ## Examples

      iex> atomize_requested_fields(["id", "title", %{"user" => ["id", "name"]}])
      [:id, :title, %{user: [:id, :name]}]

      iex> atomize_requested_fields([%{"self" => %{"args" => %{"prefix" => "test"}}}])
      [%{self: %{args: %{prefix: "test"}}}]
  """
  def atomize_requested_fields(requested_fields) when is_list(requested_fields) do
    formatter = AshTypescript.Rpc.input_field_formatter()
    Enum.map(requested_fields, &atomize_field(&1, formatter))
  end

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
    action = Ash.Resource.Info.action(resource, action_name)

    if is_nil(action) do
      throw({:action_not_found, action_name})
    end

    return_type = determine_return_type(resource, action)

    {select, load, template} = process_fields_for_type(return_type, requested_fields, [])
    formatted_template = format_extraction_template(template)

    {:ok, {select, load, formatted_template}}
  catch
    error_tuple -> {:error, error_tuple}
  end

  defp determine_return_type(resource, action) do
    case action.type do
      type when type in [:read, :create, :update, :destroy] ->
        case type do
          :read ->
            if action.get? do
              {:resource, resource}
            else
              {:array, {:resource, resource}}
            end

          _ ->
            {:resource, resource}
        end

      :action ->
        case action.returns do
          nil -> :any
          return_type -> {:ash_type, return_type, action.constraints || []}
        end
    end
  end

  defp process_fields_for_type(return_type, requested_fields, path) do
    case return_type do
      {:resource, resource} ->
        process_resource_fields(resource, requested_fields, path)

      {:array, {:resource, resource}} ->
        process_resource_fields(resource, requested_fields, path)

      {:ash_type, Ash.Type.Map, constraints} ->
        process_map_fields(constraints, requested_fields, path)

      {:ash_type, Ash.Type.Keyword, constraints} ->
        process_map_fields(constraints, requested_fields, path)

      {:ash_type, Ash.Type.Tuple, constraints} ->
        process_tuple_fields(constraints, requested_fields, path)

      {:ash_type, {:array, inner_type}, constraints} ->
        array_constraints = Keyword.get(constraints, :items, [])
        inner_return_type = {:ash_type, inner_type, array_constraints}
        process_fields_for_type(inner_return_type, requested_fields, path)

      {:ash_type, Ash.Type.Struct, constraints} ->
        case Keyword.get(constraints, :instance_of) do
          resource_module when is_atom(resource_module) ->
            process_resource_fields(resource_module, requested_fields, path)

          _ ->
            process_generic_fields(requested_fields, path)
        end

      :any ->
        process_generic_fields(requested_fields, path)

      {:ash_type, type, constraints} when is_atom(type) ->
        fake_attribute = %{type: type, constraints: constraints}

        if is_typed_struct?(fake_attribute) do
          field_specs = Keyword.get(constraints, :fields, [])

          {_field_names, template_items} =
            process_typed_struct_fields(requested_fields, field_specs, path)

          {[], [], template_items}
        else
          if requested_fields != [] do
            throw({:invalid_field_selection, :primitive_type, return_type})
          end

          {[], [], []}
        end

      _ ->
        if requested_fields != [] do
          throw({:invalid_field_selection, :primitive_type, return_type})
        end

        {[], [], []}
    end
  end

  defp process_resource_fields(resource, fields, path) do
    check_for_duplicate_fields(fields, path)

    Enum.reduce(fields, {[], [], []}, fn field, {select, load, template} ->
      field = if is_binary(field), do: String.to_existing_atom(field), else: field

      case field do
        field_name when is_atom(field_name) ->
          case classify_field(resource, field_name, path) do
            :attribute ->
              {select ++ [field_name], load, template ++ [field_name]}

            :calculation ->
              {select, load ++ [field_name], template ++ [field_name]}

            :tuple ->
              field_path = build_field_path(path, field_name)
              throw({:requires_field_selection, :tuple, field_path})

            :calculation_with_args ->
              field_path = build_field_path(path, field_name)
              throw({:calculation_requires_args, field_name, field_path})

            :calculation_complex ->
              field_path = build_field_path(path, field_name)

              throw({:requires_field_selection, :calculation_complex, field_path})

            :aggregate ->
              {select, load ++ [field_name], template ++ [field_name]}

            :complex_aggregate ->
              field_path = build_field_path(path, field_name)

              throw({:requires_field_selection, :complex_aggregate, field_path})

            :relationship ->
              field_path = build_field_path(path, field_name)
              throw({:requires_field_selection, :relationship, field_path})

            :embedded_resource ->
              field_path = build_field_path(path, field_name)
              throw({:requires_field_selection, :embedded_resource, field_path})

            :embedded_resource_array ->
              field_path = build_field_path(path, field_name)
              throw({:requires_field_selection, :embedded_resource_array, field_path})

            :typed_struct ->
              field_path = build_field_path(path, field_name)
              throw({:requires_field_selection, :typed_struct, field_path})

            :union_attribute ->
              field_path = build_field_path(path, field_name)
              throw({:requires_field_selection, :union_attribute, field_path})

            {:error, :not_found} ->
              field_path = build_field_path(path, field_name)
              throw({:unknown_field, field_name, resource, field_path})
          end

        {field_name, nested_fields} ->
          case classify_field(resource, field_name, path) do
            :relationship ->
              process_relationship(
                resource,
                field_name,
                nested_fields,
                path,
                select,
                load,
                template
              )

            :embedded_resource ->
              process_embedded_resource(
                resource,
                field_name,
                nested_fields,
                path,
                select,
                load,
                template
              )

            :embedded_resource_array ->
              process_embedded_resource(
                resource,
                field_name,
                nested_fields,
                path,
                select,
                load,
                template
              )

            :calculation_complex ->
              process_calculation_complex(
                resource,
                field_name,
                nested_fields,
                path,
                select,
                load,
                template
              )

            :complex_aggregate ->
              process_calculation_complex(
                resource,
                field_name,
                nested_fields,
                path,
                select,
                load,
                template
              )

            :typed_struct ->
              process_typed_struct(
                resource,
                field_name,
                nested_fields,
                path,
                select,
                load,
                template
              )

            :union_attribute ->
              process_union_attribute(
                resource,
                field_name,
                nested_fields,
                path,
                select,
                load,
                template
              )

            {:error, :not_found} ->
              field_path = build_field_path(path, field_name)
              throw({:unknown_field, field_name, resource, field_path})

            _ ->
              field_path = build_field_path(path, field_name)
              throw({:invalid_field_selection, field_name, :simple_field, field_path})
          end

        %{} = field_map ->
          {new_select, new_load, new_template} =
            Enum.reduce(field_map, {select, load, template}, fn {field_name, nested_fields},
                                                                {s, l, t} ->
              case classify_field(resource, field_name, path) do
                :relationship ->
                  process_relationship(resource, field_name, nested_fields, path, s, l, t)

                :embedded_resource ->
                  process_embedded_resource(resource, field_name, nested_fields, path, s, l, t)

                :embedded_resource_array ->
                  # Handle array of embedded resources with nested field selection
                  process_embedded_resource(
                    resource,
                    field_name,
                    nested_fields,
                    path,
                    s,
                    l,
                    t
                  )

                :tuple ->
                  process_tuple_type(resource, field_name, nested_fields, path, s, l, t)

                :typed_struct ->
                  # Handle typed struct with nested field selection
                  process_typed_struct(resource, field_name, nested_fields, path, s, l, t)

                :union_attribute ->
                  # Handle union attribute with nested field selection
                  process_union_attribute(resource, field_name, nested_fields, path, s, l, t)

                :calculation_with_args ->
                  # Validate that it has the right structure for calculation with args
                  if is_calculation_with_args(nested_fields) do
                    process_calculation_with_args(
                      resource,
                      field_name,
                      nested_fields,
                      path,
                      s,
                      l,
                      t
                    )
                  else
                    field_path = build_field_path(path, field_name)

                    throw({:invalid_calculation_args, field_name, field_path})
                  end

                :calculation ->
                  # This calculation doesn't take arguments but was requested with nested structure
                  field_path = build_field_path(path, field_name)
                  throw({:invalid_calculation_args, field_name, field_path})

                :calculation_complex ->
                  process_calculation_complex(resource, field_name, nested_fields, path, s, l, t)

                :aggregate ->
                  # This aggregate returns primitive type and doesn't support nested field selection
                  field_path = build_field_path(path, field_name)

                  throw({:invalid_field_selection, field_name, :aggregate, field_path})

                :complex_aggregate ->
                  process_complex_aggregate(resource, field_name, nested_fields, path, s, l, t)

                :attribute ->
                  # Attributes don't support nested field selection
                  field_path = build_field_path(path, field_name)

                  throw({:field_does_not_support_nesting, field_path})

                {:error, :not_found} ->
                  field_path = build_field_path(path, field_name)
                  throw({:unknown_field, field_name, resource, field_path})
              end
            end)

          {new_select, new_load, new_template}
      end
    end)
  end

  defp process_map_fields(constraints, requested_fields, path) do
    check_for_duplicate_fields(requested_fields, path)
    field_specs = Keyword.get(constraints, :fields, [])

    Enum.reduce(requested_fields, {[], [], []}, fn field, {select, load, template} ->
      case field do
        field_name when is_atom(field_name) ->
          if Keyword.has_key?(field_specs, field_name) do
            {select, load, template ++ [field_name]}
          else
            field_path = build_field_path(path, field_name)
            throw({:unknown_field, field_name, "map", field_path})
          end

        %{} = field_map ->
          # Handle nested field selection for complex types within maps
          Enum.reduce(field_map, {select, load, template}, fn {field_name, nested_fields},
                                                              {s, l, t} ->
            if Keyword.has_key?(field_specs, field_name) do
              field_spec = Keyword.get(field_specs, field_name)
              field_type = Keyword.get(field_spec, :type)
              field_constraints = Keyword.get(field_spec, :constraints, [])

              # Determine the return type for this field
              field_return_type = {:ash_type, field_type, field_constraints}
              new_path = path ++ [field_name]

              # Process the nested fields based on the field's type
              {_nested_select, _nested_load, nested_template} =
                process_fields_for_type(field_return_type, nested_fields, new_path)

              # For map fields, we don't need to add to select/load, just template
              {s, l, t ++ [{field_name, nested_template}]}
            else
              field_path = build_field_path(path, field_name)
              throw({:unknown_field, field_name, "map", field_path})
            end
          end)
      end
    end)
  end

  defp process_tuple_type(resource, field_name, nested_fields, path, select, load, template) do
    validate_non_empty_fields(nested_fields, field_name, path, "Type")

    attribute = Ash.Resource.Info.attribute(resource, field_name)
    # field_specs = Keyword.get(attribute.constraints, :fields, [])

    new_path = path ++ [field_name]

    {[], [], template_items} =
      process_tuple_fields(attribute.constraints, nested_fields, new_path)

    new_select = select ++ [field_name]

    {new_select, load, template ++ [{field_name, template_items}]}
  end

  defp process_tuple_fields(constraints, requested_fields, path) do
    check_for_duplicate_fields(requested_fields, path)
    field_specs = Keyword.get(constraints, :fields, [])
    field_names = Enum.map(field_specs, &elem(&1, 0))

    Enum.reduce(requested_fields, {[], [], []}, fn field, {select, load, template} ->
      field = if is_binary(field), do: String.to_existing_atom(field), else: field

      case field do
        field_name when is_atom(field_name) ->
          if Keyword.has_key?(field_specs, field_name) do
            index = Enum.find_index(field_names, &(&1 == field_name))
            {select, load, template ++ [%{field_name: field_name, index: index}]}
          else
            field_path = build_field_path(path, field_name)
            throw({:unknown_field, field_name, "tuple", field_path})
          end

        %{} = field_map ->
          # Handle nested field selection for complex types within maps
          Enum.reduce(field_map, {select, load, template}, fn {field_name, nested_fields},
                                                              {s, l, t} ->
            if Keyword.has_key?(field_specs, field_name) do
              field_spec = Keyword.get(field_specs, field_name)
              field_type = Keyword.get(field_spec, :type)
              field_constraints = Keyword.get(field_spec, :constraints, [])

              # Determine the return type for this field
              field_return_type = {:ash_type, field_type, field_constraints}
              new_path = path ++ [field_name]

              # Process the nested fields based on the field's type
              {_nested_select, _nested_load, nested_template} =
                process_fields_for_type(field_return_type, nested_fields, new_path)

              # For map fields, we don't need to add to select/load, just template
              {s, l, t ++ [{field_name, nested_template}]}
            else
              field_path = build_field_path(path, field_name)
              throw({:unknown_field, field_name, "map", field_path})
            end
          end)
      end
    end)
  end

  defp process_generic_fields(requested_fields, _path) do
    template =
      Enum.map(requested_fields, fn
        field_name when is_atom(field_name) ->
          field_name

        %{} = field_map ->
          Enum.map(field_map, fn {k, v} -> {k, v} end)
      end)

    {[], [], List.flatten(template)}
  end

  defp is_calculation_with_args(nested_fields) do
    is_map(nested_fields) and Map.has_key?(nested_fields, :args)
  end

  defp process_calculation_with_args(
         resource,
         calc_name,
         nested_fields,
         path,
         select,
         load,
         template
       ) do
    args = Map.get(nested_fields, :args)
    fields = Map.get(nested_fields, :fields, [])
    calculation = Ash.Resource.Info.calculation(resource, calc_name)

    if is_nil(calculation) do
      field_path = build_field_path(path, calc_name)
      throw({:unknown_field, calc_name, resource, field_path})
    end

    calc_return_type = determine_calculation_return_type(calculation)

    field_path = build_field_path(path, calc_name)
    fields_provided = Map.has_key?(nested_fields, :fields)

    case calc_return_type do
      {:ash_type, {:array, inner_type}, _constraints} ->
        if is_primitive_type?(inner_type) do
          # Arrays of primitive types should not accept fields parameter at all
          if fields_provided do
            field_path = build_field_path(path, calc_name)
            throw({:invalid_field_selection, calc_name, :calculation, field_path})
          end
        end

      {:ash_type, Ash.Type.Struct, _constraints} ->
        # Struct types require fields to be provided and non-empty
        validate_complex_type_fields(fields_provided, fields, field_path, "Calculation")

      {:ash_type, type, _constraints} ->
        if is_primitive_type?(type) do
          # Primitive types should not accept fields parameter at all
          if fields_provided do
            field_path = build_field_path(path, calc_name)
            throw({:invalid_field_selection, calc_name, :calculation, field_path})
          end
        end

      {:resource, _resource} ->
        # Resource types require fields to be provided and non-empty
        validate_complex_type_fields(fields_provided, fields, field_path, "Calculation")
    end

    new_path = path ++ [calc_name]

    {nested_select, nested_load, nested_template} =
      process_fields_for_type(calc_return_type, fields, new_path)

    load_fields =
      case nested_load do
        [] -> nested_select
        _ -> nested_select ++ nested_load
      end

    load_spec =
      if load_fields == [] do
        # When there are no nested fields to load, just pass the args directly
        {calc_name, args}
      else
        # When there are nested fields, use the tuple format
        {calc_name, {args, load_fields}}
      end

    # For calculations, if there's no nested template (empty fields), just use the calc name
    # Otherwise, include the nested structure
    template_item =
      if nested_template == [] do
        calc_name
      else
        {calc_name, nested_template}
      end

    {select, load ++ [load_spec], template ++ [template_item]}
  end

  defp process_complex_aggregate(resource, agg_name, nested_fields, path, select, load, template) do
    # Validate that nested fields are not empty (custom message for aggregates)
    if nested_fields == [] do
      field_path = build_field_path(path, agg_name)

      throw({:requires_field_selection, :complex_aggregate, field_path})
    end

    aggregate = Ash.Resource.Info.aggregate(resource, agg_name)
    agg_return_type = determine_aggregate_return_type(resource, aggregate)

    new_path = path ++ [agg_name]

    {nested_select, nested_load, nested_template} =
      process_fields_for_type(agg_return_type, nested_fields, new_path)

    load_spec = build_load_spec(agg_name, nested_select, nested_load)

    {select, load ++ [load_spec], template ++ [{agg_name, nested_template}]}
  end

  defp process_calculation_complex(
         resource,
         calc_name,
         nested_fields,
         path,
         select,
         load,
         template
       ) do
    # Validate that nested fields are not empty
    if nested_fields == [] do
      field_path = build_field_path(path, calc_name)

      throw({:requires_field_selection, :calculation_complex, field_path})
    end

    calculation = Ash.Resource.Info.calculation(resource, calc_name)

    if is_nil(calculation) do
      field_path = build_field_path(path, calc_name)
      throw({:unknown_field, calc_name, resource, field_path})
    end

    calc_return_type = determine_calculation_return_type(calculation)

    new_path = path ++ [calc_name]

    {nested_select, nested_load, nested_template} =
      process_fields_for_type(calc_return_type, nested_fields, new_path)

    load_spec = build_load_spec(calc_name, nested_select, nested_load)

    {select, load ++ [load_spec], template ++ [{calc_name, nested_template}]}
  end

  defp process_relationship(resource, rel_name, nested_fields, path, select, load, template) do
    relationship = Ash.Resource.Info.relationship(resource, rel_name)
    dest_resource = relationship && relationship.destination

    if dest_resource do
      process_nested_resource_fields(
        dest_resource,
        rel_name,
        nested_fields,
        path,
        select,
        load,
        template
      )
    else
      field_path = build_field_path(path, rel_name)
      throw({:unknown_field, rel_name, resource, field_path})
    end
  end

  defp process_embedded_resource(
         resource,
         field_name,
         nested_fields,
         path,
         select,
         load,
         template
       ) do
    validate_non_empty_fields(nested_fields, field_name, path, "Relationship")

    attribute = Ash.Resource.Info.attribute(resource, field_name)
    embedded_resource = extract_embedded_resource_type(attribute.type)

    new_path = path ++ [field_name]

    {_nested_select, nested_load, nested_template} =
      process_resource_fields(embedded_resource, nested_fields, new_path)

    new_select = select ++ [field_name]

    new_load =
      if nested_load != [] do
        load ++ [{field_name, nested_load}]
      else
        load
      end

    {new_select, new_load, template ++ [{field_name, nested_template}]}
  end

  defp extract_embedded_resource_type({:array, embedded_resource}), do: embedded_resource
  defp extract_embedded_resource_type(embedded_resource), do: embedded_resource

  defp process_typed_struct(resource, field_name, nested_fields, path, select, load, template) do
    validate_non_empty_fields(nested_fields, field_name, path, "TypedStruct")

    attribute = Ash.Resource.Info.attribute(resource, field_name)
    field_specs = Keyword.get(attribute.constraints, :fields, [])

    new_path = path ++ [field_name]

    {_field_names, template_items} =
      process_typed_struct_fields(nested_fields, field_specs, new_path)

    new_select = select ++ [field_name]

    {new_select, load, template ++ [{field_name, template_items}]}
  end

  defp process_typed_struct_fields(requested_fields, field_specs, path) do
    check_for_duplicate_fields(requested_fields, path)

    {field_names, template_items} =
      Enum.reduce(requested_fields, {[], []}, fn field, {names, template} ->
        case field do
          field_atom when is_atom(field_atom) or is_binary(field_atom) ->
            field_atom =
              if is_binary(field_atom) do
                String.to_existing_atom(field_atom)
              else
                field_atom
              end

            if Keyword.has_key?(field_specs, field_atom) do
              {names ++ [field_atom], template ++ [field_atom]}
            else
              field_path = build_field_path(path, field_atom)
              throw({:unknown_field, field_atom, "typed_struct", field_path})
            end

          %{} = field_map ->
            # Handle nested field selection for maps with field constraints
            {new_names, new_template} =
              Enum.reduce(field_map, {names, template}, fn {field_name, nested_fields}, {n, t} ->
                if Keyword.has_key?(field_specs, field_name) do
                  field_spec = Keyword.get(field_specs, field_name)
                  field_type = Keyword.get(field_spec, :type)
                  field_constraints = Keyword.get(field_spec, :constraints, [])

                  # Determine the return type for this field
                  field_return_type = {:ash_type, field_type, field_constraints}
                  new_path = path ++ [field_name]

                  # Process the nested fields based on the field's type
                  {_nested_select, _nested_load, nested_template} =
                    process_fields_for_type(field_return_type, nested_fields, new_path)

                  # For typed struct fields, we only need the template
                  {n ++ [field_name], t ++ [{field_name, nested_template}]}
                else
                  field_path = build_field_path(path, field_name)
                  throw({:unknown_field, field_name, "typed_struct", field_path})
                end
              end)

            {new_names, new_template}
        end
      end)

    {field_names, template_items}
  end

  defp process_union_attribute(resource, field_name, nested_fields, path, select, load, template) do
    # Union field selection format: [:member_name, %{member_name: member_fields}]
    # Example: [:note, %{text: [:id, :text, :formatting]}]
    # Also supports shorthand: %{member_name: member_fields} for single member selection

    # Normalize shorthand map format to list format
    normalized_fields =
      case nested_fields do
        %{} = field_map when map_size(field_map) > 0 ->
          # Convert map to list format: %{member: fields} -> [%{member: fields}]
          [field_map]

        fields when is_list(fields) ->
          fields

        _ ->
          nested_fields
      end

    validate_non_empty_fields(normalized_fields, field_name, path, "Union")
    check_for_duplicate_fields(normalized_fields, path ++ [field_name])

    attribute = Ash.Resource.Info.attribute(resource, field_name)
    union_types = get_union_types(attribute)

    {load_items, template_items} =
      Enum.reduce(normalized_fields, {[], []}, fn field_item, {load_acc, template_acc} ->
        case field_item do
          member when is_atom(member) ->
            # Simple union member selection (like :note, :priority_value, :url)
            if Keyword.has_key?(union_types, member) do
              member_config = Keyword.get(union_types, member)

              # Check if this simple member actually requires field selection
              member_return_type = union_member_to_return_type(member_config)

              case member_return_type do
                {:ash_type, map_like, constraints}
                when map_like in [Ash.Type.Map, Ash.Type.Keyword, Ash.Type.Tuple] ->
                  # Map type with field constraints requires field selection
                  field_specs = Keyword.get(constraints, :fields, [])

                  if field_specs != [] do
                    field_path = build_field_path(path ++ [field_name], member)
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
                  field_path = build_field_path(path ++ [field_name], member)
                  throw({:requires_field_selection, :complex_type, field_path})
              end
            else
              field_path = build_field_path(path ++ [field_name], member)
              throw({:unknown_field, member, "union_attribute", field_path})
            end

          %{} = member_map ->
            # Union member(s) with field selection - process each member in the map
            # Map can have one or more key-value pairs
            Enum.reduce(member_map, {load_acc, template_acc}, fn {member, member_fields},
                                                                 {l_acc, t_acc} ->
              if Keyword.has_key?(union_types, member) do
                member_config = Keyword.get(union_types, member)

                # Convert union member config to return type descriptor
                member_return_type = union_member_to_return_type(member_config)
                new_path = path ++ [field_name, member]

                # Use existing field processing logic
                {_nested_select, nested_load, nested_template} =
                  process_fields_for_type(member_return_type, member_fields, new_path)

                # For union types, only embedded resources with loadable fields (calculations,
                # aggregates) require explicit load statements. The union field selection itself
                # ensures the entire union value is returned by Ash.
                # - Embedded resources: Only load calculations/aggregates
                # - Maps with field constraints: No load statements needed
                # - Primitives: No load statements needed
                combined_load_fields =
                  case member_return_type do
                    {:resource, _resource} ->
                      # Embedded resource - only load loadable fields (calculations/aggregates)
                      nested_load

                    _ ->
                      # All other types (maps, primitives, etc.) - no load statements needed
                      # The union field selection ensures the entire value is returned
                      []
                  end

                if combined_load_fields != [] do
                  {l_acc ++ [{member, combined_load_fields}],
                   t_acc ++ [{member, nested_template}]}
                else
                  {l_acc, t_acc ++ [{member, nested_template}]}
                end
              else
                field_path = build_field_path(path ++ [field_name], member)
                throw({:unknown_field, member, "union_attribute", field_path})
              end
            end)

          _ ->
            # Invalid field item type
            field_path = build_field_path(path, field_name)
            throw({:invalid_union_field_format, field_path})
        end
      end)

    new_select = select ++ [field_name]

    new_load =
      if load_items != [] do
        load ++ [{field_name, load_items}]
      else
        load
      end

    {new_select, new_load, template ++ [{field_name, template_items}]}
  end

  # Helper function to extract union types from attribute constraints
  # Handles both direct union types and array union types
  defp get_union_types(attribute) do
    case attribute.type do
      Ash.Type.Union ->
        Keyword.get(attribute.constraints, :types, [])

      {:array, Ash.Type.Union} ->
        items_constraints = Keyword.get(attribute.constraints, :items, [])
        Keyword.get(items_constraints, :types, [])
    end
  end

  # Convert union member configuration to a return type descriptor that
  # can be processed by the existing field processing logic
  defp union_member_to_return_type(member_config) do
    member_type = Keyword.get(member_config, :type)
    member_constraints = Keyword.get(member_config, :constraints, [])

    case member_type do
      type when is_atom(type) and type != :map ->
        # Check if it's an embedded resource
        if is_embedded?(type) do
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

  defp determine_calculation_return_type(calculation) do
    case calculation.type do
      Ash.Type.Struct ->
        case Keyword.get(calculation.constraints || [], :instance_of) do
          resource_module when is_atom(resource_module) ->
            {:resource, resource_module}

          _ ->
            {:ash_type, calculation.type, calculation.constraints || []}
        end

      type ->
        {:ash_type, type, calculation.constraints || []}
    end
  end

  @primitive_types [
    Ash.Type.Integer,
    Ash.Type.String,
    Ash.Type.Boolean,
    Ash.Type.Float,
    Ash.Type.Decimal,
    Ash.Type.Date,
    Ash.Type.DateTime,
    Ash.Type.NaiveDatetime,
    Ash.Type.UtcDatetime,
    Ash.Type.Atom,
    Ash.Type.UUID,
    Ash.Type.Binary
  ]

  defp is_primitive_type?(type), do: type in @primitive_types

  defp validate_non_empty_fields(nested_fields, field_name, path, error_type \\ "Relationship") do
    if not is_list(nested_fields) do
      field_path = build_field_path(path, field_name)

      throw(
        {:unsupported_field_combination, :relationship, field_name, nested_fields, field_path}
      )
    end

    if nested_fields == [] do
      field_path = build_field_path(path, field_name)

      throw({:requires_field_selection, String.downcase(error_type), field_path})
    end
  end

  defp build_load_spec(field_name, nested_select, nested_load) do
    load_fields =
      case nested_load do
        [] -> nested_select
        _ -> nested_select ++ nested_load
      end

    {field_name, load_fields}
  end

  defp process_nested_resource_fields(
         resource,
         field_name,
         nested_fields,
         path,
         select,
         load,
         template
       ) do
    validate_non_empty_fields(nested_fields, field_name, path)

    new_path = path ++ [field_name]

    {nested_select, nested_load, nested_template} =
      process_resource_fields(resource, nested_fields, new_path)

    load_spec = build_load_spec(field_name, nested_select, nested_load)

    {select, load ++ [load_spec], template ++ [{field_name, nested_template}]}
  end

  defp validate_complex_type_fields(fields_provided, fields, field_path, _type_description) do
    if not fields_provided do
      throw({:requires_field_selection, :complex_type, field_path})
    end

    if fields == [] do
      throw({:requires_field_selection, :complex_type, field_path})
    end
  end

  defp determine_aggregate_return_type(resource, aggregate) do
    case aggregate.kind do
      :count ->
        {:ash_type, Ash.Type.Integer, []}

      :exists ->
        {:ash_type, Ash.Type.Boolean, []}

      :sum ->
        {:ash_type, Ash.Type.Integer, []}

      :avg ->
        {:ash_type, Ash.Type.Float, []}

      kind when kind in [:min, :max, :first, :last] ->
        if aggregate.field do
          relationship = Ash.Resource.Info.relationship(resource, aggregate.relationship_path)
          dest_resource = relationship && relationship.destination

          if dest_resource do
            if attribute = Ash.Resource.Info.attribute(dest_resource, aggregate.field) do
              {:ash_type, attribute.type, attribute.constraints || []}
            else
              {:ash_type, Ash.Type.String, []}
            end
          else
            {:ash_type, Ash.Type.String, []}
          end
        else
          relationship = Ash.Resource.Info.relationship(resource, aggregate.relationship_path)
          dest_resource = relationship && relationship.destination

          if dest_resource do
            {:resource, dest_resource}
          else
            {:ash_type, Ash.Type.String, []}
          end
        end

      :list ->
        if aggregate.field do
          relationship = Ash.Resource.Info.relationship(resource, aggregate.relationship_path)
          dest_resource = relationship && relationship.destination

          if dest_resource do
            if attribute = Ash.Resource.Info.attribute(dest_resource, aggregate.field) do
              {:ash_type, {:array, attribute.type}, []}
            else
              {:ash_type, {:array, Ash.Type.String}, []}
            end
          else
            {:ash_type, {:array, Ash.Type.String}, []}
          end
        else
          relationship = Ash.Resource.Info.relationship(resource, aggregate.relationship_path)
          dest_resource = relationship && relationship.destination

          if dest_resource do
            {:array, {:resource, dest_resource}}
          else
            {:ash_type, {:array, Ash.Type.String}, []}
          end
        end

      _ ->
        {:ash_type, Ash.Type.String, []}
    end
  end

  defp classify_field(resource, field_name, _path) do
    cond do
      attribute = Ash.Resource.Info.public_attribute(resource, field_name) ->
        case attribute.type do
          type_module when is_atom(type_module) ->
            classify_ash_type(type_module, attribute, false)

          {:array, inner_type} when is_atom(inner_type) ->
            classify_ash_type(inner_type, attribute, true)

          _ ->
            :attribute
        end

      Ash.Resource.Info.public_relationship(resource, field_name) ->
        :relationship

      calculation = Ash.Resource.Info.public_calculation(resource, field_name) ->
        if accepts_arguments?(calculation) do
          :calculation_with_args
        else
          case determine_calculation_return_type(calculation) do
            {:resource, _} ->
              :calculation_complex

            {:ash_type, Ash.Type.Struct, _} ->
              :calculation_complex

            {:ash_type, {:array, inner_type}, _} when inner_type == Ash.Type.Struct ->
              :calculation_complex

            {:ash_type, type, constraints} when is_atom(type) ->
              # Check if this is a TypedStruct module by creating a fake attribute
              fake_attribute = %{type: type, constraints: constraints}

              if is_typed_struct?(fake_attribute) do
                :calculation_complex
              else
                :calculation
              end

            _ ->
              :calculation
          end
        end

      aggregate = Ash.Resource.Info.public_aggregate(resource, field_name) ->
        case determine_aggregate_return_type(resource, aggregate) do
          {:resource, _} -> :complex_aggregate
          {:array, {:resource, _}} -> :complex_aggregate
          _ -> :aggregate
        end

      true ->
        {:error, :not_found}
    end
  end

  defp classify_ash_type(type_module, attribute, is_array) do
    cond do
      type_module == Ash.Type.Union ->
        :union_attribute

      is_embedded?(type_module) ->
        if is_array, do: :embedded_resource_array, else: :embedded_resource

      type_module == Ash.Type.Tuple ->
        :tuple

      is_typed_struct?(attribute) ->
        :typed_struct

      # Handle keyword and tuple types with field constraints
      type_module in [Ash.Type.Keyword, Ash.Type.Tuple] ->
        :typed_struct

      true ->
        :attribute
    end
  end

  defp accepts_arguments?(calculation) do
    case calculation.arguments do
      [] -> false
      nil -> false
      args when is_list(args) -> length(args) > 0
    end
  end

  defp is_embedded?(type) do
    Ash.Resource.Info.resource?(type) and Ash.Resource.Info.embedded?(type)
  end

  defp is_typed_struct?(attribute) do
    constraints = attribute.constraints || []

    with true <- Keyword.has_key?(constraints, :fields),
         true <- Keyword.has_key?(constraints, :instance_of),
         instance_of when is_atom(instance_of) <- Keyword.get(constraints, :instance_of) do
      true
    else
      _ -> false
    end
  end

  defp build_field_path(path, field_name) do
    all_parts = path ++ [field_name]
    formatter = AshTypescript.Rpc.output_field_formatter()

    case all_parts do
      [single] ->
        AshTypescript.FieldFormatter.format_field(single, formatter)

      [first | rest] ->
        formatted_first = AshTypescript.FieldFormatter.format_field(first, formatter)

        "#{formatted_first}.#{Enum.map_join(rest, ".", fn field -> AshTypescript.FieldFormatter.format_field(field, formatter) end)}"
    end
  end

  defp atomize_field(field, formatter) do
    case field do
      field_name when is_binary(field_name) ->
        AshTypescript.FieldFormatter.parse_input_field(field_name, formatter)

      field_name when is_atom(field_name) ->
        field_name

      %{} = field_map ->
        Enum.into(field_map, %{}, fn {key, value} ->
          atom_key =
            case key do
              k when is_binary(k) ->
                AshTypescript.FieldFormatter.parse_input_field(k, formatter)

              k when is_atom(k) ->
                k
            end

          atomized_value = atomize_field_value(value, formatter)
          {atom_key, atomized_value}
        end)

      other ->
        other
    end
  end

  defp atomize_field_value(value, formatter) do
    case value do
      list when is_list(list) ->
        Enum.map(list, &atomize_field(&1, formatter))

      %{} = map ->
        atomize_field(map, formatter)

      primitive ->
        primitive
    end
  end

  defp check_for_duplicate_fields(fields, path) do
    field_names =
      Enum.flat_map(fields, fn field ->
        case field do
          field_name when is_atom(field_name) ->
            [field_name]

          field_name when is_binary(field_name) ->
            try do
              [String.to_existing_atom(field_name)]
            rescue
              _ ->
                throw({:invalid_field_type, field_name, path})
            end

          %{} = field_map ->
            Map.keys(field_map)

          {field_name, _field_spec} ->
            [field_name]

          invalid_field ->
            throw({:invalid_field_type, invalid_field, path})
        end
      end)

    duplicate_fields =
      field_names
      |> Enum.frequencies()
      |> Enum.filter(fn {_field, count} -> count > 1 end)
      |> Enum.map(fn {field, _count} -> field end)

    if !Enum.empty?(duplicate_fields) do
      duplicate_field = List.first(duplicate_fields)
      field_path = build_field_path(path, duplicate_field)
      throw({:duplicate_field, duplicate_field, field_path})
    end
  end

  defp format_extraction_template(template) do
    {atoms, keyword_pairs} =
      Enum.reduce(template, {[], []}, fn item, {atoms, kw_pairs} ->
        case item do
          # Tuple types store the index only
          {key, value} when is_atom(key) and is_map(value) ->
            {atoms, kw_pairs ++ [{key, value}]}

          {key, value} when is_atom(key) ->
            {atoms, kw_pairs ++ [{key, format_extraction_template(value)}]}

          atom when is_atom(atom) ->
            {atoms ++ [atom], kw_pairs}

          other ->
            {atoms ++ [other], kw_pairs}
        end
      end)

    atoms ++ keyword_pairs
  end
end
