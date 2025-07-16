defmodule AshTypescript.Rpc.FieldParser.LoadBuilder do
  @moduledoc """
  Utility module for building Ash-compatible load statements.
  """

  alias AshTypescript.Rpc.FieldParser.{Context, CalcArgsProcessor}
  alias AshTypescript.FieldFormatter

  @doc """
  Build an Ash-compatible load entry for a complex calculation.

  Handles the full complexity of calculation specifications including:
  - calcArgs: Arguments to pass to the calculation
  - fields: Fields to select from the calculation result

  ## Parameters
  - calc_atom: The calculation name as an atom
  - calc_spec: Map containing the calculation specification
  - context: Parsing context with resource and formatter

  ## Returns
  - load_entry: Ash-compatible load statement
  - field_specs: Specification for result processing (if needed)
  """
  @spec build_calculation_load_entry(atom(), map(), Context.t()) ::
          {atom() | tuple(), map() | nil}
  def build_calculation_load_entry(calc_atom, calc_spec, %Context{} = context)
      when is_map(calc_spec) do
    # Extract and process calc_args
    calc_args = CalcArgsProcessor.process_calc_args(calc_spec, context.formatter)

    # Extract and parse fields
    fields = Map.get(calc_spec, "fields", [])
    parsed_fields = parse_field_names_for_load(fields, context.formatter)

    # Build load entry
    load_entry = combine_load_components(calc_atom, calc_args, parsed_fields)

    # Build field specs for result processing
    field_specs = build_calculation_field_specs(calc_args, fields)

    {load_entry, field_specs}
  end

  @doc """
  Build field specifications for result processing.

  Only creates field specs if we have arguments AND fields.
  """
  @spec build_calculation_field_specs(map(), list()) :: {list(), map()} | nil
  def build_calculation_field_specs(calc_args, fields) do
    if map_size(calc_args) > 0 and length(fields) > 0 do
      # Extract nested calculation specs from the fields list
      {simple_fields, extracted_nested_specs} = extract_nested_calc_specs_from_fields(fields)

      {simple_fields, extracted_nested_specs}
    else
      nil
    end
  end

  @doc """
  Combine calculation components into an Ash-compatible load statement.

  Handles all combinations of calc_args and load specifications.
  """
  @spec combine_load_components(atom(), map(), list()) :: atom() | tuple()
  def combine_load_components(calc_atom, calc_args, combined_load) do
    case {map_size(calc_args), length(combined_load)} do
      {0, 0} -> calc_atom
      {0, _} -> {calc_atom, combined_load}
      {_, 0} -> {calc_atom, calc_args}
      {_, _} -> {calc_atom, {calc_args, combined_load}}
    end
  end

  @doc """
  Parse field names for Ash load format.

  Converts field specifications into Ash-compatible load statements,
  handling both simple field names and complex nested calculations.
  """
  @spec parse_field_names_for_load(list(), atom()) :: list()
  def parse_field_names_for_load(fields, formatter) when is_list(fields) do
    fields
    |> Enum.map(&parse_single_field_for_load(&1, formatter))
    |> Enum.filter(fn x -> x != nil end)
  end

  defp parse_single_field_for_load(field, formatter) when is_binary(field) do
    FieldFormatter.parse_input_field(field, formatter)
  end

  defp parse_single_field_for_load(field_map, formatter) when is_map(field_map) do
    case Map.to_list(field_map) do
      [{field_name, field_spec}] ->
        field_atom = FieldFormatter.parse_input_field(field_name, formatter)

        case field_spec do
          %{"calcArgs" => calc_args, "fields" => nested_fields} ->
            # This is a nested calculation
            parsed_args =
              FieldFormatter.parse_input_fields(calc_args, formatter)
              |> CalcArgsProcessor.atomize_keys()

            parsed_nested_fields = parse_field_names_for_load(nested_fields, formatter)

            # Build the load entry
            combine_load_components(field_atom, parsed_args, parsed_nested_fields)

          _ ->
            # Other nested structure - just use the field name
            field_atom
        end

      _ ->
        # Invalid map structure - skip it
        nil
    end
  end

  defp parse_single_field_for_load(field, _formatter) do
    field
  end

  @doc """
  Extract nested calculation specs from fields list.

  Separates simple fields from nested calculation maps and returns
  both the simple fields and the extracted nested calculation specs.
  """
  @spec extract_nested_calc_specs_from_fields(list()) :: {list(), map()}
  def extract_nested_calc_specs_from_fields(fields) do
    Enum.reduce(fields, {[], %{}}, fn field, {simple_fields_acc, nested_specs_acc} ->
      case field do
        %{} = field_map when map_size(field_map) == 1 ->
          # This is a nested calculation
          [{calc_name, calc_spec}] = Map.to_list(field_map)

          case calc_spec do
            %{"calcArgs" => _calc_args, "fields" => calc_fields} ->
              # Extract nested specs from calc_fields recursively
              {simple_calc_fields, deeper_nested_specs} =
                extract_nested_calc_specs_from_fields(calc_fields)

              # Store the spec for this calculation
              calc_atom = String.to_atom(calc_name)
              nested_spec = {simple_calc_fields, deeper_nested_specs}

              {simple_fields_acc, Map.put(nested_specs_acc, calc_atom, nested_spec)}

            _ ->
              # Not a valid nested calculation, treat as simple field
              {[field | simple_fields_acc], nested_specs_acc}
          end

        _ ->
          # Simple field
          {[field | simple_fields_acc], nested_specs_acc}
      end
    end)
  end
end
