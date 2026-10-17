# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.RouteArgument do
  @moduledoc """
  One argument of a typed controller route as stored in the manifest.
  `client_name` is the output-formatted argument name and `type` is the
  decorated `%Ash.Info.Manifest.Type{}`.
  """

  @type t :: %__MODULE__{
          name: atom(),
          client_name: String.t() | nil,
          type: Ash.Info.Manifest.Type.t(),
          allow_nil?: boolean(),
          has_default?: boolean(),
          description: String.t() | nil
        }

  defstruct [:name, :client_name, :type, :description, allow_nil?: true, has_default?: false]
end
