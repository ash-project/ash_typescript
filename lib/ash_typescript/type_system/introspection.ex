# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.TypeSystem.Introspection do
  @moduledoc """
  Core type introspection and classification for Ash types.

  This module provides a centralized set of functions for determining the nature
  and characteristics of Ash types, including embedded resources, typed structs,
  NewTypes, custom types, and primitive types.

  Used throughout the codebase for type checking, code generation, and runtime
  processing.
  """

  defdelegate is_embedded_resource?(module), to: AshRpc.Introspection, as: :embedded_resource?

  @doc """
  Unwraps one `Ash.Type.NewType` layer into its subtype and full constraints.

  If the NewType defines `typescript_field_names/0` and the constraints carry
  no `instance_of` yet, the NewType is added as `instance_of` so its field
  name mapping stays reachable (the outermost such NewType wins).

  ## Examples

      iex> AshTypescript.TypeSystem.Introspection.unwrap_new_type(Ash.Type.String, max_length: 50)
      {Ash.Type.String, [max_length: 50]}
  """
  @spec unwrap_new_type(term(), keyword()) :: {term(), keyword()}
  def unwrap_new_type(type, constraints) when is_atom(type) do
    {subtype, constraints} =
      Ash.Info.Manifest.Generator.TypeResolver.unwrap_new_type(type, constraints)

    if subtype != type and AshTypescript.Helpers.has_typescript_field_names?(type) and
         not Keyword.has_key?(constraints, :instance_of) do
      {subtype, Keyword.put(constraints, :instance_of, type)}
    else
      {subtype, constraints}
    end
  end

  def unwrap_new_type(type, constraints), do: {type, constraints}

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
      Ash.Type.Duration,
      Ash.Type.Atom,
      Ash.Type.UUID,
      Ash.Type.Binary
    ]
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

  @doc """
  Checks if a type is a custom Ash type with a typescript_type_name callback.

  Custom types are Ash types that define a `typescript_type_name/0` callback
  to specify their TypeScript representation.

  ## Examples

      iex> AshTypescript.TypeSystem.Introspection.is_custom_type?(MyApp.MyCustomType)
      true

      iex> AshTypescript.TypeSystem.Introspection.is_custom_type?(Ash.Type.String)
      false
  """
  def is_custom_type?(type) when is_atom(type) and not is_nil(type) do
    Code.ensure_loaded?(type) and
      function_exported?(type, :typescript_type_name, 0) and
      Spark.implements_behaviour?(type, Ash.Type)
  end

  def is_custom_type?(_), do: false

  # ---------------------------------------------------------------------------
  # TypeScript Field Names Helpers
  # ---------------------------------------------------------------------------

  @doc """
  Checks if a module has a typescript_field_names/0 callback.

  ## Examples

      iex> AshTypescript.TypeSystem.Introspection.has_typescript_field_names?(MyApp.TaskStats)
      true

      iex> AshTypescript.TypeSystem.Introspection.has_typescript_field_names?(Ash.Type.String)
      false
  """
  def has_typescript_field_names?(nil), do: false

  def has_typescript_field_names?(module) when is_atom(module) do
    Code.ensure_loaded?(module) && function_exported?(module, :typescript_field_names, 0)
  end

  def has_typescript_field_names?(_), do: false

  @doc """
  Returns the full definition of a named type (a `:type_ref` module).

  Looks the type up in the manifest first. Named types outside the manifest —
  e.g. a NewType referenced only by a typed controller route, which RPC
  reachability never collects — are resolved directly from the module.
  """
  @spec named_type_definition(module()) :: Ash.Info.Manifest.Type.t()
  def named_type_definition(module) do
    Ash.Info.Manifest.get_type(AshTypescript.type_lookup(), module) ||
      Ash.Info.Manifest.Generator.TypeResolver.resolve_definition(module)
  end

  @doc """
  Gets the typescript_field_names as a map, or empty map if not available.

  ## Examples

      iex> AshTypescript.TypeSystem.Introspection.get_typescript_field_names_map(MyApp.TaskStats)
      %{is_active?: "isActive", meta_1: "meta1"}
  """
  def get_typescript_field_names_map(nil), do: %{}

  def get_typescript_field_names_map(module) when is_atom(module) do
    if has_typescript_field_names?(module) do
      module.typescript_field_names() |> Map.new()
    else
      %{}
    end
  end

  def get_typescript_field_names_map(_), do: %{}

  @doc """
  Builds a reverse mapping from client names to internal names.

  Can take either a map of field names or a module with typescript_field_names/0.

  ## Examples

      iex> AshTypescript.TypeSystem.Introspection.build_reverse_field_names_map(%{is_active?: "isActive"})
      %{"isActive" => :is_active?}

      iex> AshTypescript.TypeSystem.Introspection.build_reverse_field_names_map(MyApp.TaskStats)
      %{"isActive" => :is_active?, "meta1" => :meta_1}
  """
  def build_reverse_field_names_map(ts_field_names) when is_map(ts_field_names) do
    ts_field_names
    |> Enum.map(fn {internal, client} -> {client, internal} end)
    |> Map.new()
  end

  def build_reverse_field_names_map(module) when is_atom(module) do
    module
    |> get_typescript_field_names_map()
    |> build_reverse_field_names_map()
  end

  def build_reverse_field_names_map(_), do: %{}

  # ---------------------------------------------------------------------------
  # Type Constraint Helpers
  # ---------------------------------------------------------------------------

  @doc """
  Checks if constraints include non-empty field definitions.

  ## Examples

      iex> AshTypescript.TypeSystem.Introspection.has_field_constraints?([fields: [name: [type: :string]]])
      true

      iex> AshTypescript.TypeSystem.Introspection.has_field_constraints?([fields: []])
      false
  """
  def has_field_constraints?(constraints) when is_list(constraints) do
    Keyword.has_key?(constraints, :fields) && Keyword.get(constraints, :fields) != []
  end

  def has_field_constraints?(_), do: false

  @doc """
  Gets the type and constraints for a field from field specs.

  ## Examples

      iex> specs = [name: [type: :string], age: [type: :integer]]
      iex> AshTypescript.TypeSystem.Introspection.get_field_spec_type(specs, :name)
      {:string, []}

      iex> AshTypescript.TypeSystem.Introspection.get_field_spec_type(specs, :unknown)
      {nil, []}
  """
  def get_field_spec_type(field_specs, field_name) when is_list(field_specs) do
    case Enum.find(field_specs, fn {name, _spec} -> name == field_name end) do
      nil -> {nil, []}
      {_name, spec} -> {Keyword.get(spec, :type), Keyword.get(spec, :constraints, [])}
    end
  end

  def get_field_spec_type(_, _), do: {nil, []}
end
