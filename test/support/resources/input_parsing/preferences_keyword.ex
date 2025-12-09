# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.InputParsing.PreferencesKeyword do
  @moduledoc """
  NewType keyword with typescript_field_names callback for testing input parsing.

  Tests keyword type with problematic field names:
  - theme_1 → "theme1"
  - is_dark_mode? → "isDarkMode"
  """
  use Ash.Type.NewType,
    subtype_of: :keyword,
    constraints: [
      fields: [
        theme_1: [type: :string, allow_nil?: false],
        font_size: [type: :integer, allow_nil?: true],
        is_dark_mode?: [type: :boolean, allow_nil?: true]
      ]
    ]

  def typescript_field_names do
    [
      theme_1: "theme1",
      is_dark_mode?: "isDarkMode"
    ]
  end
end
