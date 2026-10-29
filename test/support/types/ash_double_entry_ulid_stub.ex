# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshDoubleEntry.ULID do
  @moduledoc """
  Minimal stub impersonating `AshDoubleEntry.ULID` so the built-in `scalar`
  entry (`AshTypescript.CustomTypes.Builtin`, and its `ULID` alias) applies
  during test codegen without pulling ash_double_entry as a dependency.

  Only the module name matters for the entry; this stub implements just
  enough of `Ash.Type` for the test action argument to compile.
  """
  use Ash.Type

  @impl true
  def storage_type(_constraints), do: :string

  @impl true
  def cast_input(nil, _constraints), do: {:ok, nil}
  def cast_input(value, _constraints) when is_binary(value), do: {:ok, value}
  def cast_input(_value, _constraints), do: :error

  @impl true
  def cast_stored(nil, _constraints), do: {:ok, nil}
  def cast_stored(value, _constraints) when is_binary(value), do: {:ok, value}
  def cast_stored(_value, _constraints), do: :error

  @impl true
  def dump_to_native(nil, _constraints), do: {:ok, nil}
  def dump_to_native(value, _constraints) when is_binary(value), do: {:ok, value}
  def dump_to_native(_value, _constraints), do: :error
end
