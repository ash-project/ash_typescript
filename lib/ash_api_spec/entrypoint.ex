# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshApiSpec.Entrypoint do
  @moduledoc """
  Represents an action entrypoint in the API specification.

  Each entrypoint pairs a resource module with an action definition,
  representing an operation that clients can invoke.
  """

  @type t :: %__MODULE__{
          resource: atom(),
          action: AshApiSpec.Action.t()
        }

  defstruct [:resource, :action]
end
