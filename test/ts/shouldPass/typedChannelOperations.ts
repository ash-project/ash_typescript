// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Typed Channel Operations Tests - shouldPass
// Tests for typed event subscription functions generated from AshTypescript.TypedChannel

import {
  createOrgChannel,
  onOrgChannelMessage,
  onOrgChannelMessages,
  unsubscribeOrgChannel,
  createContentFeedChannel,
  onContentFeedChannelMessage,
  onContentFeedChannelMessages,
  unsubscribeContentFeedChannel,
  createModerationChannel,
  onModerationChannelMessages,
  unsubscribeModerationChannel,
  createFullActivityChannel,
  onFullActivityChannelMessage,
  onFullActivityChannelMessages,
  unsubscribeFullActivityChannel,
} from "../generated_typed_channels";

import type {
  OrgChannel,
  OrgChannelEvents,
  OrgChannelRefs,
  ContentFeedChannel,
  ContentFeedChannelEvents,
  FullActivityChannel,
  FullActivityChannelEvents,
  ModerationChannel,
  ItemCreatedPayload,
  ItemUpdatedPayload,
  ItemDeletedPayload,
  ArticlePublishedPayload,
  ArticleUpdatedPayload,
  ReviewSubmittedPayload,
  AlertSentPayload,
  AlertClearedPayload,
  ArticleArchivedPayload,
  ReviewApprovedPayload,
} from "../ash_types";

// Mock socket
declare const mockSocket: { channel(topic: string, params?: object): unknown };

// --- OrgChannel (wildcard topic "org:*") ---

// Test 1: Create channel with suffix (wildcard topic)
const orgChannel: OrgChannel = createOrgChannel(mockSocket, "org-123");

// Test 2: Single-event subscription with typed payload
const itemCreatedRef: number = onOrgChannelMessage(
  orgChannel,
  "item_created",
  (payload) => {
    const id: string = payload.id;
    const name: string | null = payload.name;
  }
);

// Test 3: Single-event subscription - numeric payload
const itemUpdatedRef: number = onOrgChannelMessage(
  orgChannel,
  "item_updated",
  (payload) => {
    const value: number = payload;
  }
);

// Test 4: Single-event subscription - string payload
onOrgChannelMessage(orgChannel, "item_deleted", (payload) => {
  const value: string = payload;
});

// Test 5: Multi-event subscription
const orgRefs: OrgChannelRefs = onOrgChannelMessages(orgChannel, {
  item_created: (payload) => {
    const id: string = payload.id;
    const name: string | null = payload.name;
  },
  item_updated: (payload) => {
    const count: number = payload;
  },
  item_deleted: (payload) => {
    const value: string = payload;
  },
});

// Test 6: Partial multi-event subscription (all handlers optional)
const partialOrgRefs: OrgChannelRefs = onOrgChannelMessages(orgChannel, {
  item_created: (payload) => console.log(payload.id),
});

// Test 7: Unsubscribe
unsubscribeOrgChannel(orgChannel, orgRefs);

// --- ContentFeedChannel (wildcard topic "content_feed:*") ---

// Test 8: Create content feed channel
const feedChannel: ContentFeedChannel = createContentFeedChannel(
  mockSocket,
  "feed-abc"
);

// Test 9: Typed map payload
onContentFeedChannelMessage(
  feedChannel,
  "article_published",
  (payload) => {
    const id: string = payload.id;
    const title: string | null = payload.title;
  }
);

// Test 10: String payload
onContentFeedChannelMessage(feedChannel, "article_updated", (payload) => {
  const title: string = payload;
});

// Test 11: Number payload
onContentFeedChannelMessage(feedChannel, "review_submitted", (payload) => {
  const rating: number = payload;
});

// Test 12: Multi-event on content feed
const feedRefs = onContentFeedChannelMessages(feedChannel, {
  article_published: (payload) => console.log(payload.title),
  article_updated: (payload) => console.log(payload.toUpperCase()),
  review_submitted: (payload) => console.log(payload.toFixed(2)),
});

unsubscribeContentFeedChannel(feedChannel, feedRefs);

// --- ModerationChannel ---

// Test 13: Moderation channel with typed map payload (AlertSentPayload)
const modChannel: ModerationChannel = createModerationChannel(
  mockSocket,
  "mod-zone"
);

const modRefs = onModerationChannelMessages(modChannel, {
  alert_sent: (payload) => {
    const id: string = payload.id;
    const message: string | null = payload.message;
    const severity: string | null = payload.severity;
  },
  article_archived: (payload) => {
    const archived: boolean = payload;
  },
  review_approved: (payload) => {
    const approved: boolean = payload;
  },
});

unsubscribeModerationChannel(modChannel, modRefs);

// --- FullActivityChannel (all events from multiple resources) ---

// Test 14: Full activity channel with all event types
const activityChannel: FullActivityChannel = createFullActivityChannel(
  mockSocket,
  "activity-main"
);

const activityRefs = onFullActivityChannelMessages(activityChannel, {
  article_published: (payload) => {
    const id: string = payload.id;
    const title: string | null = payload.title;
  },
  article_updated: (payload) => {
    const s: string = payload;
  },
  article_archived: (payload) => {
    const b: boolean = payload;
  },
  review_submitted: (payload) => {
    const n: number = payload;
  },
  review_approved: (payload) => {
    const b: boolean = payload;
  },
  alert_sent: (payload) => {
    const id: string = payload.id;
    const message: string | null = payload.message;
    const severity: string | null = payload.severity;
  },
  alert_cleared: (payload) => {
    const dt: string = payload;
  },
});

unsubscribeFullActivityChannel(activityChannel, activityRefs);

// Test 15: Single event from full activity channel
const singleRef = onFullActivityChannelMessage(
  activityChannel,
  "alert_sent",
  (payload) => {
    const id: string = payload.id;
  }
);

// Test 16: Payload type aliases are usable standalone
const myPayload: ItemCreatedPayload = { id: "abc" as any, name: "test" };
const myUpdate: ItemUpdatedPayload = 42;
const myDelete: ItemDeletedPayload = "some-id";
const myArticle: ArticlePublishedPayload = { id: "abc" as any, title: "Hi" };
const myArticleUpdate: ArticleUpdatedPayload = "new title";
const myReview: ReviewSubmittedPayload = 5;
const myAlert: AlertSentPayload = {
  id: "abc" as any,
  message: "warning",
  severity: "high",
};
const myCleared: AlertClearedPayload = "2025-01-01T00:00:00Z";
const myArchived: ArticleArchivedPayload = true;
const myApproved: ReviewApprovedPayload = true;

console.log("Typed channel operations tests should compile successfully!");
