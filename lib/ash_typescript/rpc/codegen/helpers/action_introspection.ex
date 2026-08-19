# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Codegen.Helpers.ActionIntrospection do
  @moduledoc """
  Provides helper functions for analyzing Ash actions.

  This module contains utilities for determining action characteristics like:
  - Pagination support (offset, keyset, required, countable)
  - Input requirements
  - Return type field selectability

  The return type analysis uses a type-driven classification pattern with
  `classify_return_type/2` for consistent handling of all type variants.
  """

  alias AshTypescript.TypeSystem.Introspection

  # Container types that can have field constraints for field selection
  @field_constrained_types [Ash.Type.Map, Ash.Type.Keyword, Ash.Type.Tuple]

  @doc """
  Looks up an action in the configured manifest's action lookup and raises on miss.

  Use at runtime sites that have already validated action existence upstream
  (e.g. `Pipeline.discover_action/2` returns `{:error, {:action_not_found, …}}`
  before reaching parse-time lookup), so a miss here indicates an internal
  consistency error rather than user input.
  """
  def get_action!(resource, action_name) do
    case Map.get(AshTypescript.action_lookup(), {resource, action_name}) do
      %Ash.Info.Manifest.Action{} = action ->
        action

      nil ->
        raise "action #{inspect(action_name)} not found on #{inspect(resource)} in manifest"
    end
  end

  @doc """
  Returns true if the action supports pagination.

  ## Examples

      iex> action_supports_pagination?(%{type: :read, get?: false, pagination: %{offset?: true}})
      true

      iex> action_supports_pagination?(%{type: :read, get?: true})
      false
  """
  def action_supports_pagination?(action) do
    action.type == :read and not action.get? and has_pagination_config?(action)
  end

  @doc """
  Returns true if the action supports offset-based pagination.
  """
  def action_supports_offset_pagination?(action) do
    case get_pagination_config(action) do
      nil -> false
      pagination_config -> Map.get(pagination_config, :offset?, false)
    end
  end

  @doc """
  Returns true if the action supports keyset-based pagination.
  """
  def action_supports_keyset_pagination?(action) do
    case get_pagination_config(action) do
      nil -> false
      pagination_config -> Map.get(pagination_config, :keyset?, false)
    end
  end

  @doc """
  Returns true if the action requires pagination.
  """
  def action_requires_pagination?(action) do
    case get_pagination_config(action) do
      nil -> false
      pagination_config -> Map.get(pagination_config, :required?, false)
    end
  end

  @doc """
  Returns true if the action supports countable pagination.
  """
  def action_supports_countable?(action) do
    case get_pagination_config(action) do
      nil ->
        false

      pagination_config ->
        # Ash.Info.Manifest.Pagination uses `:countable?`; raw Ash uses `:countable`
        Map.get(pagination_config, :countable?) || Map.get(pagination_config, :countable, false)
    end
  end

  @doc """
  Returns true if the action has a default limit configured.
  """
  def action_has_default_limit?(action) do
    case get_pagination_config(action) do
      nil -> false
      pagination_config -> Map.has_key?(pagination_config, :default_limit)
    end
  end

  defp has_pagination_config?(action) do
    case action do
      %{pagination: pagination} when is_map(pagination) -> true
      _ -> false
    end
  end

  defp get_pagination_config(action) do
    case action do
      %{pagination: pagination} when is_map(pagination) -> pagination
      _ -> nil
    end
  end

  @doc """
  Returns :required | :optional | :none.

  Inspects the action's unified `inputs` list. Each `Ash.Info.Manifest.Argument`
  carries `required?` directly — describing input presence independent of value
  shape (`allow_nil?` / `has_default?`).
  """
  def action_input_type(action) do
    inputs = action.inputs

    cond do
      inputs == [] -> :none
      Enum.any?(inputs, & &1.required?) -> :required
      true -> :optional
    end
  end

  @doc """
  Returns `true` if `input_name` refers to an accepted attribute on `resource`
  (i.e. present in the manifest resource's `fields` map) rather than a
  declared action argument. Used to decide whether to apply field-name mapping
  or argument-name mapping to an `Ash.Info.Manifest.Argument`.
  """
  def accepted_attribute?(resource, input_name, resource_lookup) do
    case Map.get(resource_lookup || %{}, resource) do
      %Ash.Info.Manifest.Resource{fields: fields} when is_map(fields) ->
        Map.has_key?(fields, input_name)

      _ ->
        false
    end
  end

  @doc """
  Resolves the TypeScript client name for an action input.

  Accepted attributes (present in the resource's field map) use field-name
  mapping via `format_field_for_client/3` (resource-aware, honors `field_names`
  DSL). Declared action arguments use `argument_names` mapping via
  `format_field_name/2` (formatter only — arguments don't carry resource field
  metadata).
  """
  def format_input_name(resource, action_name, input_name, resource_lookup, formatter \\ nil) do
    formatter = formatter || AshTypescript.Rpc.output_field_formatter()

    if accepted_attribute?(resource, input_name, resource_lookup) do
      AshTypescript.FieldFormatter.format_field_for_client(input_name, resource, formatter)
    else
      mapped =
        AshTypescript.Resource.Info.get_mapped_argument_name(resource, action_name, input_name)

      cond do
        is_binary(mapped) ->
          mapped

        mapped == input_name ->
          AshTypescript.FieldFormatter.format_field_name(input_name, formatter)

        true ->
          AshTypescript.FieldFormatter.format_field_name(mapped, formatter)
      end
    end
  end

  @doc """
  Checks if a generic action returns a field-selectable type.

  Returns:
  - `{:ok, :resource, resource_module}` - Single resource
  - `{:ok, :array_of_resource, resource_module}` - Array of resources
  - `{:ok, :typed_map, fields}` - Typed map with constraints
  - `{:ok, :array_of_typed_map, fields}` - Array of typed maps
  - `{:ok, :typed_struct, {module, fields}}` - Type with field constraints (TypedStruct or similar)
  - `{:ok, :array_of_typed_struct, {module, fields}}` - Array of types with field constraints
  - `{:ok, :unconstrained_map, nil}` - Map without field constraints
  - `{:ok, :array_of_unconstrained_map, nil}` - Array of maps without field constraints
  - `{:error, :not_generic_action}` - Not a generic action
  - `{:error, reason}` - Other errors
  """
  def action_returns_field_selectable_type?(action) do
    case AshTypescript.Manifest.Custom.action_return_classification(action) do
      nil -> compute_action_returns_field_selectable_type?(action, AshTypescript.type_lookup())
      cached -> cached
    end
  end

  @doc """
  Pure computation of `action_returns_field_selectable_type?/1`, taking an
  explicit `type_lookup` so it can run during manifest decoration (before the
  `:type_lookup` is persisted). The decorator stores the result on the action's
  `custom.ash_typescript` so the runtime path is a plain map read.
  """
  def compute_action_returns_field_selectable_type?(action, type_lookup) do
    if action.type != :action do
      {:error, :not_generic_action}
    else
      check_action_returns(action, type_lookup)
    end
  end

  defp check_action_returns(action, type_lookup) do
    {base_type, constraints, is_array} = unwrap_return_type(action, type_lookup)

    {unwrapped_type, unwrapped_constraints} =
      Introspection.unwrap_new_type(base_type, constraints)

    case classify_return_type(unwrapped_type, unwrapped_constraints, type_lookup) do
      {:resource, module} ->
        if is_array do
          {:ok, :array_of_resource, module}
        else
          {:ok, :resource, module}
        end

      {:typed_map, fields} ->
        if is_array do
          {:ok, :array_of_typed_map, fields}
        else
          {:ok, :typed_map, fields}
        end

      {:typed_struct, {module, fields}} ->
        if is_array do
          {:ok, :array_of_typed_struct, {module, fields}}
        else
          {:ok, :typed_struct, {module, fields}}
        end

      :unconstrained_map ->
        if is_array do
          {:ok, :array_of_unconstrained_map, nil}
        else
          {:ok, :unconstrained_map, nil}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp unwrap_return_type(action, type_lookup) do
    case action.returns do
      # Ash.Info.Manifest.Type with array kind
      %Ash.Info.Manifest.Type{kind: :array, item_type: item_type} ->
        {item_type, [], true}

      # Ash.Info.Manifest.Type ref — resolve before continuing
      %Ash.Info.Manifest.Type{kind: :type_ref, module: module} ->
        full_type = Ash.Info.Manifest.get_type!(type_lookup, module)
        {full_type, [], false}

      # Ash.Info.Manifest.Type (non-array)
      %Ash.Info.Manifest.Type{} = type ->
        {type, [], false}

      # Legacy: raw Ash type tuple
      {:array, inner_type} ->
        inner_constraints = Keyword.get(Map.get(action, :constraints) || [], :items, [])
        {inner_type, inner_constraints, true}

      type ->
        {type, Map.get(action, :constraints) || [], false}
    end
  end

  # Classifies a return type into a category for field selectability
  @spec classify_return_type(
          atom() | tuple() | Ash.Info.Manifest.Type.t(),
          keyword(),
          map()
        ) ::
          {:resource, module()}
          | {:typed_map, keyword()}
          | {:typed_struct, {module(), keyword()}}
          | :unconstrained_map
          | {:error, atom()}
  # Ash.Info.Manifest.Type classification
  defp classify_return_type(
         %Ash.Info.Manifest.Type{kind: :type_ref, module: module},
         _constraints,
         type_lookup
       ) do
    full_type = Ash.Info.Manifest.get_type!(type_lookup, module)
    classify_return_type(full_type, [], type_lookup)
  end

  defp classify_return_type(
         %Ash.Info.Manifest.Type{kind: kind, resource_module: mod},
         _constraints,
         _type_lookup
       )
       when kind in [:resource, :embedded_resource] and not is_nil(mod) do
    {:resource, mod}
  end

  defp classify_return_type(
         %Ash.Info.Manifest.Type{kind: :struct, fields: fields, instance_of: inst},
         _constraints,
         _type_lookup
       )
       when is_list(fields) and fields != [] and not is_nil(inst) do
    {:typed_struct, {inst, fields}}
  end

  defp classify_return_type(
         %Ash.Info.Manifest.Type{kind: kind} = type_info,
         _constraints,
         _type_lookup
       )
       when kind in [:map, :keyword, :tuple] do
    fields = Ash.Info.Manifest.Type.get_fields(type_info)

    if fields != [] do
      {:typed_map, fields}
    else
      :unconstrained_map
    end
  end

  defp classify_return_type(%Ash.Info.Manifest.Type{}, _constraints, _type_lookup) do
    {:error, :not_field_selectable_type}
  end

  # Legacy raw Ash type classification
  defp classify_return_type(type, constraints, _type_lookup) do
    cond do
      type == Ash.Type.Struct and Keyword.has_key?(constraints, :instance_of) ->
        instance_of = Keyword.get(constraints, :instance_of)

        cond do
          Ash.Resource.Info.resource?(instance_of) ->
            {:resource, instance_of}

          Keyword.has_key?(constraints, :fields) ->
            {:typed_struct, {instance_of, Keyword.get(constraints, :fields, [])}}

          true ->
            {:error, :not_field_selectable_type}
        end

      type == Ash.Type.Struct ->
        {:error, :no_instance_of_defined}

      type in @field_constrained_types and Keyword.has_key?(constraints, :fields) ->
        {:typed_map, Keyword.get(constraints, :fields)}

      type in @field_constrained_types ->
        :unconstrained_map

      is_atom(type) and has_field_constraints?(constraints) ->
        fields = Keyword.get(constraints, :fields, [])
        {:typed_struct, {type, fields}}

      true ->
        {:error, :not_field_selectable_type}
    end
  end

  defp has_field_constraints?(constraints) do
    Keyword.has_key?(constraints, :fields) and Keyword.has_key?(constraints, :instance_of)
  end
end
