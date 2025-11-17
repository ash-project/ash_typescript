# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.Article do
  @moduledoc """
  Test resource representing article content with details.
  """
  use Ash.Resource,
    domain: AshTypescript.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshTypescript.Resource]

  typescript do
    type_name "Article"
  end

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id

    attribute :hero_image_url, :string do
      allow_nil? false
      public? true
    end

    attribute :hero_image_alt, :string do
      allow_nil? false
      public? true
    end

    attribute :summary, :string do
      allow_nil? false
      public? true
    end

    attribute :body, :string do
      allow_nil? false
      public? true
    end

    create_timestamp :created_at do
      public? true
    end

    update_timestamp :updated_at do
      public? true
    end
  end

  relationships do
    belongs_to :content, AshTypescript.Test.Content do
      allow_nil? false
      attribute_writable? true
      public? true
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :content_id,
        :hero_image_url,
        :hero_image_alt,
        :summary,
        :body
      ]
    end

    update :update do
      primary? true

      accept [
        :hero_image_url,
        :hero_image_alt,
        :summary,
        :body
      ]
    end
  end
end
