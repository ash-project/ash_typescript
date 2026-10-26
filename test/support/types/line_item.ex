# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.LineItem do
  @moduledoc """
  A map-storage custom type declared by a test-manifest `map` entry, with a
  nested declared type (Money) and an embedded resource: its alias needs a
  `LineItemInput` and its schema follows `MoneyZodSchema` and references
  `TaskMetadataZodSchema` lazily.
  """
  use Ash.Type

  @impl true
  def storage_type(_), do: :map

  @impl true
  def cast_input(nil, _), do: {:ok, nil}
  def cast_input(value, _) when is_map(value), do: {:ok, value}
  def cast_input(_, _), do: {:error, "must be a map"}

  @impl true
  def cast_stored(nil, _), do: {:ok, nil}
  def cast_stored(value, _) when is_map(value), do: {:ok, value}
  def cast_stored(_, _), do: {:error, "stored value must be a map"}

  @impl true
  def dump_to_native(nil, _), do: {:ok, nil}
  def dump_to_native(value, _) when is_map(value), do: {:ok, value}
  def dump_to_native(_, _), do: {:error, "dump value must be a map"}
end
