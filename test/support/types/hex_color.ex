# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.HexColor do
  @moduledoc """
  A NewType over `:string` with a `match` constraint and its own TypeScript
  mapping, used as a member of typed maps (`AshTypescript.Test.Theme`,
  `AshTypescript.Test.ThemeMap`) to pin that scalar members keep their own
  mapping.
  """
  use Ash.Type.NewType, subtype_of: :string, constraints: [match: ~r/^#[0-9a-fA-F]{6}$/]

  def typescript_type, do: "`#${string}`"
end
