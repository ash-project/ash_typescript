# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
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

  # ─────────────────────────────────────────────────────────────────
  # Pagination Helpers
  # ─────────────────────────────────────────────────────────────────

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

  @doc """
  Returns true if the action has pagination configuration.
  """
  def has_pagination_config?(action) do
    case action do
      %{pagination: pagination} when is_map(pagination) -> true
      _ -> false
    end
  end

  @doc """
  Gets the pagination configuration for an action.
  """
  def get_pagination_config(action) do
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
    # Get public arguments
    public_arguments = Enum.filter(action.arguments, & &1.public?)

    # Get accepted attributes (for create/update/destroy actions)
    accepted_attributes =
      (Map.get(action, :accept) || [])
      |> Enum.map(&Ash.Resource.Info.attribute(resource, &1))
      |> Enum.reject(&is_nil/1)

    inputs = public_arguments ++ accepted_attributes

    cond do
      Enum.empty?(inputs) ->
        :none

      Enum.any?(inputs, fn
        %Ash.Resource.Actions.Argument{} = input ->
          not input.allow_nil? and is_nil(input.default)

        %Ash.Resource.Attribute{} = input ->
          input.name not in Map.get(action, :allow_nil_input, []) and
              (input.name in Map.get(action, :require_attributes, []) ||
                 (not input.allow_nil? and is_nil(input.default)))
      end) ->
        :required

      true ->
        :optional
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

  # ─────────────────────────────────────────────────────────────────
  # Return Type Classification
  # ─────────────────────────────────────────────────────────────────

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
        {:ok, :unconstrained_map, nil}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Unwraps array wrapper from return type, returning {base_type, constraints, is_array}
  defp unwrap_return_type(action) do
    case action.returns do
      {:array, inner_type} ->
        inner_constraints = Keyword.get(action.constraints || [], :items, [])
        {inner_type, inner_constraints, true}

      type ->
        {type, action.constraints || [], false}
    end
  end

  # Classifies a return type into a category for field selectability
  @spec classify_return_type(atom() | tuple(), keyword()) ::
          {:resource, module()}
          | {:typed_map, keyword()}
          | {:typed_struct, {module(), keyword()}}
          | :unconstrained_map
          | {:error, atom()}
  defp classify_return_type(type, constraints) do
    cond do
      # Ash.Type.Struct with instance_of - represents a resource
      type == Ash.Type.Struct and Keyword.has_key?(constraints, :instance_of) ->
        {:resource, Keyword.get(constraints, :instance_of)}

      # Ash.Type.Struct without instance_of - error
      type == Ash.Type.Struct ->
        {:error, :no_instance_of_defined}

      # Container types with field constraints (Map, Keyword, Tuple)
      type in @field_constrained_types and Keyword.has_key?(constraints, :fields) ->
        {:typed_map, Keyword.get(constraints, :fields)}

      # Container types without field constraints - unconstrained map
      type in @field_constrained_types ->
        :unconstrained_map

      # Module with field constraints (TypedStruct pattern - requires both fields and instance_of)
      is_atom(type) and has_field_constraints?(constraints) ->
        fields = Keyword.get(constraints, :fields, [])
        {:typed_struct, {type, fields}}

      # Not field-selectable
      true ->
        {:error, :not_field_selectable_type}
    end
  end

  defp has_field_constraints?(constraints) do
    Keyword.has_key?(constraints, :fields) and Keyword.has_key?(constraints, :instance_of)
  end
end
