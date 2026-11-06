// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
//
// SPDX-License-Identifier: MIT

// `has` on an array of unions takes a member value the runtime can compare:
// members that are records (embedded resources) are left out.

import { listTodos } from "../generated";

export const recordMember = await listTodos({
  fields: ["id"],
  // @ts-expect-error - text is an embedded resource member of blocks
  filter: { blocks: { has: { text: { text: "hello" } } } },
});

export const recordMemberEq = await listTodos({
  fields: ["id"],
  // @ts-expect-error - eq leaves out the record member too
  filter: { blocks: { eq: [{ text: { text: "hello" } }] } },
});

// The scalar member is offered.
export const scalarMember = await listTodos({
  fields: ["id"],
  filter: { blocks: { has: { note: "hello" } } },
});
