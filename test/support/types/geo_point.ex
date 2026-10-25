# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.GeoPoint do
  @moduledoc """
  A hand-rolled custom type stored as a map, used to exercise a `map` entry's
  `zod` / `valibot` schemas.

  The test manifest declares it with a `map` entry (`lat` and `lng`, both
  non-null floats), whose `zod` / `valibot` replace the generated object of
  the fields with schemas authored in TypeScript that also check the ranges.
  """
  use Ash.Type

  @impl true
  def storage_type(_), do: :map

  @impl true
  def cast_input(nil, _), do: {:ok, nil}

  # Input arrives with atom keys: ash_rpc maps the declared fields' client
  # names to them before Ash casts.
  def cast_input(%{lat: lat, lng: lng} = value, _) when is_number(lat) and is_number(lng) do
    {:ok, value}
  end

  def cast_input(_, _), do: {:error, "must be a map with numeric lat and lng"}

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
end
