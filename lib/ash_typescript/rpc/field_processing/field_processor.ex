# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.FieldProcessing.FieldProcessor do
  @moduledoc """
  Core field processing orchestration module.

  This module coordinates field processing across different types (resources, maps, tuples, etc.)
  and delegates to specialized type processors for complex types like unions and calculations.
  """

  alias AshTypescript.TypeSystem.Introspection

  alias AshTypescript.Rpc.FieldProcessing.{
    FieldClassifier,
    Utilities,
    Validator
  }

  alias AshTypescript.Rpc.FieldProcessing.TypeProcessors.{
    CalculationProcessor,
    TupleProcessor,
    TypedStructProcessor,
    UnionProcessor
  }

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

        if Introspection.is_typed_struct_from_attribute?(fake_attribute) do
          if requested_fields == [] do
            throw({:requires_field_selection, :typed_struct, nil})
          end

          field_specs = Keyword.get(constraints, :fields, [])
          instance_of = Keyword.get(constraints, :instance_of)

          field_name_mappings =
            if instance_of && function_exported?(instance_of, :typescript_field_names, 0) do
              instance_of.typescript_field_names()
            else
              []
            end

          {_field_names, template_items} =
            TypedStructProcessor.process_typed_struct_fields(
              requested_fields,
              field_specs,
              path,
              field_name_mappings,
              &process_fields_for_type/3
            )

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

  # Process a simple field (atom without nested structure)
  defp process_simple_field(resource, field_name, path, select, load, template) do
    field_name = AshTypescript.Resource.Info.get_original_field_name(resource, field_name)

    case FieldClassifier.classify_field(resource, field_name, path) do
      :attribute ->
        {select ++ [field_name], load, template ++ [field_name]}

      :calculation ->
        {select, load ++ [field_name], template ++ [field_name]}

      :tuple ->
        field_path = Utilities.build_field_path(path, field_name)
        throw({:requires_field_selection, :tuple, field_path})

      :calculation_with_args ->
        field_path = Utilities.build_field_path(path, field_name)
        throw({:calculation_requires_args, field_name, field_path})

      :calculation_complex ->
        field_path = Utilities.build_field_path(path, field_name)
        throw({:requires_field_selection, :calculation_complex, field_path})

      :aggregate ->
        {select, load ++ [field_name], template ++ [field_name]}

      :complex_aggregate ->
        field_path = Utilities.build_field_path(path, field_name)
        throw({:requires_field_selection, :complex_aggregate, field_path})

      :relationship ->
        field_path = Utilities.build_field_path(path, field_name)
        throw({:requires_field_selection, :relationship, field_path})

      :embedded_resource ->
        field_path = Utilities.build_field_path(path, field_name)
        throw({:requires_field_selection, :embedded_resource, field_path})

      :embedded_resource_array ->
        field_path = Utilities.build_field_path(path, field_name)
        throw({:requires_field_selection, :embedded_resource_array, field_path})

      :typed_struct ->
        field_path = Utilities.build_field_path(path, field_name)
        throw({:requires_field_selection, :typed_struct, field_path})

      :union_attribute ->
        field_path = Utilities.build_field_path(path, field_name)
        throw({:requires_field_selection, :union_attribute, field_path})

      {:error, :not_found} ->
        field_path = Utilities.build_field_path(path, field_name)
        throw({:unknown_field, field_name, resource, field_path})
    end
  end

  # Process a nested field specified as tuple {field_name, nested_fields}
  defp process_nested_field_tuple(
         resource,
         field_name,
         nested_fields,
         path,
         select,
         load,
         template
       ) do
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

      :complex_aggregate ->
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

      :typed_struct ->
        TypedStructProcessor.process_typed_struct(
          resource,
          field_name,
          nested_fields,
          path,
          select,
          load,
          template,
          &process_fields_for_type/3
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

      {:error, :not_found} ->
        field_path = Utilities.build_field_path(path, field_name)
        throw({:unknown_field, field_name, resource, field_path})

      _ ->
        field_path = Utilities.build_field_path(path, field_name)
        throw({:invalid_field_selection, field_name, :simple_field, field_path})
    end
  end

  # Process a field map %{field_name => nested_fields, ...}
  defp process_field_map(resource, field_map, path, select, load, template) do
    {new_select, new_load, new_template} =
      Enum.reduce(field_map, {select, load, template}, fn {field_name, nested_fields},
                                                          {s, l, t} ->
        field_name = AshTypescript.Resource.Info.get_original_field_name(resource, field_name)

        case FieldClassifier.classify_field(resource, field_name, path) do
          :relationship ->
            process_relationship(resource, field_name, nested_fields, path, s, l, t)

          :embedded_resource ->
            process_embedded_resource(resource, field_name, nested_fields, path, s, l, t)

          :embedded_resource_array ->
            process_embedded_resource(resource, field_name, nested_fields, path, s, l, t)

          :tuple ->
            TupleProcessor.process_tuple_type(
              resource,
              field_name,
              nested_fields,
              path,
              s,
              l,
              t,
              &process_fields_for_type/3
            )

          :typed_struct ->
            TypedStructProcessor.process_typed_struct(
              resource,
              field_name,
              nested_fields,
              path,
              s,
              l,
              t,
              &process_fields_for_type/3
            )

          :union_attribute ->
            process_union_with_member_map(resource, field_name, nested_fields, path, s, l, t)

          :calculation_with_args ->
            if CalculationProcessor.is_calculation_with_args(nested_fields) do
              CalculationProcessor.process_calculation_with_args(
                resource,
                field_name,
                nested_fields,
                path,
                s,
                l,
                t,
                &process_fields_for_type/3
              )
            else
              field_path = Utilities.build_field_path(path, field_name)
              throw({:invalid_calculation_args, field_name, field_path})
            end

          :calculation ->
            # This calculation doesn't take arguments but was requested with nested structure
            field_path = Utilities.build_field_path(path, field_name)
            throw({:invalid_calculation_args, field_name, field_path})

          :calculation_complex ->
            CalculationProcessor.process_calculation_complex(
              resource,
              field_name,
              nested_fields,
              path,
              s,
              l,
              t,
              &process_fields_for_type/3
            )

          :aggregate ->
            # This aggregate returns primitive type and doesn't support nested field selection
            field_path = Utilities.build_field_path(path, field_name)
            throw({:invalid_field_selection, field_name, :aggregate, field_path})

          :complex_aggregate ->
            CalculationProcessor.process_complex_aggregate(
              resource,
              field_name,
              nested_fields,
              path,
              s,
              l,
              t,
              &process_fields_for_type/3
            )

          :attribute ->
            # Attributes don't support nested field selection
            field_path = Utilities.build_field_path(path, field_name)
            throw({:field_does_not_support_nesting, field_path})

          {:error, :not_found} ->
            field_path = Utilities.build_field_path(path, field_name)
            throw({:unknown_field, field_name, resource, field_path})
        end
      end)

    {new_select, new_load, new_template}
  end

  # Process union attribute with member map
  defp process_union_with_member_map(
         resource,
         field_name,
         nested_fields,
         path,
         select,
         load,
         template
       ) do
    # For union attributes accessed via field map, delegate to UnionProcessor.process_union_attribute
    # which handles normalization and validation
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
            field_path = Utilities.build_field_path(path, field_name)
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
              field_path = Utilities.build_field_path(path, field_name)
              throw({:unknown_field, field_name, "map", field_path})
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

  # Process a relationship field
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
      field_path = Utilities.build_field_path(path, rel_name)
      throw({:unknown_field, rel_name, resource, field_path})
    end
  end

  # Process an embedded resource field
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

  # Process nested resource fields (for relationships)
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
