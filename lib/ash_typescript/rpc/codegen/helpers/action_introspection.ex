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
  """

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
  """
  def action_input_type(resource, action) do
    inputs =
      resource
      |> Ash.Resource.Info.action_inputs(action.name)
      |> Enum.filter(&is_atom/1)
      |> Enum.map(fn input ->
        Enum.find(action.arguments, fn argument ->
          argument.name == input
        end) || Ash.Resource.Info.attribute(resource, input)
      end)
      |> Enum.uniq_by(& &1.name)

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

  defp check_action_returns(action) do
    case action.returns do
      {:array, Ash.Type.Struct} ->
        items_constraints = Keyword.get(action.constraints || [], :items, [])

        if Keyword.has_key?(items_constraints, :instance_of) do
          {:ok, :array_of_resource, Keyword.get(items_constraints, :instance_of)}
        else
          {:error, :no_instance_of_defined}
        end

      Ash.Type.Struct ->
        constraints = action.constraints || []

        if Keyword.has_key?(constraints, :instance_of) do
          {:ok, :resource, Keyword.get(constraints, :instance_of)}
        else
          {:error, :no_instance_of_defined}
        end

      {:array, map_like} when map_like in [Ash.Type.Map, Ash.Type.Keyword, Ash.Type.Keyword] ->
        items_constraints = Keyword.get(action.constraints || [], :items, [])

        if Keyword.has_key?(items_constraints, :fields) do
          {:ok, :array_of_typed_map, Keyword.get(items_constraints, :fields)}
        else
          {:error, :no_fields_defined}
        end

      {:array, module} when is_atom(module) ->
        constraints = action.constraints || []
        items_constraints = Keyword.get(constraints, :items, [])

        if has_field_constraints?(items_constraints) do
          fields = Keyword.get(items_constraints, :fields, [])
          {:ok, :array_of_typed_struct, {module, fields}}
        else
          {:error, :not_field_selectable_type}
        end

      map_like when map_like in [Ash.Type.Map, Ash.Type.Keyword, Ash.Type.Keyword] ->
        constraints = action.constraints || []

        if Keyword.has_key?(constraints, :fields) do
          {:ok, :typed_map, Keyword.get(constraints, :fields)}
        else
          {:ok, :unconstrained_map, nil}
        end

      module when is_atom(module) ->
        constraints = action.constraints || []

        if has_field_constraints?(constraints) do
          fields = Keyword.get(constraints, :fields, [])
          {:ok, :typed_struct, {module, fields}}
        else
          {:error, :not_field_selectable_type}
        end

      _ ->
        {:error, :not_field_selectable_type}
    end
  end

  defp has_field_constraints?(constraints) do
    Keyword.has_key?(constraints, :fields) and Keyword.has_key?(constraints, :instance_of)
  end
end
