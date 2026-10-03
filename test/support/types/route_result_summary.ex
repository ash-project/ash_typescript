# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.RouteResultSummary do
  @moduledoc """
  A typed map NewType referenced only by a typed controller route's `returns`,
  so it is not reachable from any RPC action.
  """
  use Ash.Type.NewType,
    subtype_of: :map,
    constraints: [
      fields: [
        total_count: [type: :integer, allow_nil?: false],
        status: [type: :atom, allow_nil?: false, constraints: [one_of: [:ok, :pending]]],
        extra: [type: :map]
      ]
    ]
end
