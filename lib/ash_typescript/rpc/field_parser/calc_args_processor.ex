defmodule AshTypescript.Rpc.FieldParser.CalcArgsProcessor do
  @moduledoc """
  Utility module for processing calculation arguments.

  Consolidates the repeated pattern of extracting, parsing, and atomizing
  calculation arguments from field specifications.
  """

  alias AshTypescript.FieldFormatter

  @doc """
  Process calculation arguments from a calculation specification.

  Extracts args from the spec, applies field formatting, and atomizes keys.

  ## Parameters
  - calc_spec: Map containing calculation specification
  - formatter: Field formatter to use for key parsing

  ## Returns
  Map with atomized keys ready for Ash load statements
  """
  @spec process_calc_args(map(), atom()) :: map()
  def process_calc_args(calc_spec, formatter) when is_map(calc_spec) do
    args_field = get_args_field_name()

    calc_spec
    |> Map.get(args_field, %{})
    |> FieldFormatter.parse_input_fields(formatter)
    |> atomize_keys()
  end

  @doc """
  Get the expected field name for args based on output formatter.

  This ensures consistency with the TypeScript schema generation.
  """
  @spec get_args_field_name() :: String.t()
  def get_args_field_name do
    FieldFormatter.format_field(:args, AshTypescript.Rpc.output_field_formatter())
  end

  @doc """
  Atomize string keys in a map to atom keys.

  Safely converts string keys to existing atoms, preserving non-string keys.
  """
  @spec atomize_keys(map()) :: map()
  def atomize_keys(args) when is_map(args) do
    Enum.reduce(args, %{}, fn {k, v}, acc ->
      atom_key = if is_binary(k), do: String.to_existing_atom(k), else: k
      Map.put(acc, atom_key, v)
    end)
  end

  def atomize_keys(args), do: args
end
