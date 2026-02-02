# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.InputParsing.DataContentMap do
  @moduledoc """
  NewType for the 'data' union member with typescript_field_names callback.

  Maps is_cached? to isCached to satisfy verifier requirements.
  """
  use Ash.Type.NewType,
    subtype_of: :map,
    constraints: [
      fields: [
        item_count: [type: :integer, allow_nil?: false],
        is_cached?: [type: :boolean, allow_nil?: true]
      ]
    ]

  # String values are the exact TypeScript names (no additional formatting)
  def typescript_field_names do
    [
      is_cached?: "isCached"
    ]
  end
end
