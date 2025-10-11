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
    mapped_names = __MODULE__.typescript_mapped_field_names!(resource)
    Keyword.get(mapped_names, field_name, field_name)
  end

  @doc """
  Gets the original invalid field name for a mapped field name.
  Returns the field name that was mapped to the given valid name, or the same field name if no mapping exists.

  ## Examples

      iex> AshTypescript.Resource.Info.get_original_field_name(MyApp.User, :address_line1)
      :address_line_1

      iex> AshTypescript.Resource.Info.get_original_field_name(MyApp.User, :normal_field)
      nil
  """
  def get_original_field_name(resource, mapped_field_name) do
    mapped_names = __MODULE__.typescript_mapped_field_names!(resource)

    case Enum.find(mapped_names, fn {_original, mapped} -> mapped == mapped_field_name end) do
      {original, _mapped} -> original
      nil -> mapped_field_name
    end
  end
end
