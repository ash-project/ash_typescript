# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# `AshTypescript.Test.TypedChannel.StaticTopicChannel` (static topic, no wildcard)
# lives in test/support/resources/static_topic_channel.ex.

defmodule AshTypescript.TypedChannel.CodegenTest do
  use ExUnit.Case

  alias AshTypescript.TypedChannel.Codegen

  @moduletag :ash_typescript

  @org_topic "org:*"

  describe "generate_all_channel_types/1 — OrgChannel" do
    setup do
      content = Codegen.generate_all_channel_types([{AshTypescript.Test.OrgChannel, @org_topic}])
      %{content: content}
    end

    test "generates branded channel type", %{content: content} do
      assert content |> String.split("export type OrgChannel = {") |> length() == 2
      assert content =~ ~s[readonly __channelType: "OrgChannel";]
      assert content =~ "on(event: string, callback: (payload: unknown) => void): number;"
      assert content =~ "off(event: string, ref: number): void;"
    end

    test "generates map payload type for item_created (:map)", %{content: content} do
      assert content =~ "export type ItemCreatedPayload = {id: UUID, name: string | null};"
    end

    test "generates map payload type with a number field for item_updated", %{content: content} do
      assert content =~ "export type ItemUpdatedPayload = {count: number};"
    end

    test "generates map payload type with a string field for item_deleted", %{content: content} do
      assert content =~ "export type ItemDeletedPayload = {id: string};"
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

  describe "generate_all_channel_functions/1 — OrgChannel" do
    setup do
      content =
        Codegen.generate_all_channel_functions([{AshTypescript.Test.OrgChannel, @org_topic}])

      %{content: content}
    end

    test "generates factory function using topic prefix", %{content: content} do
      assert content |> String.split("export function createOrgChannel(") |> length() == 2
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

  describe "generate_all_channel_types/1" do
    test "generates types for all given channel entries" do
      content =
        Codegen.generate_all_channel_types([
          {AshTypescript.Test.OrgChannel, "org:*"},
          {AshTypescript.Test.ContentFeedChannel, "content_feed:*"}
        ])

      assert content =~ "export type OrgChannelEvents = {"
      assert content =~ "export type OrgChannel = {"
      assert content =~ "export type ContentFeedChannelEvents = {"
    end

    test "returns empty string for empty list" do
      assert Codegen.generate_all_channel_types([]) == ""
    end
  end

  describe "generate_all_channel_functions/1" do
    test "generates functions for all given channel entries" do
      content =
        Codegen.generate_all_channel_functions([
          {AshTypescript.Test.OrgChannel, "org:*"},
          {AshTypescript.Test.ContentFeedChannel, "content_feed:*"}
        ])

      assert content =~ "export function createOrgChannel("
      assert content =~ "export function onOrgChannelMessage"
      assert content =~ "export function createContentFeedChannel("
    end

    test "returns empty string for empty list" do
      assert Codegen.generate_all_channel_functions([]) == ""
    end
  end

  describe "generate_all_channel_functions/1 — static topic (no wildcard)" do
    setup do
      content =
        Codegen.generate_all_channel_functions([
          {AshTypescript.Test.TypedChannel.StaticTopicChannel, "notifications"}
        ])

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

  describe "orchestrator integration — TrackerChannel" do
    setup do
      {:ok, files} = AshTypescript.Test.CodegenTestHelper.generate_files()
      types_file = AshTypescript.types_output_file()
      types_content = Map.get(files, types_file, "")
      channels_file = AshTypescript.typed_channels_output_file()
      channels_content = Map.get(files, channels_file, "")
      %{types_content: types_content, channels_content: channels_content}
    end

    test "map calc transform payload types wrapping string concat", %{types_content: content} do
      assert content =~ "export type TrackerSummaryPayload = {summary: string};"
      assert content =~ "export type TrackerLabelPayload = {label: string | null};"
      assert content =~ "export type TrackerStatusChangedPayload = {status: string};"
    end

    test "map calc transform payload type with local fields and correct nullability", %{
      types_content: content
    } do
      # %{id: id, name: name, status: status}
      # id is non-null (primary key), name/status are nullable
      assert content =~
               "export type TrackerSnapshotPayload = {id: UUID, name: string | null, status: string | null};"
    end

    test "map calc transform payload type with relationship traversal", %{
      types_content: content
    } do
      # %{id: id, name: name, latest_entry_body: first(entries, :body)}
      # id non-null, name nullable, first() nullable
      assert content =~
               "export type TrackerDetailPayload = {id: UUID, latestEntryBody: string | null, name: string | null};"
    end

    test "integer calc payload type (count aggregate)", %{types_content: content} do
      assert content =~ "export type TrackerEntryCountPayload = {count: number | null};"
    end

    test "boolean expression calc transform payload type", %{types_content: content} do
      assert content =~ "export type TrackerIsActivePayload = {active: boolean | null};"
    end

    test "integer aggregate calc payload type (max)", %{types_content: content} do
      assert content =~ "export type TrackerTopScorePayload = {score: number | null};"
    end

    test "map with nested relationship fields (first on related FK)", %{types_content: content} do
      # id non-null (PK), name nullable, aggregates (first) nullable
      assert content =~
               "export type TrackerDeepDetailPayload = {id: UUID, latestAuthor: UUID | null, latestBody: string | null, latestScore: number | null, name: string | null};"
    end

    test "map mixing aggregates, booleans, and strings with correct nullability", %{
      types_content: content
    } do
      # all fields nullable: attributes nullable, aggregates nullable, boolean expr with nullable operands nullable
      assert content =~
               "export type TrackerReportPayload = {entryCount: number | null, isActive: boolean | null, latestBody: string | null, name: string | null, status: string | null, topScore: number | null};"
    end

    test "no payload types are unknown", %{types_content: content} do
      refute content =~ "Payload = unknown"
    end

    test "events map includes all 10 events", %{types_content: content} do
      assert content =~ "export type TrackerChannelEvents = {"
      assert content =~ "tracker_summary: TrackerSummaryPayload;"
      assert content =~ "tracker_label: TrackerLabelPayload;"
      assert content =~ "tracker_status_changed: TrackerStatusChangedPayload;"
      assert content =~ "tracker_snapshot: TrackerSnapshotPayload;"
      assert content =~ "tracker_detail: TrackerDetailPayload;"
      assert content =~ "tracker_entry_count: TrackerEntryCountPayload;"
      assert content =~ "tracker_is_active: TrackerIsActivePayload;"
      assert content =~ "tracker_top_score: TrackerTopScorePayload;"
      assert content =~ "tracker_deep_detail: TrackerDeepDetailPayload;"
      assert content =~ "tracker_report: TrackerReportPayload;"
    end

    test "tracker subscription functions appear in channels file", %{channels_content: content} do
      assert content =~ "export function createTrackerChannel("
      assert content =~ "export function onTrackerChannelMessage"
      assert content =~ "export function onTrackerChannelMessages"
      assert content =~ "export function unsubscribeTrackerChannel"
    end
  end

  describe "orchestrator integration" do
    setup do
      {:ok, files} = AshTypescript.Test.CodegenTestHelper.generate_files()
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

  describe "channel set and payload types come from the manifest" do
    alias AshTypescript.Codegen.Orchestrator

    test "payload types come from the channel's manifest publication" do
      key = {AshTypescript.Test.OrgChannel, AshTypescript.Test.ChannelItem, "item_created"}

      fake =
        update_in(AshTypescript.manifest().custom.ash_typescript.publications[key], fn pub ->
          %{pub | returns: Ash.Info.Manifest.Generator.TypeResolver.resolve(:boolean, [])}
        end)

      content =
        AshTypescript.with_manifest(fake, fn ->
          Codegen.generate_all_channel_types([{AshTypescript.Test.OrgChannel, "org:*"}])
        end)

      assert content =~ "export type ItemCreatedPayload = boolean;"
    end

    test "channel_entries/0 lists the manifest's channels with their DSL topic" do
      entries = Orchestrator.channel_entries()

      assert {AshTypescript.Test.OrgChannel, "org:*"} in entries
      assert entries == Enum.sort_by(entries, fn {mod, _} -> inspect(mod) end)
    end

    test "the channel set follows with_manifest/2, not config" do
      only_static =
        AshTypescript.Test.InlineManifest.build!(
          typed_controllers: [],
          typed_channels: [AshTypescript.Test.TypedChannel.StaticTopicChannel]
        )

      AshTypescript.with_manifest(only_static, fn ->
        assert Orchestrator.channel_entries() ==
                 [{AshTypescript.Test.TypedChannel.StaticTopicChannel, "notifications"}]
      end)
    end
  end
end
