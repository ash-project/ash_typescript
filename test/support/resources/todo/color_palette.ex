# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.Todo.ColorPalette do
  @moduledoc """
  A custom type that represents a color palette stored as a map.
  It declares its fields with `typescript_fields/0`, so decoration makes it a
  typed map and its TypeScript is generated from the fields, and names its
  alias with `typescript_alias_name/0`.
  """
  use Ash.Type

  @impl true
  def storage_type(_), do: :map

  @impl true
  def cast_input(nil, _), do: {:ok, nil}

  # Input arrives with atom keys: ash_rpc maps the declared fields' client
  # names to them before Ash casts.
  def cast_input(%{primary: primary, secondary: secondary, accent: accent} = value, _)
      when is_binary(primary) and is_binary(secondary) and is_binary(accent) do
    {:ok, value}
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

  @doc "The declared fields (ash_typescript's `typescript_fields/0` callback)."
  def typescript_fields do
    [
      primary: [type: :string, allow_nil?: false],
      secondary: [type: :string, allow_nil?: false],
      accent: [type: :string, allow_nil?: false]
    ]
  end

  @doc "The TypeScript alias name (ash_typescript's `typescript_alias_name/0` callback)."
  def typescript_alias_name, do: "ColorPalette"
end
