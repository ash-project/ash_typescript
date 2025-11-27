# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.TypeSystem.Introspection do
  @moduledoc """
  Core type introspection and classification for Ash types.

  This module delegates to `AshIntrospection.TypeSystem.Introspection` for the core
  functionality and provides TypeScript-specific extensions.
  """

  # Delegate all core functions to AshIntrospection
  defdelegate is_embedded_resource?(module), to: AshIntrospection.TypeSystem.Introspection
  defdelegate is_primitive_type?(type), to: AshIntrospection.TypeSystem.Introspection
  defdelegate classify_ash_type(type_module, attribute, is_array), to: AshIntrospection.TypeSystem.Introspection
  defdelegate get_union_types(attribute), to: AshIntrospection.TypeSystem.Introspection
  defdelegate get_union_types_from_constraints(type, constraints), to: AshIntrospection.TypeSystem.Introspection
  defdelegate get_inner_type(type), to: AshIntrospection.TypeSystem.Introspection
  defdelegate is_ash_type?(module), to: AshIntrospection.TypeSystem.Introspection

  @doc """
  Recursively unwraps Ash.Type.NewType to get the underlying type and constraints.

  Uses :typescript_field_names as the callback to check for field name mappings.
  """
  def unwrap_new_type(type, constraints) do
    AshIntrospection.TypeSystem.Introspection.unwrap_new_type(type, constraints, :typescript_field_names)
  end

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
  Checks if constraints specify an instance_of that is an Ash resource.

  ## Examples

      iex> AshTypescript.TypeSystem.Introspection.is_resource_instance_of?([instance_of: MyApp.Todo])
      true

      iex> AshTypescript.TypeSystem.Introspection.is_resource_instance_of?([])
      false
  """
  def is_resource_instance_of?(constraints) when is_list(constraints) do
    case Keyword.get(constraints, :instance_of) do
      nil -> false
      module -> is_atom(module) && Ash.Resource.Info.resource?(module)
    end
  end

  def is_resource_instance_of?(_), do: false

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
