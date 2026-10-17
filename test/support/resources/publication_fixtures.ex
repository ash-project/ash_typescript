# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# Publication fixtures for the manifest publication and access-invariant tests.
# They are listed in no manifest module option, so the generated snapshots are
# unaffected; tests reach them through inline manifests.

defmodule AshTypescript.Test.PublicationFixtures.Exposed do
  @moduledoc false
  use Ash.Resource,
    domain: nil,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshTypescript.Resource]

  typescript do
    type_name "PublicationsTestExposed"
    field_names is_hot?: "isHot"
  end

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :is_hot?, :boolean, public?: true
    attribute :display_name, :string, public?: true
  end

  actions do
    defaults [:read]
  end
end

defmodule AshTypescript.Test.PublicationFixtures.Plain do
  @moduledoc false
  use Ash.Resource, domain: nil, data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :display_name, :string, public?: true
  end

  actions do
    defaults [:read]
  end
end

defmodule AshTypescript.Test.PublicationFixtures.Feed do
  @moduledoc false
  use Ash.Resource, domain: nil, notifiers: [Ash.Notifier.PubSub]

  pub_sub do
    module AshTypescript.Test.TestEndpoint
    prefix "feed"

    publish :create, [:id],
      event: "exposed_pushed",
      public?: true,
      returns: :struct,
      constraints: [instance_of: AshTypescript.Test.PublicationFixtures.Exposed],
      transform: fn _ -> nil end

    publish :update, [:id],
      event: "plain_pushed",
      public?: true,
      returns: :struct,
      constraints: [instance_of: AshTypescript.Test.PublicationFixtures.Plain],
      transform: fn _ -> nil end

    publish :destroy, [:id], event: "untyped_pushed", public?: true
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
      publish :exposed_pushed
      publish :plain_pushed
      publish :untyped_pushed
    end
  end

  def join(_topic, _payload, socket), do: {:ok, socket}
end
