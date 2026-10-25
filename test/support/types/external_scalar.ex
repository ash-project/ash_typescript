# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.ExternalCode do
  @moduledoc """
  A string custom type with no TypeScript callbacks, standing in for a type
  from a dependency. The test manifest declares it with a `scalar` entry whose
  `typescript` is an MFA (`AshTypescript.Test.ExternalCodeTs.typescript/1`).
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

defmodule AshTypescript.Test.ExternalCodeTs do
  @moduledoc """
  The `typescript` MFA of the test manifest's `AshTypescript.Test.ExternalCode`
  scalar entry. It receives the use's constraints.
  """

  @doc "The TypeScript type of an `ExternalCode` use."
  @spec typescript(Keyword.t()) :: String.t()
  def typescript(constraints) when is_list(constraints), do: "`code-${string}`"
end
