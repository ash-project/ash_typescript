# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.InputParsing.Profile do
  @moduledoc """
  Embedded resource for testing input parsing with nested resources.

  Contains fields with various naming conventions to test:
  - Standard snake_case fields
  - Fields requiring DSL mapping
  """
  use Ash.Resource,
    data_layer: :embedded,
    extensions: [AshTypescript.Resource]

  typescript do
    type_name "InputParsingProfile"
    # String values are the exact TypeScript names (no additional formatting)
    field_names bio_text_1: "bioText1", is_public?: "isPublic"
  end

  attributes do
    attribute :display_name, :string do
      allow_nil? false
      public? true
    end

    attribute :bio_text_1, :string do
      allow_nil? true
      public? true
    end

    attribute :is_public?, :boolean do
      default true
      public? true
    end

    attribute :follower_count, :integer do
      default 0
      public? true
    end
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end
end
