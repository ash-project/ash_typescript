# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.InputParsing.Options do
  @moduledoc """
  NewType for testing input parsing with action arguments.

  Tests typescript_field_names callback with argument types.
  """
  use Ash.Type.NewType,
    subtype_of: :map,
    constraints: [
      fields: [
        cache_enabled_1?: [type: :boolean, allow_nil?: true],
        retry_limit: [type: :integer, allow_nil?: true]
      ]
    ]

  # String values are the exact TypeScript names (no additional formatting)
  def typescript_field_names do
    [
      cache_enabled_1?: "cacheEnabled1"
    ]
  end
end
