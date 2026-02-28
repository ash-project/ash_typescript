# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.ChannelArticle do
  @moduledoc """
  Test resource for TypedChannel multi-resource stress testing.

  Declares three publications covering map, string, and boolean return types.
  """
  use Ash.Resource,
    domain: nil,
    notifiers: [Ash.Notifier.PubSub]

  pub_sub do
    module AshTypescript.Test.TestEndpoint
    prefix "articles"

    publish :create, [:id],
      event: "article_published",
      public?: true,
      returns: :map,
      constraints: [
        fields: [
          id: [type: :uuid, allow_nil?: false],
          title: [type: :string, allow_nil?: true]
        ]
      ],
      transform: fn notification ->
        %{id: notification.data.id, title: notification.data.title}
      end

    publish :update, [:id],
      event: "article_updated",
      public?: true,
      returns: :string,
      transform: fn notification -> notification.data.title end

    publish :destroy, [:id],
      event: "article_archived",
      public?: true,
      returns: :boolean,
      transform: fn _notification -> true end
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    attribute :body, :string, public?: true
  end

  actions do
    defaults [:read, :create, :update, :destroy]
  end
end
