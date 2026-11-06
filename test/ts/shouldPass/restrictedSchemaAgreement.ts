// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Restricted schemas agree with the runtime - shouldPass
//
// One selection per restricted rpc_action of the test domain that the types
// accept. `restricted_schema_agreement_test.exs` sends each call's `fields`
// through ash_rpc's `Pipeline.parse_request` and expects it accepted, so keep
// every call in the form `export const x = await <function>({ ... });`, with
// JSON-compatible literals.

import {
  listTodosAllowEmbedded,
  listTodosAllowFlatEmbedded,
  listTodosAllowHistory,
  listTodosAllowNested,
  listTodosAllowNestedCalc,
  listTodosAllowOnlyUser,
  listTodosAllowUnionMember,
  listTodosDenyAggregateEmbedded,
  listTodosDenyBareFields,
  listTodosDenyBlockMember,
  listTodosDenyEmbedded,
  listTodosDenyHistoryCalc,
  listTodosDenyMappedCalc,
  listTodosDenyNested,
  listTodosDenyNestedCalc,
  listTodosDenySelfUser,
  listTodosDenyUnionMember,
  listTodosDenyUser,
  listUsersDenyMappedCalc,
} from "../generated";

export const allowEmbedded = await listTodosAllowEmbedded({
  fields: ["id", { metadata: ["category", "displayCategory"] }],
});

export const allowFlatEmbedded = await listTodosAllowFlatEmbedded({
  fields: ["id", { metadata: ["category"] }],
});

export const allowHistory = await listTodosAllowHistory({
  fields: ["id", { metadataHistory: ["category", "displayCategory"] }],
});

// A restricted has_many keeps its nested query options.
export const allowNested = await listTodosAllowNested({
  fields: [
    "id",
    { user: ["id"] },
    {
      comments: {
        page: { limit: 2 },
        filter: { rating: { greaterThan: 2 } },
        sort: "-rating",
        fields: [
          "id",
          { todo: ["id", "title", { content: [{ text: ["text"] }, "note"] }] },
        ],
      },
    },
  ],
});

export const allowNestedCalc = await listTodosAllowNestedCalc({
  fields: ["id", { comments: ["id", "weightedScore"] }],
});

// Attributes under unnamed embedded and union attributes stay selectable.
export const allowOnlyUser = await listTodosAllowOnlyUser({
  fields: [
    "id",
    { user: ["id", "email"] },
    { metadata: ["category"] },
    { content: [{ text: ["text"] }, { checklist: ["title"] }, "note"] },
  ],
});

export const allowUnionMember = await listTodosAllowUnionMember({
  fields: [
    "id",
    { content: [{ text: ["text", "displayText"] }, { checklist: ["title"] }, "note"] },
  ],
});

export const denyAggregateEmbedded = await listTodosDenyAggregateEmbedded({
  fields: ["id", { firstCommentMetadata: ["category"] }],
});

// A bare denied attribute or member keeps its attributes.
export const denyBareFields = await listTodosDenyBareFields({
  fields: [
    "id",
    { metadata: ["category"] },
    { blocks: [{ text: ["text"] }, "note"] },
    { content: [{ text: ["text"] }, "note", { checklist: ["totalItems"] }] },
  ],
});

if (denyBareFields.success && denyBareFields.data.length > 0) {
  const category: string | undefined = denyBareFields.data[0].metadata?.category;
  console.log(category);
}

export const denyBlockMember = await listTodosDenyBlockMember({
  fields: ["id", { blocks: [{ text: ["text", "isFormatted"] }, "note"] }],
});

export const denyEmbedded = await listTodosDenyEmbedded({
  fields: ["id", { metadata: ["category", "isOverdue"] }],
});

export const denyHistoryCalc = await listTodosDenyHistoryCalc({
  fields: ["id", { metadataHistory: ["category", "isOverdue"] }],
});

export const denyMappedCalc = await listTodosDenyMappedCalc({
  fields: ["id", { user: ["id", "email", { comments: ["id"] }] }],
});

// A restricted has_many keeps its nested query options.
export const denyNested = await listTodosDenyNested({
  fields: [
    "id",
    {
      comments: {
        page: { limit: 2 },
        filter: { rating: { greaterThan: 2 } },
        sort: "-rating",
        fields: ["id", "content"],
      },
    },
  ],
});

if (denyNested.success && denyNested.data.length > 0) {
  const comments = denyNested.data[0].comments;
  console.log(comments);
}

export const denyNestedCalc = await listTodosDenyNestedCalc({
  fields: ["id", { comments: ["id", "rating", { user: ["id"] }] }],
});

export const denySelfUser = await listTodosDenySelfUser({
  fields: ["id", { self: { args: { prefix: "x" }, fields: ["id", "title"] } }],
});

export const denyUnionMember = await listTodosDenyUnionMember({
  fields: ["id", { content: [{ text: ["text", "isFormatted"] }, "note"] }],
});

export const denyUser = await listTodosDenyUser({
  fields: ["id", { comments: ["id"] }],
});

export const usersDenyMappedCalc = await listUsersDenyMappedCalc({
  fields: ["id", "name", { todos: ["id"] }],
});
