# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.InputParsing.InnerConfig do
  @moduledoc """
  NewType for inner config with typescript_field_names.

  Used to test nested typed maps where both outer and inner have field mappings.
  """
  use Ash.Type.NewType,
    subtype_of: :map,
    constraints: [
      fields: [
        max_retries_1: [type: :integer, allow_nil?: false],
        is_cached?: [type: :boolean, allow_nil?: true],
        timeout_ms: [type: :integer, allow_nil?: true]
      ]
    ]

  def typescript_field_names do
    [
      max_retries_1: "maxRetries1",
      is_cached?: "isCached"
    ]
  end
end
