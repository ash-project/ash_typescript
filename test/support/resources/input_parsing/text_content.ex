# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.InputParsing.TextContent do
  @moduledoc """
  Embedded resource for union type member testing in input parsing.

  Used as a tagged union member to verify that union type inputs
  correctly apply field name mappings.
  """
  use Ash.Resource,
    data_layer: :embedded,
    extensions: [AshTypescript.Resource]

  typescript do
    type_name "InputParsingTextContent"
    # String values are the exact TypeScript names (no additional formatting)
    field_names word_count_1: "wordCount1", is_formatted?: "isFormatted"
  end

  attributes do
    attribute :content_type, :string do
      allow_nil? false
      public? true
    end

    attribute :body, :string do
      allow_nil? false
      public? true
    end

    attribute :word_count_1, :integer do
      default 0
      public? true
    end

    attribute :is_formatted?, :boolean do
      default false
      public? true
    end
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end
end
