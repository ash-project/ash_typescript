# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.GeoPoint do
  @moduledoc """
  A hand-rolled custom type stored as a map, used to exercise validation-schema
  mapping overrides that resolve to a *non-string* schema.

  Its real shape lives in `cast_input/2`, so the storage-derived fallback can
  only manage `z.record(z.string(), z.any())` / `v.record(v.string(), v.any())`.
  `config/config.exs` tightens that to a precise object schema authored in
  TypeScript, referenced through `zod_mapping_overrides` /
  `valibot_mapping_overrides`.
  """
  use Ash.Type

  @impl true
  def storage_type(_), do: :map

  @impl true
  def cast_input(nil, _), do: {:ok, nil}

  def cast_input(%{lat: lat, lng: lng} = value, _) when is_number(lat) and is_number(lng) do
    {:ok, value}
  end

  def cast_input(%{"lat" => lat, "lng" => lng}, _) when is_number(lat) and is_number(lng) do
    {:ok, %{lat: lat, lng: lng}}
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

  def typescript_type_name, do: "CustomTypes.GeoPoint"
end
