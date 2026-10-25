# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.Theme do
  @moduledoc """
  A map-storage custom type declaring its fields with `typescript_fields/0`.
  Its members are scalar types with their own TypeScript mapping: a NewType
  with `typescript_type_name/0` (`HexColor`), a `use Ash.Type` with
  `typescript_type_name/0` (`PriorityScore`) and an external type declared in
  the test manifest (`ExternalCode`).
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

  @doc "The declared fields (ash_typescript's `typescript_fields/0` callback)."
  def typescript_fields do
    [
      color: [type: AshTypescript.Test.HexColor, allow_nil?: false],
      accent: [type: AshTypescript.Test.HexColor],
      score: [type: AshTypescript.Test.Todo.PriorityScore],
      code: [type: AshTypescript.Test.ExternalCode, allow_nil?: false],
      codes: [type: {:array, AshTypescript.Test.ExternalCode}]
    ]
  end
end

defmodule AshTypescript.Test.ThemeMap do
  @moduledoc """
  An ordinary NewType over `:map` with `fields`, with the same scalar members
  as `AshTypescript.Test.Theme`.
  """
  use Ash.Type.NewType,
    subtype_of: :map,
    constraints: [
      fields: [
        color: [type: AshTypescript.Test.HexColor, allow_nil?: false],
        accent: [type: AshTypescript.Test.HexColor],
        score: [type: AshTypescript.Test.Todo.PriorityScore],
        code: [type: AshTypescript.Test.ExternalCode, allow_nil?: false],
        codes: [type: {:array, AshTypescript.Test.ExternalCode}]
      ]
    ]
end
