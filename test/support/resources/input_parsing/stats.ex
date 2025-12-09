# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.InputParsing.Stats do
  @moduledoc """
  NewType with typescript_field_names callback for testing input parsing.

  Maps fields with problematic Elixir names to TypeScript-safe names:
  - total_count_1 → "totalCount1"
  - is_complete? → "isComplete"
  """
  use Ash.Type.NewType,
    subtype_of: :map,
    constraints: [
      fields: [
        total_count_1: [type: :integer, allow_nil?: false],
        is_complete?: [type: :boolean, allow_nil?: true],
        last_updated_at: [type: :utc_datetime, allow_nil?: true]
      ]
    ]

  # String values are the exact TypeScript names (no additional formatting)
  def typescript_field_names do
    [
      total_count_1: "totalCount1",
      is_complete?: "isComplete"
    ]
  end
end
