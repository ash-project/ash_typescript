# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.CustomMetadata do
  @moduledoc """
  A custom map type with typescript_field_names callback for testing.
  """
  use Ash.Type.NewType,
    subtype_of: :map,
    constraints: [
      fields: [
        field_1: [type: :string, allow_nil?: false],
        is_active?: [type: :boolean, allow_nil?: false],
        line_2: [type: :string, allow_nil?: true]
      ]
    ]

  def typescript_field_names do
    [
      field_1: "field1",
      is_active?: "isActive",
      line_2: "line2"
    ]
  end
end
