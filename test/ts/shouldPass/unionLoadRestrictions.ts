// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Load restrictions through union members, a calculation returning a
// resource and an aggregate holding an embedded resource - shouldPass

import {
  listTodosAllowUnionMember,
  listTodosDenyAggregateEmbedded,
  listTodosDenyBlockMember,
  listTodosDenySelfUser,
  listTodosDenyUnionMember,
} from "../generated";

// denied_loads: [content: [text: [:display_text]]] - other fields of the
// member, other members and scalar members stay selectable
export const denyUnionMemberOthers = await listTodosDenyUnionMember({
  fields: [
    "id",
    {
      content: [
        { text: ["text", "isFormatted"] },
        { checklist: ["title", "totalItems"] },
        "note",
      ],
    },
  ],
});

if (denyUnionMemberOthers.success && denyUnionMemberOthers.data.length > 0) {
  const content = denyUnionMemberOthers.data[0].content;
  if (content && "text" in content && content.text) {
    const text: string = content.text.text;
  }
  if (content && "note" in content) {
    const note: string | undefined = content.note;
  }
}

// allowed_loads: [content: [text: [:display_text]]]
export const allowUnionMember = await listTodosAllowUnionMember({
  fields: [
    "id",
    { content: [{ text: ["text", "displayText"] }, { checklist: ["title"] }, "note"] },
  ],
});

if (allowUnionMember.success && allowUnionMember.data.length > 0) {
  const content = allowUnionMember.data[0].content;
  if (content && "text" in content && content.text) {
    const displayText: string | null | undefined = content.text.displayText;
  }
}

// denied_loads: [blocks: [text: [:display_text]]] - an array of unions
export const denyBlockMemberOthers = await listTodosDenyBlockMember({
  fields: ["id", { blocks: [{ text: ["text", "wordCount"] }, "note"] }],
});

// denied_loads: [self: [:user]] - the calculation keeps its arguments
export const denySelfUserWithArgs = await listTodosDenySelfUser({
  fields: ["id", { self: { args: { prefix: "x" }, fields: ["id", "title"] } }],
});

if (denySelfUserWithArgs.success && denySelfUserWithArgs.data.length > 0) {
  const self = denySelfUserWithArgs.data[0].self;
  if (self) {
    const title: string = self.title;
  }
}

// denied_loads: [first_comment_metadata: [:display_category]]
export const denyAggregateEmbedded = await listTodosDenyAggregateEmbedded({
  fields: ["id", { firstCommentMetadata: ["category"] }],
});

if (denyAggregateEmbedded.success && denyAggregateEmbedded.data.length > 0) {
  const metadata = denyAggregateEmbedded.data[0].firstCommentMetadata;
  if (metadata) {
    const category: string = metadata.category;
  }
}
