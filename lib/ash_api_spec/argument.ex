# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshApiSpec.Argument do
  @moduledoc """
  Represents an action argument or calculation argument in the API specification.
  """

  @type t :: %__MODULE__{
          name: atom(),
          type: AshApiSpec.Type.t(),
          allow_nil?: boolean(),
          has_default?: boolean(),
          description: String.t() | nil,
          sensitive?: boolean()
        }

  defstruct [
    :name,
    :type,
    :allow_nil?,
    :has_default?,
    :description,
    :sensitive?
  ]
end
