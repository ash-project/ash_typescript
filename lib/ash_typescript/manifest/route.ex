# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.Route do
  @moduledoc """
  A typed controller route as stored under `manifest.custom.ash_typescript.routes`,
  keyed by `{source_module, name}`. `controller_module` is the generated
  Phoenix controller (`typed_controller_module_name!/1`), which codegen
  uses to join router entries. `client_input_names` resolves query and
  body keys, and `path_input_names` resolves router path segment names.
  """

  alias AshTypescript.Manifest.RouteArgument

  @type t :: %__MODULE__{
          source_module: module(),
          controller_module: module(),
          name: atom(),
          inputs: [RouteArgument.t()],
          client_input_names: %{String.t() => atom()},
          path_input_names: %{String.t() => atom()},
          returns: Ash.Info.Manifest.Type.t() | nil
        }

  defstruct [
    :source_module,
    :controller_module,
    :name,
    :returns,
    inputs: [],
    client_input_names: %{},
    path_input_names: %{}
  ]
end
