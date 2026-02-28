# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.ChannelItem do
  @moduledoc """
  Test resource for TypedChannel TypeScript codegen testing.

  Declares PubSub publications with `returns` types so that
  AshTypescript can generate typed TypeScript event payloads.
  """
  use Ash.Resource,
    domain: nil,
    notifiers: [Ash.Notifier.PubSub]

  pub_sub do
    module AshTypescript.Test.TestEndpoint
    prefix "items"

    publish :create, [:id],
      event: "item_created",
      public?: true,
      returns: :map,
      constraints: [
        fields: [
          id: [type: :uuid, allow_nil?: false],
          name: [type: :string, allow_nil?: true]
        ]
      ],
      transform: fn notification -> %{id: notification.data.id, name: notification.data.name} end

    publish :update, [:id],
      event: "item_updated",
      public?: true,
      returns: :integer,
      transform: fn _notification -> 1 end

    publish :destroy, [:id],
      event: "item_deleted",
      public?: true
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end

  actions do
    defaults [:read, :create, :update, :destroy]
  end
end
