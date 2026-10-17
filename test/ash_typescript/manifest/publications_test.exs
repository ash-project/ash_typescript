# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.PublicationsTest do
  use ExUnit.Case, async: true

  alias AshTypescript.Manifest.{Custom, Publication}
  alias AshTypescript.Test.InlineManifest
  alias AshTypescript.Test.PublicationFixtures.{Exposed, Feed, FeedChannel, Plain}

  @moduletag :ash_typescript

  setup_all do
    %{manifest: InlineManifest.build!(typed_controllers: [], typed_channels: [FeedChannel])}
  end

  test "configured channel events are stored (default manifest)" do
    assert %Publication{
             channel_module: AshTypescript.Test.OrgChannel,
             event: "item_created",
             returns: %Ash.Info.Manifest.Type{}
           } =
             Custom.publication(
               nil,
               AshTypescript.Test.OrgChannel,
               AshTypescript.Test.ChannelItem,
               "item_created"
             )
  end

  test "a declared event without returns is stored with returns: nil", %{manifest: m} do
    assert %Publication{channel_module: FeedChannel, event: "untyped_pushed", returns: nil} =
             Custom.publication(m, FeedChannel, Feed, "untyped_pushed")

    assert %Publication{returns: %Ash.Info.Manifest.Type{}} =
             Custom.publication(m, FeedChannel, Feed, "exposed_pushed")
  end

  test "undeclared publications are not stored", %{manifest: m} do
    refute Enum.any?(Custom.publications(m), &(&1.resource == Feed and &1.event == "create"))
    assert length(Custom.publications(m)) == 3
  end

  test "a domain resource referenced only by a publication is in manifest.resources", %{
    manifest: m
  } do
    lookup = AshRpc.Manifest.resource_lookup(m)
    exposed = Map.fetch!(lookup, Exposed)
    plain = Map.fetch!(lookup, Plain)

    assert AshRpc.Manifest.Custom.exposed?(exposed)
    assert AshRpc.Manifest.Custom.client_field_names(exposed)["isHot"] == :is_hot?
    refute AshRpc.Manifest.Custom.exposed?(plain)
  end

  test "publications/1 order is deterministic", %{manifest: m} do
    pubs = Custom.publications(m)
    assert pubs == Enum.sort_by(pubs, &{&1.channel_module, &1.resource, &1.event})
  end

  test "the same publication declared by two channels is stored once per channel" do
    channels = [AshTypescript.Test.OrgChannel, AshTypescript.Test.TypedChannel.StaticTopicChannel]
    m = InlineManifest.build!(typed_controllers: [], typed_channels: channels)

    for channel <- channels do
      assert %Publication{channel_module: ^channel} =
               Custom.publication(m, channel, AshTypescript.Test.ChannelItem, "item_created")
    end
  end
end
