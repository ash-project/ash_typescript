# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.InputParsing.DeepNestedSettings do
  @moduledoc """
  NewType for testing deeply nested typed maps with field mappings at each level.

  Tests: outer_map (with field_names) → inner_config (NewType with field_names)
  """
  use Ash.Type.NewType,
    subtype_of: :map,
    constraints: [
      fields: [
        display_name: [type: :string, allow_nil?: false],
        is_enabled_1?: [type: :boolean, allow_nil?: true],
        inner_config: [
          type: AshTypescript.Test.InputParsing.InnerConfig,
          allow_nil?: true
        ]
      ]
    ]

  def typescript_field_names do
    [
      is_enabled_1?: "isEnabled1"
    ]
  end
end
