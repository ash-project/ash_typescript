# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.PublicationsTest do
  use ExUnit.Case, async: true

  alias AshTypescript.Manifest.{Custom, Publication}
  alias AshTypescript.Test.InlineManifest
  alias AshTypescript.Test.PublicationFixtures.{Feed, FeedChannel}

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

  # A declared event without `returns`, or with a resource payload, is
  # rejected when the manifest compiles: see plain_data_test.exs.
  test "declared events are stored with their returns type", %{manifest: m} do
    assert %Publication{
             channel_module: FeedChannel,
             event: "item_pushed",
             returns: %Ash.Info.Manifest.Type{kind: :map}
           } = Custom.publication(m, FeedChannel, Feed, "item_pushed")

    assert %Publication{returns: %Ash.Info.Manifest.Type{kind: :keyword}} =
             Custom.publication(m, FeedChannel, Feed, "count_pushed")
  end

  test "undeclared publications are not stored", %{manifest: m} do
    refute Enum.any?(Custom.publications(m), &(&1.resource == Feed and &1.event == "create"))
    assert length(Custom.publications(m)) == 2
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
