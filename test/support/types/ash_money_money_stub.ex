# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshMoney.Types.Money do
  @moduledoc """
  Minimal stub impersonating `AshMoney.Types.Money` so the codegen's
  `third_party_types` map matches during test codegen without pulling
  ash_money as a dependency.

  Only the module name matters for the mapping; this stub implements just
  enough of `Ash.Type` for the test resource attribute to compile.
  """
  use Ash.Type

  @impl true
  def storage_type(_constraints), do: :map

  @impl true
  def cast_input(nil, _constraints), do: {:ok, nil}
  def cast_input(%{amount: _, currency: _} = value, _), do: {:ok, value}
  def cast_input(%{"amount" => _, "currency" => _} = value, _), do: {:ok, value}
  def cast_input(_value, _constraints), do: :error

  @impl true
  def cast_stored(nil, _constraints), do: {:ok, nil}
  def cast_stored(value, _constraints) when is_map(value), do: {:ok, value}
  def cast_stored(_value, _constraints), do: :error

  @impl true
  def dump_to_native(nil, _constraints), do: {:ok, nil}
  def dump_to_native(value, _constraints) when is_map(value), do: {:ok, value}
  def dump_to_native(_value, _constraints), do: :error
end
