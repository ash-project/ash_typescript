# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.TypeSystem.Introspection do
  @moduledoc """
  Core type introspection and classification for Ash types.

  Detects custom types (`typescript_type/0`), resolves named type
  definitions from the decorated manifest, and reads `typescript_field_names/0`
  mappings.
  """

  @doc """
  Checks if a type is a custom Ash type with a typescript_type callback.

  Custom types are Ash types that define a `typescript_type/0` callback
  to specify their TypeScript representation.

  ## Examples

      iex> AshTypescript.TypeSystem.Introspection.is_custom_type?(MyApp.MyCustomType)
      true

      iex> AshTypescript.TypeSystem.Introspection.is_custom_type?(Ash.Type.String)
      false
  """
  def is_custom_type?(type) when is_atom(type) and not is_nil(type) do
    Code.ensure_loaded?(type) and
      function_exported?(type, :typescript_type, 0) and
      Spark.implements_behaviour?(type, Ash.Type)
  end

  def is_custom_type?(_), do: false

  @doc """
  Returns the decorated definition of a named type (a `:type_ref` module) from
  the manifest (`AshTypescript.with_manifest/2` applies).

  Raises `ArgumentError` for a type missing from the manifest: every named type
  codegen renders, route-only types included, is in the manifest, so a miss is a
  decoration gap.
  """
  @spec named_type_definition(module()) :: Ash.Info.Manifest.Type.t()
  defdelegate named_type_definition(module),
    to: AshTypescript.Codegen.ClientNames,
    as: :named_type!

  @doc """
  Gets the typescript_field_names as a map, or empty map if not available.

  ## Examples

      iex> AshTypescript.TypeSystem.Introspection.get_typescript_field_names_map(MyApp.TaskStats)
      %{is_active?: "isActive", meta_1: "meta1"}
  """
  def get_typescript_field_names_map(nil), do: %{}

  def get_typescript_field_names_map(module) when is_atom(module) do
    if AshTypescript.Helpers.has_typescript_field_names?(module) do
      module.typescript_field_names() |> Map.new()
    else
      %{}
    end
  end

  def get_typescript_field_names_map(_), do: %{}
end
