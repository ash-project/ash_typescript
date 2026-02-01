# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
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
  Gets the mapped TypeScript client name for a field, or returns nil if no mapping exists.

  The mapped value is always a string representing the exact TypeScript client name.

  ## Examples

      iex> AshTypescript.Resource.Info.get_mapped_field_name(MyApp.User, :is_active?)
      "isActive"

      iex> AshTypescript.Resource.Info.get_mapped_field_name(MyApp.User, :normal_field)
      nil
  """
  def get_mapped_field_name(resource, field_name) do
    mapped_names = __MODULE__.typescript_field_names!(resource)
    Keyword.get(mapped_names, field_name)
  end

  @doc """
  Gets the original Elixir field name for a TypeScript client field name.

  The client_field_name should be a string like "isActive".
  Returns the original Elixir atom like :is_active?, or the input if no mapping exists.

  ## Examples

      iex> AshTypescript.Resource.Info.get_original_field_name(MyApp.User, "isActive")
      :is_active?

      iex> AshTypescript.Resource.Info.get_original_field_name(MyApp.User, "normalField")
      "normalField"
  """
  def get_original_field_name(resource, client_field_name) do
    mapped_names = __MODULE__.typescript_field_names!(resource)

    # client_field_name can be a string (from client) or atom (from atomized field selection)
    client_name_str =
      if is_atom(client_field_name),
        do: Atom.to_string(client_field_name),
        else: client_field_name

    case Enum.find(mapped_names, fn {_original, mapped} -> mapped == client_name_str end) do
      {original, _mapped} -> original
      nil -> client_field_name
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
