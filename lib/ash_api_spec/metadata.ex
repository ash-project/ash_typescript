# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshApiSpec.Metadata do
  @moduledoc """
  Represents action metadata in the API specification.
  """

  @type t :: %__MODULE__{
          name: atom(),
          type: AshApiSpec.Type.t(),
          allow_nil?: boolean(),
          description: String.t() | nil
        }

  defstruct [
    :name,
    :type,
    :allow_nil?,
    :description
  ]
end
