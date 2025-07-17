defmodule AshTypescript.Test.Todo.ColorPalette do
  @moduledoc """
  A custom type that represents a color palette stored as a map.
  Demonstrates how custom types can provide precise TypeScript definitions
  for complex data structures.
  """
  use Ash.Type

  @impl true
  def storage_type(_), do: :map

  @impl true
  def cast_input(nil, _), do: {:ok, nil}
  def cast_input(%{primary: primary, secondary: secondary, accent: accent} = value, _) 
    when is_binary(primary) and is_binary(secondary) and is_binary(accent) do
    {:ok, value}
  end
  def cast_input(value, _) when is_map(value) do
    with {:ok, primary} <- Map.fetch(value, :primary),
         {:ok, secondary} <- Map.fetch(value, :secondary),
         {:ok, accent} <- Map.fetch(value, :accent) do
      {:ok, %{primary: primary, secondary: secondary, accent: accent}}
    else
      _ -> {:error, "must be a map with primary, secondary, and accent colors"}
    end
  end
  def cast_input(_, _), do: {:error, "must be a map with primary, secondary, and accent colors"}

  @impl true
  def cast_stored(nil, _), do: {:ok, nil}
  def cast_stored(value, _) when is_map(value), do: {:ok, value}
  def cast_stored(_, _), do: {:error, "stored value must be a map"}

  @impl true
  def dump_to_native(nil, _), do: {:ok, nil}
  def dump_to_native(value, _) when is_map(value), do: {:ok, value}
  def dump_to_native(_, _), do: {:error, "dump value must be a map"}

  @impl true
  def apply_constraints(value, _constraints), do: {:ok, value}

  # Custom callbacks for AshTypescript - provides TypeScript type information
  @doc """
  Returns the TypeScript type name for this custom type.
  """
  def typescript_type_name, do: "ColorPalette"

  @doc """
  Returns the TypeScript type definition for this custom type.
  This shows the power of custom types with complex storage types.
  """
  def typescript_type_def do
    """
    {
      primary: string;
      secondary: string;
      accent: string;
    }
    """
  end
end