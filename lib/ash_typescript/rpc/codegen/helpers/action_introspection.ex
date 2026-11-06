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

  The return type classification comes from ash_rpc
  (`AshRpc.Introspection.compute_return_classification/2`).
  """

  defdelegate action_supports_pagination?(action), to: AshRpc.Introspection
  defdelegate action_supports_offset_pagination?(action), to: AshRpc.Introspection
  defdelegate action_supports_keyset_pagination?(action), to: AshRpc.Introspection
  defdelegate action_requires_pagination?(action), to: AshRpc.Introspection
  defdelegate action_supports_countable?(action), to: AshRpc.Introspection
  defdelegate action_has_default_limit?(action), to: AshRpc.Introspection

  defdelegate compute_action_returns_field_selectable_type?(action, type_lookup),
    to: AshRpc.Introspection,
    as: :compute_return_classification

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
end
