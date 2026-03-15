# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# Inline resource/channel defined here (not in test/support/) so that the
# intentional missing `returns` triggers IO.warn only during `mix test`, not
# during `mix compile --warnings-as-errors` which would block CI.
defmodule AshTypescript.Test.TypedChannel.NoReturnsItem do
  @moduledoc false
  use Ash.Resource, domain: nil, notifiers: [Ash.Notifier.PubSub]

  pub_sub do
    module AshTypescript.Test.TestEndpoint
    prefix "no_returns_items"

    publish :destroy, [:id],
      event: "thing_removed",
      public?: true
    # intentionally no `returns` — TypeScript payload type should be `unknown`
  end

  attributes do
    uuid_primary_key :id
  end

  actions do
    defaults [:destroy]
  end
end

defmodule AshTypescript.Test.TypedChannel.NoReturnsChannel do
  @moduledoc false
  use AshTypescript.TypedChannel

  typed_channel do
    topic "things:*"

    resource AshTypescript.Test.TypedChannel.NoReturnsItem do
      publish(:thing_removed)
    end
  end
end

# Channel with a static topic (no wildcard) — exercises the no-suffix factory path.
defmodule AshTypescript.Test.TypedChannel.StaticTopicChannel do
  @moduledoc false
  use AshTypescript.TypedChannel

  typed_channel do
    topic "notifications"

    resource AshTypescript.Test.ChannelItem do
      publish(:item_created)
    end
  end
end

defmodule AshTypescript.TypedChannel.CodegenTest do
  use ExUnit.Case

  alias AshTypescript.TypedChannel.Codegen

  @moduletag :ash_typescript

  @org_topic "org:*"

  describe "generate_channel_types/2 — with topic" do
    setup do
      content = Codegen.generate_channel_types(AshTypescript.Test.OrgChannel, @org_topic)
      %{content: content}
    end

    test "generates branded channel type", %{content: content} do
      assert content =~ "export type OrgChannel = {"
      assert content =~ ~s[readonly __channelType: "OrgChannel";]
      assert content =~ "on(event: string, callback: (payload: unknown) => void): number;"
      assert content =~ "off(event: string, ref: number): void;"
    end

    test "generates map payload type for item_created (:map)", %{content: content} do
      assert content =~ "export type ItemCreatedPayload = {id: UUID, name: string | null};"
    end

    test "generates number payload type for item_updated (:integer)", %{content: content} do
      assert content =~ "export type ItemUpdatedPayload = number;"
    end

    test "generates string payload type for item_deleted (:string)", %{content: content} do
      assert content =~ "export type ItemDeletedPayload = string;"
    end

    test "generates channel events map type", %{content: content} do
      assert content =~ "export type OrgChannelEvents = {"
    end

    test "events map includes all declared events", %{content: content} do
      assert content =~ "item_created: ItemCreatedPayload;"
      assert content =~ "item_updated: ItemUpdatedPayload;"
      assert content =~ "item_deleted: ItemDeletedPayload;"
    end

    test "generates handlers mapped type", %{content: content} do
      assert content =~ "export type OrgChannelHandlers = {"
      assert content =~ "[E in keyof OrgChannelEvents]?: (payload: OrgChannelEvents[E]) => void;"
    end

    test "generates refs mapped type", %{content: content} do
      assert content =~ "export type OrgChannelRefs = {"
      assert content =~ "[E in keyof OrgChannelEvents]?: number;"
    end

    test "does not include subscription helper functions", %{content: content} do
      refute content =~ "export function onOrgChannelMessage"
      refute content =~ "export function onOrgChannelMessages"
      refute content =~ "export function unsubscribeOrgChannel"
      refute content =~ "export function createOrgChannel"
    end

    test "includes comment identifying the channel module", %{content: content} do
      assert content =~ "// Channel types for AshTypescript.Test.OrgChannel"
    end
  end

  describe "generate_channel_types/2 — unknown payload type" do
    setup do
      content =
        Codegen.generate_channel_types(
          AshTypescript.Test.TypedChannel.NoReturnsChannel,
          "things:*"
        )

      %{content: content}
    end

    test "generates unknown payload type for event without returns", %{content: content} do
      assert content =~ "export type ThingRemovedPayload = unknown;"
    end
  end

  describe "generate_channel_types/1 — without topic" do
    setup do
      content = Codegen.generate_channel_types(AshTypescript.Test.OrgChannel)
      %{content: content}
    end

    test "does not generate branded channel type", %{content: content} do
      refute content =~ "export type OrgChannel = {"
    end

    test "still generates events map and utility types", %{content: content} do
      assert content =~ "export type OrgChannelEvents = {"
      assert content =~ "export type OrgChannelHandlers = {"
      assert content =~ "export type OrgChannelRefs = {"
    end
  end

  describe "generate_channel_functions/2 — with topic" do
    setup do
      content = Codegen.generate_channel_functions(AshTypescript.Test.OrgChannel, @org_topic)
      %{content: content}
    end

    test "generates factory function using topic prefix", %{content: content} do
      assert content =~ "export function createOrgChannel("
      assert content =~ "suffix: string"
      assert content =~ "socket.channel(`org:${suffix}`) as OrgChannel"
    end

    test "generates typed subscription helper using branded channel type", %{content: content} do
      assert content =~ "export function onOrgChannelMessage<E extends keyof OrgChannelEvents>("
      assert content =~ "channel: OrgChannel,"
    end

    test "generates on-messages function with branded channel type", %{content: content} do
      assert content =~ "export function onOrgChannelMessages("
      assert content =~ "channel: OrgChannel,"
      assert content =~ "handlers: OrgChannelHandlers"
      assert content =~ "): OrgChannelRefs {"
    end

    test "generates unsubscribe function with branded channel type", %{content: content} do
      assert content =~ "export function unsubscribeOrgChannel("
      assert content =~ "channel: OrgChannel,"
      assert content =~ "refs: OrgChannelRefs"
      assert content =~ "channel.off(event, ref);"
    end

    test "does not include type declarations", %{content: content} do
      refute content =~ "export type OrgChannelEvents"
      refute content =~ "export type OrgChannelHandlers"
      refute content =~ "export type OrgChannelRefs"
      refute content =~ "export type OrgChannel ="
      refute content =~ "export type ItemCreatedPayload"
    end
  end

  describe "generate_channel_functions/1 — without topic" do
    setup do
      content = Codegen.generate_channel_functions(AshTypescript.Test.OrgChannel)
      %{content: content}
    end

    test "does not generate factory function", %{content: content} do
      refute content =~ "export function createOrgChannel"
    end

    test "still generates subscription helpers", %{content: content} do
      assert content =~ "export function onOrgChannelMessage"
      assert content =~ "export function onOrgChannelMessages"
      assert content =~ "export function unsubscribeOrgChannel"
    end
  end

  describe "generate_all_channel_types/1" do
    test "generates types for all given channel entries" do
      content =
        Codegen.generate_all_channel_types([{AshTypescript.Test.OrgChannel, "org:*"}])

      assert content =~ "export type OrgChannelEvents = {"
      assert content =~ "export type OrgChannel = {"
    end

    test "returns empty string for empty list" do
      assert Codegen.generate_all_channel_types([]) == ""
    end
  end

  describe "generate_all_channel_functions/1" do
    test "generates functions for all given channel entries" do
      content =
        Codegen.generate_all_channel_functions([{AshTypescript.Test.OrgChannel, "org:*"}])

      assert content =~ "export function createOrgChannel("
      assert content =~ "export function onOrgChannelMessage"
    end

    test "returns empty string for empty list" do
      assert Codegen.generate_all_channel_functions([]) == ""
    end
  end

  describe "generate_channel_functions/2 — static topic (no wildcard)" do
    setup do
      content =
        Codegen.generate_channel_functions(
          AshTypescript.Test.TypedChannel.StaticTopicChannel,
          "notifications"
        )

      %{content: content}
    end

    test "factory takes no suffix parameter", %{content: content} do
      assert content =~ "export function createStaticTopicChannel("
      assert content =~ ~s[socket.channel("notifications") as StaticTopicChannel]
      refute content =~ "suffix"
    end

    test "factory signature has only socket parameter", %{content: content} do
      # Extract factory function — should have socket param but no suffix
      assert content =~
               """
               export function createStaticTopicChannel(
                 socket: { channel(topic: string, params?: object): unknown }
               ): StaticTopicChannel {\
               """
    end
  end

  describe "generate_all_channel_types/1 — payload type deduplication" do
    test "shared payload type appears exactly once in batch output" do
      # ContentFeedChannel and FullActivityChannel both include article_published
      # (from ChannelArticle), producing ArticlePublishedPayload. It should appear only once.
      content =
        Codegen.generate_all_channel_types([
          {AshTypescript.Test.ContentFeedChannel, "content_feed:*"},
          {AshTypescript.Test.FullActivityChannel, "activity:*"}
        ])

      occurrences =
        content
        |> String.split("export type ArticlePublishedPayload")
        |> length()
        |> Kernel.-(1)

      assert occurrences == 1
    end
  end

  describe "orchestrator integration" do
    setup do
      {:ok, files} = AshTypescript.Codegen.Orchestrator.generate(:ash_typescript)
      %{files: files}
    end

    test "channel types appear in types file", %{files: files} do
      types_file = AshTypescript.types_output_file()
      types_content = Map.get(files, types_file, "")

      assert types_content =~ "export type OrgChannelEvents = {"
      assert types_content =~ "export type OrgChannel = {"
      assert types_content =~ "export type ItemCreatedPayload = {id: UUID, name: string | null};"
    end

    test "channel types file does not contain functions", %{files: files} do
      types_file = AshTypescript.types_output_file()
      types_content = Map.get(files, types_file, "")

      refute types_content =~ "export function createOrgChannel"
      refute types_content =~ "export function onOrgChannelMessage"
    end

    test "subscription functions and factory appear in typed channels file", %{files: files} do
      channels_file = AshTypescript.typed_channels_output_file()
      channels_content = Map.get(files, channels_file, "")

      assert channels_content =~ "export function createOrgChannel("
      assert channels_content =~ "export function onOrgChannelMessage"
    end

    test "typed channels file imports branded types from ash_types.ts", %{files: files} do
      channels_file = AshTypescript.typed_channels_output_file()
      channels_content = Map.get(files, channels_file, "")

      assert channels_content =~ "import type {"
      assert channels_content =~ "OrgChannel"
    end
  end
end
