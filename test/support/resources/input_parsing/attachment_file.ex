# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.InputParsing.AttachmentFile do
  @moduledoc """
  Embedded resource for array of unions testing - file attachment type.

  Tests array of unions with embedded resource members having field_names.
  """
  use Ash.Resource,
    data_layer: :embedded,
    extensions: [AshTypescript.Resource]

  typescript do
    type_name "InputParsingAttachmentFile"
    field_names is_public_1?: "isPublic1", size_bytes_1: "sizeBytes1"
  end

  attributes do
    attribute :attachment_type, :string do
      allow_nil? false
      default "file"
      public? true
    end

    attribute :filename, :string do
      allow_nil? false
      public? true
    end

    attribute :mime_type, :string do
      allow_nil? true
      public? true
    end

    attribute :is_public_1?, :boolean do
      default true
      public? true
    end

    attribute :size_bytes_1, :integer do
      allow_nil? true
      public? true
    end
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end
end
