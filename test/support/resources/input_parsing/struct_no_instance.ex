# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.InputParsing.StructNoInstance do
  @moduledoc """
  A `:struct` NewType without `instance_of`, with typescript_field_names.
  Its overrides live on the NewType module itself (is_done? → isDone, count_1 → countOne).
  """
  use Ash.Type.NewType,
    subtype_of: :struct,
    constraints: [
      fields: [
        is_done?: [type: :boolean, allow_nil?: false],
        count_1: [type: :integer]
      ]
    ]

  def typescript_field_names, do: [is_done?: "isDone", count_1: "countOne"]
end
