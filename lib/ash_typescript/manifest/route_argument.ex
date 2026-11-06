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
          has_default?: boolean()
        }

  defstruct [:name, :client_name, :type, allow_nil?: true, has_default?: false]

  @doc """
  Whether a request must send the argument: it is not nilable and has no
  `default`. An omitted argument with a default gets the default, whatever
  `allow_nil?`, like a create/update action argument; a sent `null` (or a value
  that casts to `nil`) stays `nil`. Codegen (TS optionality) and the
  request handler both read requiredness here; `allow_nil?` alone only says
  whether `null` is a valid value.
  """
  @spec required?(t()) :: boolean()
  def required?(%__MODULE__{allow_nil?: allow_nil?, has_default?: has_default?}),
    do: not allow_nil? and not has_default?
end
