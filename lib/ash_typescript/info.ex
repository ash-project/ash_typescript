defmodule AshTypescript.Resource.Info do
  @moduledoc """
  Provides introspection functions for AshTypescript.Resource configuration.

  This module generates helper functions to access TypeScript configuration
  defined on resources using the AshTypescript.Resource DSL extension.
  """
  use Spark.InfoGenerator, extension: AshTypescript.Resource, sections: [:typescript]
end
