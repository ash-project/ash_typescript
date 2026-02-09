# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.TypedController.Info do
  @moduledoc """
  Provides introspection functions for AshTypescript.TypedController configuration.
  """
  use Spark.InfoGenerator,
    extension: AshTypescript.TypedController.Dsl,
    sections: [:typed_controller]

  @doc "Whether or not a given module uses the AshTypescript.TypedController DSL"
  @spec typed_controller?(module) :: boolean
  def typed_controller?(module) when is_atom(module) do
    typed_controller_module_name!(module)
    true
  rescue
    _ -> false
  end
end
