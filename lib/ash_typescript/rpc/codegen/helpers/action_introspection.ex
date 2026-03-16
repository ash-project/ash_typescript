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

  # Container types that can have field constraints for field selection
  @field_constrained_types [Ash.Type.Map, Ash.Type.Keyword, Ash.Type.Tuple]

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
      nil -> false
      pagination_config -> Map.get(pagination_config, :countable, false)
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
  Returns :required | :optional | :none

  Determines whether an action requires input, has optional input, or has no input.
  This is based on the action's public arguments and accepted attributes.
  """
  def action_input_type(resource, action) do
    action_input_type(resource, action, AshTypescript.resource_lookup(Mix.Project.config()[:app]))
  end

  @doc """
  Returns :required | :optional | :none (with pre-computed resource_lookup).

  Same as `action_input_type/2` but avoids regenerating the resource lookup.
  """
  def action_input_type(resource, action, resource_lookup) do
    arguments = action.arguments

    # Get accepted attributes from the spec's fields
    accepted_fields = get_accepted_fields(resource, action, resource_lookup)

    inputs = arguments ++ accepted_fields

    cond do
      Enum.empty?(inputs) ->
        :none

      Enum.any?(inputs, &input_is_required?(&1, action)) ->
        :required

      true ->
        :optional
    end
  end

  defp input_is_required?(%AshApiSpec.Argument{} = arg, _action) do
    not arg.allow_nil? and not arg.has_default?
  end

  defp input_is_required?(%AshApiSpec.Field{} = field, action) do
    field.name not in (action.allow_nil_input || []) and
      (field.name in (action.require_attributes || []) ||
         (not field.allow_nil? and not field.has_default?))
  end

  # Fallback for raw Ash structs (used in tests or legacy paths)
  defp input_is_required?(%{allow_nil?: allow_nil?} = input, action) do
    has_default? = Map.get(input, :has_default?, is_nil(Map.get(input, :default)))

    if match?(%{name: _}, input) and Map.has_key?(action, :allow_nil_input) do
      input.name not in (action.allow_nil_input || []) and
        (input.name in (Map.get(action, :require_attributes) || []) ||
           (not allow_nil? and not has_default?))
    else
      not allow_nil? and not has_default?
    end
  end

  defp get_accepted_fields(resource, action, resource_lookup) do
    case Map.get(action, :accept) || [] do
      [] ->
        []

      accept_list ->
        case Map.get(resource_lookup, resource) do
          %AshApiSpec.Resource{} = api_resource ->
            accept_list
            |> Enum.map(&Map.get(api_resource.fields, &1))
            |> Enum.reject(&is_nil/1)

          nil ->
            []
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
    if action.type != :action do
      {:error, :not_generic_action}
    else
      check_action_returns(action)
    end
  end

  defp check_action_returns(action) do
    {base_type, constraints, is_array} = unwrap_return_type(action)

    case classify_return_type(base_type, constraints) do
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

  defp unwrap_return_type(action) do
    case action.returns do
      # AshApiSpec.Type with array kind
      %AshApiSpec.Type{kind: :array, item_type: item_type} ->
        {item_type, [], true}

      # AshApiSpec.Type ref — resolve before continuing
      %AshApiSpec.Type{kind: :type_ref, module: module} ->
        full_type = AshApiSpec.Generator.TypeResolver.resolve_definition(module)
        {full_type, [], false}

      # AshApiSpec.Type (non-array)
      %AshApiSpec.Type{} = type ->
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
  @spec classify_return_type(atom() | tuple() | AshApiSpec.Type.t(), keyword()) ::
          {:resource, module()}
          | {:typed_map, keyword()}
          | {:typed_struct, {module(), keyword()}}
          | :unconstrained_map
          | {:error, atom()}
  # AshApiSpec.Type classification
  defp classify_return_type(%AshApiSpec.Type{kind: :type_ref, module: module}, _constraints) do
    full_type = AshApiSpec.Generator.TypeResolver.resolve_definition(module)
    classify_return_type(full_type, [])
  end

  defp classify_return_type(%AshApiSpec.Type{kind: kind, resource_module: mod}, _constraints)
       when kind in [:resource, :embedded_resource] and not is_nil(mod) do
    {:resource, mod}
  end

  defp classify_return_type(
         %AshApiSpec.Type{kind: :struct, fields: fields, instance_of: inst},
         _constraints
       )
       when is_list(fields) and fields != [] and not is_nil(inst) do
    {:typed_struct, {inst, fields}}
  end

  defp classify_return_type(%AshApiSpec.Type{kind: kind} = type_info, _constraints)
       when kind in [:map, :keyword, :tuple] do
    fields = AshApiSpec.Type.get_fields(type_info)

    if fields != [] do
      {:typed_map, fields}
    else
      :unconstrained_map
    end
  end

  defp classify_return_type(%AshApiSpec.Type{}, _constraints) do
    {:error, :not_field_selectable_type}
  end

  # Legacy raw Ash type classification
  defp classify_return_type(type, constraints) do
    cond do
      type == Ash.Type.Struct and Keyword.has_key?(constraints, :instance_of) ->
        {:resource, Keyword.get(constraints, :instance_of)}

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
