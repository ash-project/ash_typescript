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
    try do
      typescript_type_name!(module)
      true
    rescue
      _ -> false
    end
  end
end
