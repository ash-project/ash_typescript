# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.RouteSettings do
  @moduledoc """
  A typed map NewType with `typescript_field_names` that is referenced only by
  typed controller routes, so it is not reachable from any RPC action (and is
  therefore absent from the manifest's type lookup).
  """
  use Ash.Type.NewType,
    subtype_of: :map,
    constraints: [
      fields: [
        enabled?: [type: :boolean, allow_nil?: false],
        level_1: [type: :integer]
      ]
    ]

  def typescript_field_names do
    [enabled?: "enabled", level_1: "level1"]
  end
end
