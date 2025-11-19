# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.FieldProcessing.TypeProcessors.CalculationProcessor do
  @moduledoc """
  Processes calculation and aggregate fields with optional arguments and field selection.

  Calculations can have:
  - Arguments (required or optional)
  - Complex return types requiring nested field selection
  - Simple return types that don't support field selection
  """

  alias AshTypescript.Rpc.FieldProcessing.{FieldClassifier, Utilities, Validator}

  @doc """
  Checks if nested fields represent a calculation with arguments.

  Calculations with arguments use a special format: %{args: %{...}, fields: [...]}
  """
  def is_calculation_with_args(nested_fields) do
    is_map(nested_fields) and Map.has_key?(nested_fields, :args)
  end

  @doc """
  Processes a calculation that accepts arguments.

  ## Parameters

  - `resource` - The resource containing the calculation
  - `calc_name` - The calculation name
  - `nested_fields` - Map with :args and optionally :fields keys
  - `path` - Current path in field hierarchy
  - `select`, `load`, `template` - Current processing state

  ## Returns

  `{select, new_load, new_template}` tuple
  """
  def process_calculation_with_args(
        resource,
        calc_name,
        nested_fields,
        path,
        select,
        load,
        template,
        process_fields_fn
      ) do
    args = Map.get(nested_fields, :args)
    fields = Map.get(nested_fields, :fields, [])
    calculation = Ash.Resource.Info.calculation(resource, calc_name)

    if is_nil(calculation) do
      throw({:unknown_field, calc_name, resource, path})
    end

    calc_return_type = FieldClassifier.determine_calculation_return_type(calculation)

    fields_provided = Map.has_key?(nested_fields, :fields)

    case calc_return_type do
      {:ash_type, {:array, inner_type}, _constraints} ->
        if FieldClassifier.is_primitive_type?(inner_type) do
          if fields_provided do
            throw({:invalid_field_selection, calc_name, :calculation, path})
          end
        end

      {:ash_type, Ash.Type.Struct, _constraints} ->
        Validator.validate_complex_type_fields(
          fields_provided,
          fields,
          calc_name,
          path,
          "Calculation"
        )

      {:ash_type, type, _constraints} ->
        if FieldClassifier.is_primitive_type?(type) do
          if fields_provided do
            throw({:invalid_field_selection, calc_name, :calculation, path})
          end
        end

      {:resource, _resource} ->
        Validator.validate_complex_type_fields(
          fields_provided,
          fields,
          calc_name,
          path,
          "Calculation"
        )
    end

    new_path = path ++ [calc_name]

    {nested_select, nested_load, nested_template} =
      process_fields_fn.(calc_return_type, fields, new_path)

    load_fields =
      case nested_load do
        [] -> nested_select
        _ -> nested_select ++ nested_load
      end

    load_spec =
      if load_fields == [] do
        {calc_name, args}
      else
        {calc_name, {args, load_fields}}
      end

    template_item =
      if nested_template == [] do
        calc_name
      else
        {calc_name, nested_template}
      end

    {select, load ++ [load_spec], template ++ [template_item]}
  end

  @doc """
  Processes a complex calculation (returns structured data requiring field selection).

  ## Parameters

  - `resource` - The resource containing the calculation
  - `calc_name` - The calculation name
  - `nested_fields` - The fields to select from the calculation result
  - `path` - Current path in field hierarchy
  - `select`, `load`, `template` - Current processing state
  - `process_fields_fn` - Function to recursively process nested fields

  ## Returns

  `{select, new_load, new_template}` tuple
  """
  def process_calculation_complex(
        resource,
        calc_name,
        nested_fields,
        path,
        select,
        load,
        template,
        process_fields_fn
      ) do
    # Extract args and fields from the nested structure (if present)
    # For calculations without arguments, this will be %{args: %{}, fields: [...]}
    # For backward compatibility, also support plain arrays
    fields =
      case nested_fields do
        %{} = map when is_map(map) ->
          Map.get(map, :fields, [])

        list when is_list(list) ->
          list

        _ ->
          []
      end

    if fields == [] do
      throw({:requires_field_selection, :calculation_complex, calc_name, path})
    end

    calculation = Ash.Resource.Info.calculation(resource, calc_name)

    if is_nil(calculation) do
      throw({:unknown_field, calc_name, resource, path})
    end

    calc_return_type = FieldClassifier.determine_calculation_return_type(calculation)

    new_path = path ++ [calc_name]

    {nested_select, nested_load, nested_template} =
      process_fields_fn.(calc_return_type, fields, new_path)

    load_spec = Utilities.build_load_spec(calc_name, nested_select, nested_load)

    {select, load ++ [load_spec], template ++ [{calc_name, nested_template}]}
  end

  @doc """
  Processes a complex aggregate (returns structured data requiring field selection).

  Similar to complex calculations but for aggregate fields.
  """
  def process_complex_aggregate(
        resource,
        agg_name,
        nested_fields,
        path,
        select,
        load,
        template,
        process_fields_fn
      ) do
    # Validate that nested fields are not empty (custom message for aggregates)
    if nested_fields == [] do
      throw({:requires_field_selection, :complex_aggregate, agg_name, path})
    end

    aggregate = Ash.Resource.Info.aggregate(resource, agg_name)
    agg_return_type = FieldClassifier.determine_aggregate_return_type(resource, aggregate)

    new_path = path ++ [agg_name]

    {nested_select, nested_load, nested_template} =
      process_fields_fn.(agg_return_type, nested_fields, new_path)

    load_spec = Utilities.build_load_spec(agg_name, nested_select, nested_load)

    {select, load ++ [load_spec], template ++ [{agg_name, nested_template}]}
  end
end
