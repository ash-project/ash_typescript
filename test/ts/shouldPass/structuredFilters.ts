// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
//
// SPDX-License-Identifier: MIT

// Structured Filter Tests - shouldPass
// Filters on structured fields with their input shape. Also run through the
// RPC pipeline by test/ash_typescript/rpc/ts_runtime_validation_test.exs, so
// every value the types accept, the runtime accepts too.

import { listTodos } from "../generated";

export const unionEq = await listTodos({
  fields: ["id", "title"],
  filter: { content: { eq: { note: "remember" } } },
});

export const unionIn = await listTodos({
  fields: ["id", "title"],
  filter: { content: { in: [{ note: "remember" }, { priorityValue: 8 }] } },
});

export const unionArrayHas = await listTodos({
  fields: ["id", "title"],
  filter: { attachments: { has: { url: "https://a.example" } } },
});

export const mapWithTagUnion = await listTodos({
  fields: ["id", "title"],
  filter: { statusInfo: { eq: { simple: { message: "ok" } } } },
});

export const keywordEq = await listTodos({
  fields: ["id", "title"],
  filter: { options: { eq: { priority: 3, category: "work" } } },
});

export const tupleEq = await listTodos({
  fields: ["id", "title"],
  filter: { coordinates: { eq: { latitude: 1.5, longitude: 2.5 } } },
});

export const embeddedIsNil = await listTodos({
  fields: ["id", "title"],
  filter: { metadata: { isNil: false }, metadataHistory: { isNil: false } },
});

export const resourceCalcIsNil = await listTodos({
  fields: ["id", "title"],
  filter: { creator: { isNil: false } },
});

export const combined = await listTodos({
  fields: ["id", "title"],
  filter: {
    or: [
      { content: { eq: { note: "remember" } } },
      { options: { eq: { priority: 5 } } },
    ],
  },
});
