# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# Publication fixtures for the manifest publication tests. They are listed in
# no manifest module option, so the generated snapshots are unaffected; tests
# reach them through inline manifests. Publications that the manifest rejects
# (resources, unions, no `returns`, ...) live in
# test/ash_typescript/manifest/plain_data_test.exs.

defmodule AshTypescript.Test.PublicationFixtures.Feed do
  @moduledoc false
  use Ash.Resource, domain: nil, notifiers: [Ash.Notifier.PubSub]

  pub_sub do
    module AshTypescript.Test.TestEndpoint
    prefix "feed"

    publish :create, [:id],
      event: "item_pushed",
      public?: true,
      returns: :map,
      constraints: [fields: [id: [type: :uuid, allow_nil?: false]]],
      transform: fn notification -> %{id: notification.data.id} end

    publish :update, [:id],
      event: "count_pushed",
      public?: true,
      returns: :keyword,
      constraints: [fields: [count: [type: :integer, allow_nil?: false]]],
      transform: fn _ -> [count: 1] end
  end

  attributes do
    uuid_primary_key :id
  end

  actions do
    defaults [:read, :create, :update, :destroy]
  end
end

defmodule AshTypescript.Test.PublicationFixtures.FeedChannel do
  @moduledoc false
  use Phoenix.Channel
  use AshTypescript.TypedChannel

  typed_channel do
    topic "feed:*"

    resource AshTypescript.Test.PublicationFixtures.Feed do
      publish :item_pushed
      publish :count_pushed
    end
  end

  def join(_topic, _payload, socket), do: {:ok, socket}
end
