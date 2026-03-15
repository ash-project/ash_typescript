# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.TypeSystem.Introspection do
  @moduledoc """
  Core type introspection and classification for Ash types.

  This module provides a centralized set of functions for determining the nature
  and characteristics of Ash types, including embedded resources, typed structs,
  unions, and primitive types.

  ## Fallback vs Primary Helpers

  Some functions in this module serve as **fallback helpers** for code paths that
  don't have access to pre-resolved `%AshApiSpec.Type{}` data. When `resource_lookups`
  or `%AshApiSpec.Type{}` structs are available, prefer using their pre-resolved fields
  (e.g., `type.kind`, `type.resource_module`, `type.fields`) instead of calling:

  - `is_embedded_resource?/1` — use `type.kind in [:resource, :embedded_resource]`
  - `is_resource_instance_of?/1` — use `type.resource_module` or `type.instance_of`
  - `has_field_constraints?/1` — use `type.fields != []`
  - `get_union_types_from_constraints/2` — use `type.constraints[:types]`

  The following remain primary helpers used regardless of `%AshApiSpec.Type{}` availability:

  - `is_custom_type?/1` — TypeScript callback detection
  - `has_typescript_field_names?/1` — TypeScript field name callback detection
  - `get_typescript_field_names_map/1` — TypeScript field name retrieval
  - `build_reverse_field_names_map/1` — Reverse client→internal name mapping
  - `unwrap_new_type/2` — NewType unwrapping (only for atom types, not `%AshApiSpec.Type{}`)
  """

  @doc """
  Checks if a module is an embedded Ash resource.

  **Fallback helper** — when `%AshApiSpec.Type{}` is available, use
  `type.kind in [:resource, :embedded_resource]` instead.

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

  **Fallback helper** — when `%AshApiSpec.Type{}` is available, use
  `type.resource_module` or `type.instance_of` instead.

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

  **Fallback helper** — when `%AshApiSpec.Type{}` is available, use
  `type.fields != []` instead.

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
