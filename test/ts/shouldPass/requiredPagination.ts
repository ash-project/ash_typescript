// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Required Pagination Tests - shouldPass
// Actions whose pagination is required always return a page, never a plain array

import { listKeysetRequiredTodos, listMixedRequiredTodos } from "../generated";

// Keyset-only, required: the result is always a keyset page
export const testRequiredKeyset = await listKeysetRequiredTodos({
  fields: ["id", "title"],
  page: { after: "cursor123", limit: 10 },
});

if (testRequiredKeyset.success) {
  const hasMore: boolean = testRequiredKeyset.data.hasMore;
  const nextPage: string | null = testRequiredKeyset.data.nextPage;
  const previousPage: string | null = testRequiredKeyset.data.previousPage;
  const type: "keyset" = testRequiredKeyset.data.type;
  const title: string = testRequiredKeyset.data.results[0].title;
}

// Offset and keyset, required: either page shape, told apart by `type`
export const testRequiredMixed = await listMixedRequiredTodos({
  fields: ["id"],
  page: { offset: 20, limit: 10 },
});

if (testRequiredMixed.success) {
  const hasMore: boolean = testRequiredMixed.data.hasMore;

  if (testRequiredMixed.data.type === "offset") {
    const offset: number = testRequiredMixed.data.offset;
  } else {
    const nextPage: string | null = testRequiredMixed.data.nextPage;
  }
}

export const testRequiredMixedKeyset = await listMixedRequiredTodos({
  fields: ["id"],
  page: { before: "cursor456" },
});
