# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.ContentItem do
  @moduledoc """
  Union type for polymorphic content items.
  """

  use Ash.Type.NewType,
    subtype_of: :union,
    constraints: [
      types: [
        article: [
          type: :struct,
          constraints: [instance_of: AshTypescript.Test.Article]
        ]
      ]
    ]
end
