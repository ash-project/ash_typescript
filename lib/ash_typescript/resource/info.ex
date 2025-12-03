# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Resource.Info do
  @moduledoc """
  Provides introspection functions for AshTypescript.Resource configuration.

  This module generates helper functions to access TypeScript configuration
  defined on resources using the AshTypescript.Resource DSL extension.
  """
  use Spark.InfoGenerator, extension: AshTypescript.Resource, sections: [:typescript]

  @doc "Whether or not a given module is a resource module using the AshTypescript.Resource extension"
  @spec typescript_resource?(module) :: boolean
  def typescript_resource?(module) when is_atom(module) do
    typescript_type_name!(module)
    true
  rescue
    _ -> false
  end

  @doc """
  Gets the mapped name for a field, or returns the original name if no mapping exists.
  """
  def get_mapped_field_name(resource, field_name) do
    mapped_names = __MODULE__.typescript_field_names!(resource)
    Keyword.get(mapped_names, field_name, field_name)
  end

  @doc """
  Gets the original invalid field name for a mapped field name.
  Returns the field name that was mapped to the given valid name, or the same field name if no mapping exists.

  This function handles the case where the incoming field name has been converted to snake_case
  by the field formatter. It compares both the exact value and the snake_case version of
  each mapped value to find a match.

  ## Examples

      iex> AshTypescript.Resource.Info.get_original_field_name(MyApp.User, :address_line1)
      :address_line_1

      iex> AshTypescript.Resource.Info.get_original_field_name(MyApp.User, :normal_field)
      nil

      # Also handles snake_case converted camelCase mapped names
      iex> AshTypescript.Resource.Info.get_original_field_name(MyApp.User, :available_for_purchase)
      :available_for_purchase?  # When mapping is available_for_purchase?: :availableForPurchase
  """
  def get_original_field_name(resource, mapped_field_name) do
    mapped_names = __MODULE__.typescript_field_names!(resource)
    mapped_field_name_string = to_string(mapped_field_name)

    # First try exact match
    case Enum.find(mapped_names, fn {_original, mapped} -> mapped == mapped_field_name end) do
      {original, _mapped} ->
        original

      nil ->
        # If no exact match, try matching the snake_case version of each mapped value
        # This handles the case where the field formatter converted "availableForPurchase"
        # to "available_for_purchase" before the lookup
        case Enum.find(mapped_names, fn {_original, mapped} ->
               AshTypescript.Helpers.camel_to_snake_case(to_string(mapped)) ==
                 mapped_field_name_string
             end) do
          {original, _mapped} -> original
          nil -> mapped_field_name
        end
    end
  end

  @doc """
  Gets the mapped name for an argument, or returns the original name if no mapping exists.

  ## Examples

      iex> AshTypescript.Resource.Info.get_mapped_argument_name(MyApp.User, :read_with_invalid_arg, :is_active?)
      :is_active
  """
  def get_mapped_argument_name(resource, action_name, argument_name) do
    argument_mappings = __MODULE__.typescript_argument_names!(resource)

    action_mappings = Keyword.get(argument_mappings, action_name, [])
    Keyword.get(action_mappings, argument_name, argument_name)
  end

  @doc """
  Gets the original invalid argument name for a mapped argument name.
  Returns the argument name that was mapped to the given valid name, or the same name if no mapping exists.

  ## Examples

      iex> AshTypescript.Resource.Info.get_original_argument_name(MyApp.User, :read_with_invalid_arg, :is_active)
      :is_active?
  """
  def get_original_argument_name(resource, action_name, mapped_argument_name) do
    argument_mappings = __MODULE__.typescript_argument_names!(resource)

    action_mappings = Keyword.get(argument_mappings, action_name, [])

    case Enum.find(action_mappings, fn {_original, mapped} -> mapped == mapped_argument_name end) do
      {original, _mapped} -> original
      nil -> mapped_argument_name
    end
  end
end
