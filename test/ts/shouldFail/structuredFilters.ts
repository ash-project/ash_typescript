// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
//
// SPDX-License-Identifier: MIT

// Structured Filter Tests - shouldFail
// Filter values the runtime rejects are rejected by the types: a record (an
// embedded resource, or a value reaching a resource) only takes isNil, a
// union leaves out its members that are records, and a structured value has
// no ordering operators.

import { listTodos } from "../generated";

// An embedded resource takes isNil only
export const embeddedEq = await listTodos({
  fields: ["id"],
  // @ts-expect-error - eq is not offered on an embedded resource
  filter: { metadata: { eq: { category: "home" } } },
});

export const embeddedArrayHas = await listTodos({
  fields: ["id"],
  // @ts-expect-error - has is not offered on an array of embedded resources
  filter: { metadataHistory: { has: { category: "home" } } },
});

// A union member that is an embedded resource is left out
export const unionEmbeddedMember = await listTodos({
  fields: ["id"],
  // @ts-expect-error - text is an embedded resource member
  filter: { content: { eq: { text: { text: "hello" } } } },
});

// Structured values have no ordering operators
export const unionOrdering = await listTodos({
  fields: ["id"],
  // @ts-expect-error - lessThan is not offered on a union
  filter: { content: { lessThan: { priorityValue: 9 } } },
});

export const keywordOrdering = await listTodos({
  fields: ["id"],
  // @ts-expect-error - greaterThan is not offered on a keyword
  filter: { options: { greaterThan: { priority: 1 } } },
});

// A calculation returning a resource takes isNil only
export const resourceCalcEq = await listTodos({
  fields: ["id"],
  // @ts-expect-error - eq is not offered on a value reaching a resource
  filter: { creator: { eq: { name: "x" } } },
});

// A union value names exactly one member, by its client name
export const unionInternalName = await listTodos({
  fields: ["id"],
  // @ts-expect-error - priority_value is the internal member name
  filter: { content: { eq: { priority_value: 8 } } },
});
