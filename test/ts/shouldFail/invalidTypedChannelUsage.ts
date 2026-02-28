// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Invalid Typed Channel Usage Tests - shouldFail
// Tests for invalid typed channel usage that should fail TypeScript compilation

import {
  createOrgChannel,
  onOrgChannelMessage,
  onOrgChannelMessages,
  unsubscribeOrgChannel,
  createContentFeedChannel,
} from "../generated_typed_channels";

import type {
  OrgChannel,
  ContentFeedChannel,
} from "../ash_types";

// Mock socket
declare const mockSocket: { channel(topic: string, params?: object): unknown };

const orgChannel = createOrgChannel(mockSocket, "org-1");
const feedChannel = createContentFeedChannel(mockSocket, "feed-1");

// Test 1: Invalid event name
onOrgChannelMessage(
  orgChannel,
  // @ts-expect-error - "nonexistent_event" is not a valid OrgChannel event
  "nonexistent_event",
  (payload) => console.log(payload)
);

// Test 2: Wrong channel type passed to function
onOrgChannelMessage(
  // @ts-expect-error - feedChannel is ContentFeedChannel, not OrgChannel
  feedChannel,
  "item_created",
  (payload) => console.log(payload)
);

// Test 3: Wrong payload type in handler - item_created has {id, name}, not number
onOrgChannelMessage(orgChannel, "item_created", (payload) => {
  // @ts-expect-error - payload is {id: UUID, name: string | null}, not number
  const n: number = payload;
});

// Test 4: Accessing non-existent property on typed payload
onOrgChannelMessage(orgChannel, "item_created", (payload) => {
  // @ts-expect-error - "nonExistentProp" does not exist on ItemCreatedPayload
  console.log(payload.nonExistentProp);
});

// Test 5: Wrong payload type for numeric event
onOrgChannelMessage(orgChannel, "item_updated", (payload) => {
  // @ts-expect-error - payload is number, not string
  const s: string = payload;
});

// Test 6: Invalid event in multi-event handler
onOrgChannelMessages(orgChannel, {
  item_created: (payload) => console.log(payload),
  // @ts-expect-error - "fake_event" is not a valid OrgChannel event
  fake_event: (payload: unknown) => console.log(payload),
});

// Test 7: Unsubscribe with wrong channel type
// @ts-expect-error - feedChannel is ContentFeedChannel, not OrgChannel
unsubscribeOrgChannel(feedChannel, {});

// Test 8: String not assignable to branded channel type
// @ts-expect-error - string is not OrgChannel
const badChannel: OrgChannel = "not-a-channel";

console.log("Invalid typed channel usage tests should FAIL compilation!");
