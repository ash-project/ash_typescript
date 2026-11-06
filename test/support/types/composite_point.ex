# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.CompositePoint do
  @moduledoc """
  A composite custom type (`composite?/1` + `composite_types/1`, no other
  field declaration) stored as a map: its `composite_types/1` entries are its
  fields. Used by `AshTypescript.Test.Task`'s `position`.
  """
  use Ash.Type

  @impl true
  def storage_type(_), do: :map

  @impl true
  def composite?(_), do: true

  @impl true
  def composite_types(_), do: [{:x, :x, :integer, []}, {:y, :y, :integer, []}]

  @impl true
  def cast_input(nil, _), do: {:ok, nil}

  # Input arrives with atom keys: ash_rpc maps the fields' client names first.
  def cast_input(%{x: x, y: y} = value, _) when is_integer(x) and is_integer(y),
    do: {:ok, value}

  def cast_input(_, _), do: {:error, "must be a map with integer x and y"}

  @impl true
  def cast_stored(nil, _), do: {:ok, nil}
  def cast_stored(value, _) when is_map(value), do: {:ok, value}
  def cast_stored(_, _), do: {:error, "stored value must be a map"}

  @impl true
  def dump_to_native(nil, _), do: {:ok, nil}
  def dump_to_native(value, _) when is_map(value), do: {:ok, value}
  def dump_to_native(_, _), do: {:error, "dump value must be a map"}
end
