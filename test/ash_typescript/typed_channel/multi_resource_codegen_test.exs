# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# Inline resources for payload type conflict test.
# Resource A publishes item_created as :map, Resource B publishes item_created as :string.
# They live in separate channels, so the verifier's unique-event-per-channel check passes,
# but generate_all_channel_types/1 should detect the type name collision.

defmodule AshTypescript.Test.TypedChannel.ConflictItemA do
  @moduledoc false
  use Ash.Resource, domain: nil, notifiers: [Ash.Notifier.PubSub]

  pub_sub do
    module AshTypescript.Test.TestEndpoint
    prefix "conflict_a"

    publish :create, [:id],
      event: "item_created",
      public?: true,
      returns: :map,
      constraints: [fields: [id: [type: :uuid, allow_nil?: false]]],
      transform: fn n -> %{id: n.data.id} end
  end

  attributes do
    uuid_primary_key :id
  end

  actions do
    defaults [:create]
  end
end

defmodule AshTypescript.Test.TypedChannel.ConflictItemB do
  @moduledoc false
  use Ash.Resource, domain: nil, notifiers: [Ash.Notifier.PubSub]

  pub_sub do
    module AshTypescript.Test.TestEndpoint
    prefix "conflict_b"

    publish :create, [:id],
      event: "item_created",
      public?: true,
      returns: :string,
      transform: fn n -> n.data.id end
  end

  attributes do
    uuid_primary_key :id
  end

  actions do
    defaults [:create]
  end
end

defmodule AshTypescript.Test.TypedChannel.ConflictChannelA do
  @moduledoc false
  use AshTypescript.TypedChannel

  typed_channel do
    topic "conflict_a:*"

    resource AshTypescript.Test.TypedChannel.ConflictItemA do
      publish(:item_created)
    end
  end
end

defmodule AshTypescript.Test.TypedChannel.ConflictChannelB do
  @moduledoc false
  use AshTypescript.TypedChannel

  typed_channel do
    topic "conflict_b:*"

    resource AshTypescript.Test.TypedChannel.ConflictItemB do
      publish(:item_created)
    end
  end
end

defmodule AshTypescript.TypedChannel.MultiResourceCodegenTest do
  use ExUnit.Case

  alias AshTypescript.TypedChannel.Codegen

  @moduletag :ash_typescript

  # ─────────────────────────────────────────────────────────────────
  # ContentFeedChannel — two resources (Article + Review), three events
  # ─────────────────────────────────────────────────────────────────

  describe "ContentFeedChannel — articles and reviews (types)" do
    setup do
      %{
        content:
          Codegen.generate_channel_types(
            AshTypescript.Test.ContentFeedChannel,
            "content_feed:*"
          )
      }
    end

    test "generates branded channel type", %{content: content} do
      assert content =~ "export type ContentFeedChannel = {"
      assert content =~ ~s[readonly __channelType: "ContentFeedChannel";]
    end

    test "generates map payload type for article_published (:map)", %{content: content} do
      assert content =~ "export type ArticlePublishedPayload = {id: UUID, title: string | null};"
    end

    test "generates string payload type for article_updated (:string)", %{content: content} do
      assert content =~ "export type ArticleUpdatedPayload = string;"
    end

    test "generates number payload type for review_submitted (:integer)", %{content: content} do
      assert content =~ "export type ReviewSubmittedPayload = number;"
    end

    test "generates events map with all three events", %{content: content} do
      assert content =~ "export type ContentFeedChannelEvents = {"
      assert content =~ "article_published: ArticlePublishedPayload;"
      assert content =~ "article_updated: ArticleUpdatedPayload;"
      assert content =~ "review_submitted: ReviewSubmittedPayload;"
    end

    test "does not include events from resources not declared in this channel", %{
      content: content
    } do
      refute content =~ "article_archived"
      refute content =~ "review_approved"
      refute content =~ "alert_sent"
    end

    test "does not include subscription helper functions", %{content: content} do
      refute content =~ "export function onContentFeedChannelMessage"
      refute content =~ "export function createContentFeedChannel"
    end
  end

  describe "ContentFeedChannel — articles and reviews (functions)" do
    setup do
      %{
        content:
          Codegen.generate_channel_functions(
            AshTypescript.Test.ContentFeedChannel,
            "content_feed:*"
          )
      }
    end

    test "generates factory using topic prefix", %{content: content} do
      assert content =~ "export function createContentFeedChannel("
      assert content =~ "socket.channel(`content_feed:${suffix}`) as ContentFeedChannel"
    end

    test "generates correctly named subscription helper using branded type", %{content: content} do
      assert content =~
               "export function onContentFeedChannelMessage<E extends keyof ContentFeedChannelEvents>("

      assert content =~ "channel: ContentFeedChannel,"
    end

    test "subscription helper is generic over the event map", %{content: content} do
      assert content =~ "handler: (payload: ContentFeedChannelEvents[E]) => void"

      assert content =~
               "channel.on(event, (payload: unknown) => handler(payload as ContentFeedChannelEvents[E]))"
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # ModerationChannel — all three resources, one event each
  # ─────────────────────────────────────────────────────────────────

  describe "ModerationChannel — one event from each resource (types)" do
    setup do
      %{
        content:
          Codegen.generate_channel_types(AshTypescript.Test.ModerationChannel, "moderation:*")
      }
    end

    test "generates branded channel type", %{content: content} do
      assert content =~ "export type ModerationChannel = {"
    end

    test "generates boolean payload type for article_archived", %{content: content} do
      assert content =~ "export type ArticleArchivedPayload = boolean;"
    end

    test "generates boolean payload type for review_approved", %{content: content} do
      assert content =~ "export type ReviewApprovedPayload = boolean;"
    end

    test "generates map payload type for alert_sent (:map)", %{content: content} do
      assert content =~
               "export type AlertSentPayload = {id: UUID, message: string | null, severity: string | null};"
    end

    test "generates events map scoped to just these three events", %{content: content} do
      assert content =~ "export type ModerationChannelEvents = {"
      assert content =~ "article_archived: ArticleArchivedPayload;"
      assert content =~ "review_approved: ReviewApprovedPayload;"
      assert content =~ "alert_sent: AlertSentPayload;"
    end

    test "does not include events not declared in this channel", %{content: content} do
      refute content =~ "article_published"
      refute content =~ "article_updated"
      refute content =~ "review_submitted"
      refute content =~ "alert_cleared"
    end

    test "does not include subscription helper functions", %{content: content} do
      refute content =~ "export function onModerationChannelMessage"
    end
  end

  describe "ModerationChannel — one event from each resource (functions)" do
    setup do
      %{
        content:
          Codegen.generate_channel_functions(
            AshTypescript.Test.ModerationChannel,
            "moderation:*"
          )
      }
    end

    test "generates factory using topic prefix", %{content: content} do
      assert content =~ "export function createModerationChannel("
      assert content =~ "socket.channel(`moderation:${suffix}`) as ModerationChannel"
    end

    test "generates correctly named subscription helper", %{content: content} do
      assert content =~
               "export function onModerationChannelMessage<E extends keyof ModerationChannelEvents>("

      assert content =~ "channel: ModerationChannel,"
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # FullActivityChannel — all three resources, all seven events
  # ─────────────────────────────────────────────────────────────────

  describe "FullActivityChannel — all events from all resources (types)" do
    setup do
      %{
        content:
          Codegen.generate_channel_types(AshTypescript.Test.FullActivityChannel, "activity:*")
      }
    end

    test "generates branded channel type", %{content: content} do
      assert content =~ "export type FullActivityChannel = {"
    end

    test "article_published maps :map → object type", %{content: content} do
      assert content =~ "export type ArticlePublishedPayload = {id: UUID, title: string | null};"
    end

    test "article_updated maps :string → string", %{content: content} do
      assert content =~ "export type ArticleUpdatedPayload = string;"
    end

    test "article_archived maps :boolean → boolean", %{content: content} do
      assert content =~ "export type ArticleArchivedPayload = boolean;"
    end

    test "review_submitted maps :integer → number", %{content: content} do
      assert content =~ "export type ReviewSubmittedPayload = number;"
    end

    test "review_approved maps :boolean → boolean", %{content: content} do
      assert content =~ "export type ReviewApprovedPayload = boolean;"
    end

    test "alert_sent maps :map → object type", %{content: content} do
      assert content =~
               "export type AlertSentPayload = {id: UUID, message: string | null, severity: string | null};"
    end

    test "alert_cleared maps :utc_datetime → UtcDateTime", %{content: content} do
      assert content =~ "export type AlertClearedPayload = UtcDateTime;"
    end

    test "generates events map with all seven events", %{content: content} do
      assert content =~ "export type FullActivityChannelEvents = {"
      assert content =~ "article_published: ArticlePublishedPayload;"
      assert content =~ "article_updated: ArticleUpdatedPayload;"
      assert content =~ "article_archived: ArticleArchivedPayload;"
      assert content =~ "review_submitted: ReviewSubmittedPayload;"
      assert content =~ "review_approved: ReviewApprovedPayload;"
      assert content =~ "alert_sent: AlertSentPayload;"
      assert content =~ "alert_cleared: AlertClearedPayload;"
    end

    test "does not include subscription helper functions", %{content: content} do
      refute content =~ "export function onFullActivityChannelMessage"
    end
  end

  describe "FullActivityChannel — all events from all resources (functions)" do
    setup do
      %{
        content:
          Codegen.generate_channel_functions(
            AshTypescript.Test.FullActivityChannel,
            "activity:*"
          )
      }
    end

    test "generates factory using topic prefix", %{content: content} do
      assert content =~ "export function createFullActivityChannel("
      assert content =~ "socket.channel(`activity:${suffix}`) as FullActivityChannel"
    end

    test "generates correctly named subscription helper", %{content: content} do
      assert content =~
               "export function onFullActivityChannelMessage<E extends keyof FullActivityChannelEvents>("

      assert content =~ "channel: FullActivityChannel,"
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Cross-channel isolation — payload type names don't leak
  # ─────────────────────────────────────────────────────────────────

  describe "channel isolation — each channel only contains its declared types" do
    test "ContentFeedChannel has exactly 3 payload types" do
      content =
        Codegen.generate_channel_types(AshTypescript.Test.ContentFeedChannel, "content_feed:*")

      payload_type_count = content |> String.split("export type") |> length() |> Kernel.-(1)
      # 3 payload types + 1 brand type + 1 events map + 1 handlers + 1 refs = 7 export types total
      assert payload_type_count == 7
    end

    test "ModerationChannel has exactly 3 payload types" do
      content =
        Codegen.generate_channel_types(AshTypescript.Test.ModerationChannel, "moderation:*")

      payload_type_count = content |> String.split("export type") |> length() |> Kernel.-(1)
      # 3 payload types + 1 brand type + 1 events map + 1 handlers + 1 refs = 7 export types total
      assert payload_type_count == 7
    end

    test "FullActivityChannel has exactly 7 payload types" do
      content =
        Codegen.generate_channel_types(AshTypescript.Test.FullActivityChannel, "activity:*")

      payload_type_count = content |> String.split("export type") |> length() |> Kernel.-(1)

      # 7 payload types + 1 brand type + 1 events map + 1 handlers + 1 refs = 11 export types total
      assert payload_type_count == 11
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # generate_all_channel_types/1 — batch generation
  # ─────────────────────────────────────────────────────────────────

  describe "generate_all_channel_types/1 with all channels" do
    setup do
      content =
        Codegen.generate_all_channel_types([
          {AshTypescript.Test.ContentFeedChannel, "content_feed:*"},
          {AshTypescript.Test.ModerationChannel, "moderation:*"},
          {AshTypescript.Test.FullActivityChannel, "activity:*"}
        ])

      %{content: content}
    end

    test "includes all three channel comment headers", %{content: content} do
      assert content =~ "// Channel types for AshTypescript.Test.ContentFeedChannel"
      assert content =~ "// Channel types for AshTypescript.Test.ModerationChannel"
      assert content =~ "// Channel types for AshTypescript.Test.FullActivityChannel"
    end

    test "includes branded types for all three channels", %{content: content} do
      assert content =~ "export type ContentFeedChannel = {"
      assert content =~ "export type ModerationChannel = {"
      assert content =~ "export type FullActivityChannel = {"
    end

    test "includes events maps for all three channels", %{content: content} do
      assert content =~ "export type ContentFeedChannelEvents = {"
      assert content =~ "export type ModerationChannelEvents = {"
      assert content =~ "export type FullActivityChannelEvents = {"
    end

    test "includes handlers and refs types for all three channels", %{content: content} do
      assert content =~ "export type ContentFeedChannelHandlers = {"
      assert content =~ "export type ContentFeedChannelRefs = {"
      assert content =~ "export type ModerationChannelHandlers = {"
      assert content =~ "export type ModerationChannelRefs = {"
      assert content =~ "export type FullActivityChannelHandlers = {"
      assert content =~ "export type FullActivityChannelRefs = {"
    end

    test "does not include subscription helpers or factory functions", %{content: content} do
      refute content =~ "onContentFeedChannelMessage"
      refute content =~ "createContentFeedChannel"
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # generate_all_channel_functions/1 — batch function generation
  # ─────────────────────────────────────────────────────────────────

  describe "generate_all_channel_functions/1 with all channels" do
    setup do
      content =
        Codegen.generate_all_channel_functions([
          {AshTypescript.Test.ContentFeedChannel, "content_feed:*"},
          {AshTypescript.Test.ModerationChannel, "moderation:*"},
          {AshTypescript.Test.FullActivityChannel, "activity:*"}
        ])

      %{content: content}
    end

    test "includes factory and subscription helpers for all three channels", %{content: content} do
      assert content =~ "createContentFeedChannel"
      assert content =~ "onContentFeedChannelMessages"
      assert content =~ "unsubscribeContentFeedChannel"
      assert content =~ "createModerationChannel"
      assert content =~ "onModerationChannelMessages"
      assert content =~ "unsubscribeModerationChannel"
      assert content =~ "createFullActivityChannel"
      assert content =~ "onFullActivityChannelMessages"
      assert content =~ "unsubscribeFullActivityChannel"
    end

    test "does not include type declarations", %{content: content} do
      refute content =~ "export type ContentFeedChannelEvents"
      refute content =~ "export type ContentFeedChannel ="
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Orchestrator integration — types in ash_types.ts, functions in channels file
  # ─────────────────────────────────────────────────────────────────

  describe "orchestrator integration" do
    setup do
      {:ok, files} = AshTypescript.Codegen.Orchestrator.generate(:ash_typescript)
      types_file = AshTypescript.types_output_file()
      channels_file = AshTypescript.typed_channels_output_file()

      %{
        types_content: Map.get(files, types_file, ""),
        channels_content: Map.get(files, channels_file, "")
      }
    end

    test "all four branded channel types are in ash_types.ts", %{types_content: types_content} do
      assert types_content =~ "export type OrgChannel = {"
      assert types_content =~ "export type ContentFeedChannel = {"
      assert types_content =~ "export type ModerationChannel = {"
      assert types_content =~ "export type FullActivityChannel = {"
    end

    test "all four channel events maps are in ash_types.ts", %{types_content: types_content} do
      assert types_content =~ "OrgChannelEvents"
      assert types_content =~ "ContentFeedChannelEvents"
      assert types_content =~ "ModerationChannelEvents"
      assert types_content =~ "FullActivityChannelEvents"
    end

    test "all payload type aliases are in ash_types.ts", %{types_content: types_content} do
      assert types_content =~
               "export type ArticlePublishedPayload = {id: UUID, title: string | null};"

      assert types_content =~ "export type ArticleUpdatedPayload = string;"
      assert types_content =~ "export type ArticleArchivedPayload = boolean;"
      assert types_content =~ "export type ReviewSubmittedPayload = number;"
      assert types_content =~ "export type ReviewApprovedPayload = boolean;"

      assert types_content =~
               "export type AlertSentPayload = {id: UUID, message: string | null, severity: string | null};"

      assert types_content =~ "export type AlertClearedPayload = UtcDateTime;"
    end

    test "factories and subscription functions are in typed channels file",
         %{channels_content: channels_content} do
      assert channels_content =~ "createOrgChannel"
      assert channels_content =~ "onOrgChannelMessage"
      assert channels_content =~ "createContentFeedChannel"
      assert channels_content =~ "createModerationChannel"
      assert channels_content =~ "createFullActivityChannel"
    end

    test "typed channels file imports branded types from ash_types.ts",
         %{channels_content: channels_content} do
      assert channels_content =~ "import type {"
      assert channels_content =~ "OrgChannel"
    end

    test "subscription functions are absent from ash_types.ts", %{types_content: types_content} do
      refute types_content =~ "export function createOrgChannel"
      refute types_content =~ "export function onOrgChannelMessage"
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Payload type name conflict detection
  # ─────────────────────────────────────────────────────────────────

  describe "generate_all_channel_types/1 — payload type conflict" do
    test "raises when same event name maps to different TypeScript types across channels" do
      assert_raise RuntimeError, ~r/Payload type name conflict/, fn ->
        Codegen.generate_all_channel_types([
          {AshTypescript.Test.TypedChannel.ConflictChannelA, "conflict_a:*"},
          {AshTypescript.Test.TypedChannel.ConflictChannelB, "conflict_b:*"}
        ])
      end
    end

    test "error message includes conflicting type name and details" do
      error =
        assert_raise RuntimeError, fn ->
          Codegen.generate_all_channel_types([
            {AshTypescript.Test.TypedChannel.ConflictChannelA, "conflict_a:*"},
            {AshTypescript.Test.TypedChannel.ConflictChannelB, "conflict_b:*"}
          ])
        end

      assert error.message =~ "ItemCreatedPayload"
      assert error.message =~ "item_created"
    end

    test "no conflict when same event name maps to identical TypeScript type" do
      # OrgChannel's item_created is :map with {id, name} — using the same channel twice
      # produces identical types, so no conflict.
      content =
        Codegen.generate_all_channel_types([
          {AshTypescript.Test.OrgChannel, "org:*"},
          {AshTypescript.Test.OrgChannel, "org:*"}
        ])

      assert content =~ "ItemCreatedPayload"
    end
  end
end
