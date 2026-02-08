# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.ControllerResource.Info do
  @moduledoc """
  Provides introspection functions for AshTypescript.ControllerResource configuration.

  This module generates helper functions to access controller configuration
  defined on resources using the AshTypescript.ControllerResource DSL extension.
  """
  use Spark.InfoGenerator,
    extension: AshTypescript.ControllerResource,
    sections: [:controller]

  @doc "Whether or not a given module has the AshTypescript.ControllerResource extension"
  @spec controller_resource?(module) :: boolean
  def controller_resource?(module) when is_atom(module) do
    controller_module_name!(module)
    true
  rescue
    _ -> false
  end
end
