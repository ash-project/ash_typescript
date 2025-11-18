# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.TypeSystem.Introspection do
  @moduledoc """
  Core type introspection and classification for Ash types.

  This module provides a centralized set of functions for determining the nature
  and characteristics of Ash types, including embedded resources, typed structs,
  unions, and primitive types.

  Used throughout the codebase for type checking, code generation, and runtime
  processing.
  """

  @doc """
  Checks if a module is an embedded Ash resource.

  ## Examples

      iex> AshTypescript.TypeSystem.Introspection.is_embedded_resource?(MyApp.Accounts.Address)
      true

      iex> AshTypescript.TypeSystem.Introspection.is_embedded_resource?(MyApp.Accounts.User)
      false
  """
  def is_embedded_resource?(module) when is_atom(module) do
    Ash.Resource.Info.resource?(module) and Ash.Resource.Info.embedded?(module)
  end

  def is_embedded_resource?(_), do: false

  @doc """
  Checks if a type is a primitive Ash type (not a complex or composite type).

  Primitive types include basic types like String, Integer, Boolean, Date, UUID, etc.

  ## Examples

      iex> AshTypescript.TypeSystem.Introspection.is_primitive_type?(Ash.Type.String)
      true

      iex> AshTypescript.TypeSystem.Introspection.is_primitive_type?(Ash.Type.Union)
      false
  """
  def is_primitive_type?(type) do
    type in [
      Ash.Type.Integer,
      Ash.Type.String,
      Ash.Type.Boolean,
      Ash.Type.Float,
      Ash.Type.Decimal,
      Ash.Type.Date,
      Ash.Type.DateTime,
      Ash.Type.NaiveDatetime,
      Ash.Type.UtcDatetime,
      Ash.Type.Atom,
      Ash.Type.UUID,
      Ash.Type.Binary
    ]
  end

  @doc """
  Classifies an Ash type into a category for processing purposes.

  Returns one of:
  - `:union_attribute` - Union type
  - `:embedded_resource` - Single embedded resource
  - `:embedded_resource_array` - Array of embedded resources
  - `:tuple` - Tuple type
  - `:attribute` - Simple attribute (default)

  ## Parameters
  - `type_module` - The Ash type module (e.g., Ash.Type.String, Ash.Type.Union)
  - `attribute` - The attribute struct containing type and constraints
  - `is_array` - Whether this is inside an array type

  ## Examples

      iex> attr = %{type: MyApp.Address, constraints: []}
      iex> AshTypescript.TypeSystem.Introspection.classify_ash_type(MyApp.Address, attr, false)
      :embedded_resource
  """
  def classify_ash_type(type_module, _attribute, is_array) do
    cond do
      type_module == Ash.Type.Union ->
        :union_attribute

      is_embedded_resource?(type_module) ->
        if is_array, do: :embedded_resource_array, else: :embedded_resource

      type_module == Ash.Type.Tuple ->
        :tuple

      true ->
        :attribute
    end
  end

  @doc """
  Extracts union types from an attribute's constraints.

  Handles both direct union types and array union types.

  ## Examples

      iex> attr = %{type: Ash.Type.Union, constraints: [types: [note: [...], url: [...]]]}
      iex> AshTypescript.TypeSystem.Introspection.get_union_types(attr)
      [note: [...], url: [...]]
  """
  def get_union_types(attribute) do
    get_union_types_from_constraints(attribute.type, attribute.constraints)
  end

  @doc """
  Extracts union types from type and constraints directly.

  Useful when you have constraints but not the full attribute struct.
  Handles both direct union types and array union types.

  ## Examples

      iex> constraints = [types: [note: [...], url: [...]]]
      iex> AshTypescript.TypeSystem.Introspection.get_union_types_from_constraints(Ash.Type.Union, constraints)
      [note: [...], url: [...]]
  """
  def get_union_types_from_constraints(type, constraints) do
    case type do
      Ash.Type.Union ->
        Keyword.get(constraints, :types, [])

      {:array, Ash.Type.Union} ->
        items_constraints = Keyword.get(constraints, :items, [])
        Keyword.get(items_constraints, :types, [])

      _ ->
        []
    end
  end

  @doc """
  Extracts the inner type from an array type.

  ## Examples

      iex> AshTypescript.TypeSystem.Introspection.get_inner_type({:array, Ash.Type.String})
      Ash.Type.String

      iex> AshTypescript.TypeSystem.Introspection.get_inner_type(Ash.Type.String)
      Ash.Type.String
  """
  def get_inner_type({:array, inner_type}), do: inner_type
  def get_inner_type(type), do: type

  @doc """
  Checks if a type is an Ash type module.

  ## Examples

      iex> AshTypescript.TypeSystem.Introspection.is_ash_type?(Ash.Type.String)
      true

      iex> AshTypescript.TypeSystem.Introspection.is_ash_type?(MyApp.CustomType)
      true

      iex> AshTypescript.TypeSystem.Introspection.is_ash_type?(:string)
      false
  """
  def is_ash_type?(module) when is_atom(module) do
    Ash.Type.ash_type?(module)
  rescue
    _ -> false
  end

  def is_ash_type?(_), do: false
end
