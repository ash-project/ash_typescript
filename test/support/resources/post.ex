# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.Post do
  @moduledoc """
  Test resource representing blog posts with comments.
  """
  use Ash.Resource,
    domain: AshTypescript.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshTypescript.Resource]

  typescript do
    type_name "Post"
  end

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, allow_nil?: false, public?: true
    attribute :content, :string, public?: true
    attribute :published, :boolean, default: false, public?: true
    attribute :view_count, :integer, default: 0, public?: true
    attribute :rating, :decimal, public?: true
    attribute :published_at, :utc_datetime, public?: true
    attribute :tags, {:array, :string}, public?: true

    attribute :status, :atom do
      constraints one_of: [:draft, :published, :archived]
      public? true
    end

    attribute :metadata, :map, public?: true

    # Non-nullable union next to relationships — regression shape for issue #83.
    # Hoisting a field selection with `satisfies` widens it to an array-of-union
    # whose object members grow synthetic `?: undefined` siblings; a non-nullable
    # union sibling must not collapse InferResult to `never`.
    attribute :engagement, :union do
      public? true
      allow_nil? false
      default "none"

      constraints types: [
                    metrics: [
                      type: :map,
                      tag: :engagement_type,
                      tag_value: "metrics",
                      constraints: [
                        fields: [
                          views: [type: :integer, allow_nil?: false],
                          shares: [type: :integer]
                        ]
                      ]
                    ],
                    survey: [
                      type: :map,
                      tag: :engagement_type,
                      tag_value: "survey",
                      constraints: [
                        fields: [
                          score: [type: :integer, allow_nil?: false],
                          comment: [type: :string]
                        ]
                      ]
                    ],
                    none: [type: :string]
                  ],
                  storage: :type_and_value
    end

    # Array of untyped maps — regression coverage for the `has?` filter, whose
    # element type (`Record<string, any>`) itself ends in `>`.
    attribute :revisions, {:array, :map}, public?: true
  end

  relationships do
    belongs_to :author, AshTypescript.Test.User, public?: true

    has_many :comments, AshTypescript.Test.PostComment,
      destination_attribute: :post_id,
      public?: true
  end

  actions do
    defaults [:create, :read, :update, :destroy]
  end
end
