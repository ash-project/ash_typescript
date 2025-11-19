# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.FieldProcessing.FieldProcessor do
  @moduledoc """
  Core field processing orchestration module.

  This module coordinates field processing across different types (resources, maps, tuples, etc.)
  and delegates to specialized type processors for complex types like unions and calculations.
  """

  alias AshTypescript.Rpc.FieldProcessing.{
    FieldClassifier,
    Utilities,
    Validator
  }

  alias AshTypescript.Rpc.FieldProcessing.TypeProcessors.{
    CalculationProcessor,
    TupleProcessor,
    UnionProcessor
  }

  alias AshTypescript.TypeSystem.Introspection

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

    return_type = FieldClassifier.determine_return_type(resource, action)

    {select, load, template} = process_fields_for_type(return_type, requested_fields, [])
    formatted_template = Utilities.format_extraction_template(template)

    {:ok, {select, load, formatted_template}}
  catch
    error_tuple -> {:error, error_tuple}
  end

  @doc """
  Processes fields based on the return type.

  This is the central dispatcher that routes to appropriate processing functions
  based on the type of data being returned.
  """
  def process_fields_for_type(return_type, requested_fields, path) do
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
        TupleProcessor.process_tuple_fields(
          constraints,
          requested_fields,
          path,
          &process_fields_for_type/3
        )

      {:ash_type, {:array, inner_type}, constraints} ->
        array_constraints = Keyword.get(constraints, :items, [])
        inner_return_type = {:ash_type, inner_type, array_constraints}
        process_fields_for_type(inner_return_type, requested_fields, path)

      {:ash_type, Ash.Type.Struct, constraints} ->
        # Check if this has field constraints (struct with fields like TypedStruct)
        fields = Keyword.get(constraints, :fields)
        instance_of = Keyword.get(constraints, :instance_of)

        cond do
          # Struct with both instance_of and fields - process like Map with fields
          fields != nil and instance_of != nil ->
            process_field_constrained_type(constraints, requested_fields, path)

          # Struct with instance_of only - might be a resource
          instance_of != nil and Ash.Resource.Info.resource?(instance_of) ->
            process_resource_fields(instance_of, requested_fields, path)

          # Generic struct or no constraints
          true ->
            process_generic_fields(requested_fields, path)
        end

      :any ->
        process_generic_fields(requested_fields, path)

      {:ash_type, type, constraints} when is_atom(type) ->
        {unwrapped_type, unwrapped_constraints} =
          Introspection.unwrap_new_type(type, constraints)

        cond do
          unwrapped_type == Ash.Type.Union ->
            union_types = Keyword.get(unwrapped_constraints, :types, [])

            UnionProcessor.process_union_fields(
              union_types,
              requested_fields,
              path,
              &process_fields_for_type/3
            )

          # Tuple type (after unwrapping NewType)
          unwrapped_type == Ash.Type.Tuple ->
            TupleProcessor.process_tuple_fields(
              unwrapped_constraints,
              requested_fields,
              path,
              &process_fields_for_type/3
            )

          # Type with field constraints (Map, Keyword, Struct with fields, TypedStruct)
          Keyword.has_key?(unwrapped_constraints, :fields) ->
            process_field_constrained_type(unwrapped_constraints, requested_fields, path)

          # Primitive type or no special handling
          true ->
            if requested_fields != [] do
              throw(
                {:invalid_field_selection, :primitive_type, return_type, requested_fields, path}
              )
            end

            {[], [], []}
        end

      _ ->
        if requested_fields != [] do
          throw({:invalid_field_selection, :primitive_type, return_type, requested_fields, path})
        end

        {[], [], []}
    end
  end

  @doc """
  Processes fields for a resource, handling attributes, calculations, relationships, etc.
  """
  def process_resource_fields(resource, fields, path) do
    Validator.check_for_duplicate_fields(fields, path)

    Enum.reduce(fields, {[], [], []}, fn field, {select, load, template} ->
      field = if is_binary(field), do: String.to_existing_atom(field), else: field

      case field do
        field_name when is_atom(field_name) ->
          process_simple_field(resource, field_name, path, select, load, template)

        {field_name, nested_fields} ->
          process_nested_field_tuple(
            resource,
            field_name,
            nested_fields,
            path,
            select,
            load,
            template
          )

        %{} = field_map ->
          process_field_map(resource, field_map, path, select, load, template)
      end
    end)
  end

  defp process_simple_field(resource, field_name, path, select, load, template) do
    field_name = AshTypescript.Resource.Info.get_original_field_name(resource, field_name)

    case FieldClassifier.classify_field(resource, field_name, path) do
      :attribute ->
        {select ++ [field_name], load, template ++ [field_name]}

      field_type when field_type in [:calculation, :aggregate] ->
        {select, load ++ [field_name], template ++ [field_name]}

      :calculation_with_args ->
        throw({:calculation_requires_args, field_name, path})

      field_type
      when field_type in [
             :tuple,
             :calculation_complex,
             :complex_aggregate,
             :relationship,
             :embedded_resource,
             :embedded_resource_array,
             :field_constrained_type,
             :union_attribute
           ] ->
        throw({:requires_field_selection, field_type, field_name, path})

      {:error, :not_found} ->
        throw({:unknown_field, field_name, resource, path})
    end
  end

  # Core dispatch logic used by both process_nested_field_tuple and process_field_map.
  # Handles all field types (relationships, calculations, embedded resources, unions, etc.)
  defp dispatch_nested_field(resource, field_name, nested_fields, path, select, load, template) do
    field_name = AshTypescript.Resource.Info.get_original_field_name(resource, field_name)

    case FieldClassifier.classify_field(resource, field_name, path) do
      :relationship ->
        process_relationship(resource, field_name, nested_fields, path, select, load, template)

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

      :tuple ->
        TupleProcessor.process_tuple_type(
          resource,
          field_name,
          nested_fields,
          path,
          select,
          load,
          template,
          &process_fields_for_type/3
        )

      :field_constrained_type ->
        process_field_constrained_attribute(
          resource,
          field_name,
          nested_fields,
          path,
          select,
          load,
          template
        )

      :union_attribute ->
        UnionProcessor.process_union_attribute(
          resource,
          field_name,
          nested_fields,
          path,
          select,
          load,
          template,
          &process_fields_for_type/3
        )

      :calculation_with_args ->
        if CalculationProcessor.is_calculation_with_args(nested_fields) do
          CalculationProcessor.process_calculation_with_args(
            resource,
            field_name,
            nested_fields,
            path,
            select,
            load,
            template,
            &process_fields_for_type/3
          )
        else
          throw({:invalid_calculation_args, field_name, path})
        end

      :calculation ->
        # This calculation doesn't take arguments but was requested with nested structure
        throw({:invalid_calculation_args, field_name, path})

      :calculation_complex ->
        CalculationProcessor.process_calculation_complex(
          resource,
          field_name,
          nested_fields,
          path,
          select,
          load,
          template,
          &process_fields_for_type/3
        )

      :aggregate ->
        throw({:invalid_field_selection, field_name, :aggregate, path})

      :complex_aggregate ->
        CalculationProcessor.process_complex_aggregate(
          resource,
          field_name,
          nested_fields,
          path,
          select,
          load,
          template,
          &process_fields_for_type/3
        )

      :attribute ->
        throw({:field_does_not_support_nesting, field_name, path})

      {:error, :not_found} ->
        throw({:unknown_field, field_name, resource, path})

      field_type ->
        throw({:invalid_field_selection, field_name, field_type, path})
    end
  end

  defp process_nested_field_tuple(
         resource,
         field_name,
         nested_fields,
         path,
         select,
         load,
         template
       ) do
    dispatch_nested_field(resource, field_name, nested_fields, path, select, load, template)
  end

  defp process_field_map(resource, field_map, path, select, load, template) do
    Enum.reduce(field_map, {select, load, template}, fn {field_name, nested_fields}, {s, l, t} ->
      # Atomize field_name if it's a string (from map keys)
      field_atom =
        if is_binary(field_name), do: String.to_existing_atom(field_name), else: field_name

      dispatch_nested_field(resource, field_atom, nested_fields, path, s, l, t)
    end)
  end

  defp process_field_constrained_attribute(
         resource,
         field_name,
         nested_fields,
         path,
         select,
         load,
         template
       ) do
    Validator.validate_non_empty_fields(nested_fields, field_name, path, "field_constrained_type")

    attribute = Ash.Resource.Info.attribute(resource, field_name)
    constraints = attribute.constraints || []

    new_path = path ++ [field_name]

    {_nested_select, _nested_load, nested_template} =
      process_field_constrained_type(constraints, nested_fields, new_path)

    new_select = select ++ [field_name]

    {new_select, load, template ++ [{field_name, nested_template}]}
  end

  @doc """
  Processes types with field constraints (like TypedStruct, Keyword with fields).

  Similar to process_map_fields but also supports field name mapping via
  the instance_of module's typescript_field_names/0 callback.
  """
  def process_field_constrained_type(constraints, requested_fields, path) do
    if requested_fields == [] do
      throw({:requires_field_selection, :field_constrained_type, nil})
    end

    # Get field specs - check both direct :fields and :items/:fields for {:array, :map}
    field_specs =
      case Keyword.get(constraints, :fields) do
        nil ->
          # Try to get from :items/:fields for {:array, :map} types
          get_in(constraints, [:items, :fields]) || []

        fields ->
          fields
      end

    instance_of = Keyword.get(constraints, :instance_of)

    # Get field name mappings if available
    field_name_mappings =
      if instance_of && function_exported?(instance_of, :typescript_field_names, 0) do
        instance_of.typescript_field_names()
      else
        []
      end

    # Build reverse mapping for client -> server name conversion
    reverse_mappings =
      Enum.into(field_name_mappings, %{}, fn {elixir_name, ts_name} ->
        {ts_name, elixir_name}
      end)

    Validator.check_for_duplicate_fields(requested_fields, path)

    error_type = "field_constrained_type"

    Enum.reduce(requested_fields, {[], [], []}, fn field, {select, load, template} ->
      case field do
        field_name when is_atom(field_name) or is_binary(field_name) ->
          # Convert string to atom if needed
          field_atom =
            if is_binary(field_name) do
              String.to_existing_atom(field_name)
            else
              field_name
            end

          # Map TS name back to Elixir name if needed
          elixir_field_name = Map.get(reverse_mappings, field_atom, field_atom)

          if Keyword.has_key?(field_specs, elixir_field_name) do
            {select, load, template ++ [elixir_field_name]}
          else
            throw({:unknown_field, field_atom, error_type, path})
          end

        %{} = field_map ->
          Enum.reduce(field_map, {select, load, template}, fn {field_name, nested_fields},
                                                              {s, l, t} ->
            field_atom =
              if is_binary(field_name), do: String.to_existing_atom(field_name), else: field_name

            elixir_field_name = Map.get(reverse_mappings, field_atom, field_atom)

            if Keyword.has_key?(field_specs, elixir_field_name) do
              field_spec = Keyword.get(field_specs, elixir_field_name)
              field_type = Keyword.get(field_spec, :type)
              field_constraints = Keyword.get(field_spec, :constraints, [])
              field_return_type = {:ash_type, field_type, field_constraints}
              new_path = path ++ [elixir_field_name]

              {_nested_select, _nested_load, nested_template} =
                process_fields_for_type(field_return_type, nested_fields, new_path)

              # Keep original field_name format for template (string if from map)
              {s, l, t ++ [{field_name, nested_template}]}
            else
              throw({:unknown_field, field_atom, error_type, path})
            end
          end)
      end
    end)
  end

  @doc """
  Processes map fields with optional field constraints.
  """
  def process_map_fields(constraints, requested_fields, path) do
    Validator.check_for_duplicate_fields(requested_fields, path)
    field_specs = Keyword.get(constraints, :fields, [])

    Enum.reduce(requested_fields, {[], [], []}, fn field, {select, load, template} ->
      case field do
        field_name when is_atom(field_name) ->
          if Keyword.has_key?(field_specs, field_name) do
            {select, load, template ++ [field_name]}
          else
            throw({:unknown_field, field_name, "map", path})
          end

        %{} = field_map ->
          Enum.reduce(field_map, {select, load, template}, fn {field_name, nested_fields},
                                                              {s, l, t} ->
            field_atom =
              if is_binary(field_name), do: String.to_existing_atom(field_name), else: field_name

            if Keyword.has_key?(field_specs, field_atom) do
              field_spec = Keyword.get(field_specs, field_atom)
              field_type = Keyword.get(field_spec, :type)
              field_constraints = Keyword.get(field_spec, :constraints, [])
              field_return_type = {:ash_type, field_type, field_constraints}
              new_path = path ++ [field_atom]

              {_nested_select, _nested_load, nested_template} =
                process_fields_for_type(field_return_type, nested_fields, new_path)

              {s, l, t ++ [{field_name, nested_template}]}
            else
              throw({:unknown_field, field_atom, "map", path})
            end
          end)
      end
    end)
  end

  @doc """
  Processes generic fields (for :any return types).
  """
  def process_generic_fields(requested_fields, _path) do
    template =
      Enum.map(requested_fields, fn
        field_name when is_atom(field_name) ->
          field_name

        %{} = field_map ->
          Enum.map(field_map, fn {k, v} -> {k, v} end)
      end)

    {[], [], List.flatten(template)}
  end

  defp process_relationship(resource, rel_name, nested_fields, path, select, load, template) do
    relationship = Ash.Resource.Info.relationship(resource, rel_name)
    dest_resource = relationship && relationship.destination

    if dest_resource && AshTypescript.Resource.Info.typescript_resource?(dest_resource) do
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
      throw({:unknown_field, rel_name, resource, path})
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
    Validator.validate_non_empty_fields(nested_fields, field_name, path, "Relationship")

    attribute = Ash.Resource.Info.attribute(resource, field_name)
    embedded_resource = Utilities.extract_embedded_resource_type(attribute.type)

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

  defp process_nested_resource_fields(
         resource,
         field_name,
         nested_fields,
         path,
         select,
         load,
         template
       ) do
    Validator.validate_non_empty_fields(nested_fields, field_name, path)

    new_path = path ++ [field_name]

    {nested_select, nested_load, nested_template} =
      process_resource_fields(resource, nested_fields, new_path)

    load_spec = Utilities.build_load_spec(field_name, nested_select, nested_load)

    {select, load ++ [load_spec], template ++ [{field_name, nested_template}]}
  end
end
