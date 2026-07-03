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
  Gets the pre-computed formatted client name for a field under a built-in formatter.

  Backed by `Spark.Dsl.Transformer.persist/3` populated at compile time by
  `AshTypescript.Resource.Transformers.PersistFormattedFields`. Returns the
  formatted string, or `nil` if the resource is not an `AshTypescript.Resource`,
  the field is not a public attribute/relationship/calculation/aggregate, or the
  formatter is not one of the built-in atoms (`:camel_case`, `:snake_case`,
  `:pascal_case`).

  ## Examples

      iex> AshTypescript.Resource.Info.get_formatted_field(MyApp.User, :first_name, :camel_case)
      "firstName"

      iex> AshTypescript.Resource.Info.get_formatted_field(MyApp.User, :is_active?, :camel_case)
      "isActive"
  """
  def get_formatted_field(resource, field, formatter)
      when is_atom(resource) and is_atom(field) do
    Spark.Dsl.Extension.get_persisted(
      resource,
      {:typescript_formatted_fields, field, formatter}
    )
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
end
