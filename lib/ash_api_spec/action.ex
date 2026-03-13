# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshApiSpec.Action do
  @moduledoc """
  Represents a resource action in the API specification.
  """

  @type action_type :: :read | :create | :update | :destroy | :action

  @type t :: %__MODULE__{
          name: atom(),
          type: action_type(),
          description: String.t() | nil,
          primary?: boolean(),
          get?: boolean(),
          arguments: [AshApiSpec.Argument.t()],
          accept: [atom()] | nil,
          require_attributes: [atom()] | nil,
          allow_nil_input: [atom()] | nil,
          metadata: [AshApiSpec.Metadata.t()],
          returns: AshApiSpec.Type.t() | nil,
          pagination: AshApiSpec.Pagination.t() | nil
        }

  defstruct [
    :name,
    :type,
    :description,
    :primary?,
    :get?,
    :arguments,
    :accept,
    :require_attributes,
    :allow_nil_input,
    :metadata,
    :returns,
    :pagination
  ]
end
