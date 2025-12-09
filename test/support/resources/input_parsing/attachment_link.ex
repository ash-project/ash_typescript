# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.InputParsing.AttachmentLink do
  @moduledoc """
  Embedded resource for array of unions testing - link attachment type.

  Tests array of unions with embedded resource members having field_names.
  """
  use Ash.Resource,
    data_layer: :embedded,
    extensions: [AshTypescript.Resource]

  typescript do
    type_name "InputParsingAttachmentLink"
    field_names is_external_1?: "isExternal1", click_count_1: "clickCount1"
  end

  attributes do
    attribute :attachment_type, :string do
      allow_nil? false
      default "link"
      public? true
    end

    attribute :url, :string do
      allow_nil? false
      public? true
    end

    attribute :title, :string do
      allow_nil? true
      public? true
    end

    attribute :is_external_1?, :boolean do
      default true
      public? true
    end

    attribute :click_count_1, :integer do
      default 0
      public? true
    end
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end
end
