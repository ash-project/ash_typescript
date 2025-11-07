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
  Checks if a module is a TypedStruct using Spark DSL detection.

  ## Examples

      iex> AshTypescript.TypeSystem.Introspection.is_typed_struct?(MyApp.CustomType)
      true

      iex> AshTypescript.TypeSystem.Introspection.is_typed_struct?(Ash.Type.String)
      false
  """
  def is_typed_struct?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and
      function_exported?(module, :spark_is, 0) and
      is_ash_typed_struct?(module)
  end

  def is_typed_struct?(_), do: false

  defp is_ash_typed_struct?(module) do
    module.spark_is() == Ash.TypedStruct
  rescue
    _ -> false
  end

  @doc """
  Gets the field information from a TypedStruct module using Ash's DSL pattern.
  Returns a list of field definitions.

  ## Examples

      iex> AshTypescript.TypeSystem.Introspection.get_typed_struct_fields(MyApp.CustomType)
      [%{name: :field1, type: :string}, ...]
  """
  def get_typed_struct_fields(module) do
    if is_typed_struct?(module) do
      Spark.Dsl.Extension.get_entities(module, [:typed_struct])
    else
      []
    end
  rescue
    _ -> []
  end

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
  - `:typed_struct` - TypedStruct with field constraints
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
  def classify_ash_type(type_module, attribute, is_array) do
    cond do
      type_module == Ash.Type.Union ->
        :union_attribute

      is_embedded_resource?(type_module) ->
        if is_array, do: :embedded_resource_array, else: :embedded_resource

      type_module == Ash.Type.Tuple ->
        :tuple

      is_typed_struct_from_attribute?(attribute) ->
        :typed_struct

      # Handle keyword and tuple types with field constraints
      type_module in [Ash.Type.Keyword, Ash.Type.Tuple] ->
        :typed_struct

      true ->
        :attribute
    end
  end

  @doc """
  Checks if an attribute represents a typed struct (has fields and instance_of constraints).

  ## Examples

      iex> attr = %{constraints: [fields: [...], instance_of: MyApp.CustomType]}
      iex> AshTypescript.TypeSystem.Introspection.is_typed_struct_from_attribute?(attr)
      true
  """
  def is_typed_struct_from_attribute?(attribute) do
    constraints = attribute.constraints || []

    with true <- Keyword.has_key?(constraints, :fields),
         true <- Keyword.has_key?(constraints, :instance_of),
         instance_of when is_atom(instance_of) <- Keyword.get(constraints, :instance_of) do
      true
    else
      _ -> false
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
