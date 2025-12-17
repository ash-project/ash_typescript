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
      Ash.Type.Duration,
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

  @doc """
  Recursively unwraps Ash.Type.NewType to get the underlying type and constraints.

  When a type is wrapped in one or more NewType wrappers, this function
  recursively unwraps them until it reaches the base type. If the NewType
  has a `typescript_field_names/0` callback and the constraints don't already
  have an `instance_of` key, it will add the NewType module as `instance_of`
  to preserve the reference for field name mapping.

  ## Parameters
  - `type` - The type to unwrap (e.g., MyApp.CustomType)
  - `constraints` - The constraints for the type

  ## Returns
  A tuple `{unwrapped_type, unwrapped_constraints}` where:
  - `unwrapped_type` is the final underlying type after all NewType unwrapping
  - `unwrapped_constraints` are the final constraints, potentially augmented with `instance_of`

  ## Examples

      iex> # Simple NewType with typescript_field_names
      iex> unwrap_new_type(MyApp.TaskStats, [])
      {Ash.Type.Struct, [fields: [...], instance_of: MyApp.TaskStats]}

      iex> # Nested NewTypes (outermost with callback wins)
      iex> unwrap_new_type(MyApp.Wrapper, [])
      {Ash.Type.String, [max_length: 100, instance_of: MyApp.Wrapper]}

      iex> # Non-NewType (returns unchanged)
      iex> unwrap_new_type(Ash.Type.String, [max_length: 50])
      {Ash.Type.String, [max_length: 50]}
  """
  def unwrap_new_type(type, constraints) when is_atom(type) do
    if Ash.Type.NewType.new_type?(type) do
      subtype = Ash.Type.NewType.subtype_of(type)

      # Get constraints from the NewType
      # Ash.Type.NewType.constraints/2 only returns passed constraints when lazy_init? is false,
      # but do_init/1 returns the full merged constraints including subtype_constraints
      constraints =
        case type.do_init(constraints) do
          {:ok, merged_constraints} -> merged_constraints
          {:error, _} -> constraints
        end

      # Preserve reference to outermost NewType with typescript_field_names
      # Only add instance_of if:
      # 1. This NewType has typescript_field_names callback
      # 2. Constraints don't already have instance_of (preserves outermost)
      augmented_constraints =
        if function_exported?(type, :typescript_field_names, 0) and
             not Keyword.has_key?(constraints, :instance_of) do
          Keyword.put(constraints, :instance_of, type)
        else
          constraints
        end

      {subtype, augmented_constraints}
    else
      {type, constraints}
    end
  end

  def unwrap_new_type(type, constraints), do: {type, constraints}

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
