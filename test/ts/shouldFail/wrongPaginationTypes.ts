// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Wrong Pagination Types - shouldFail
// Tests that using wrong pagination parameters produces type errors

import { listRecentTodos, searchPaginatedTodos } from "../generated";

// ERROR: listRecentTodos only supports keyset pagination, but offset is being used
export const testKeysetActionWithOffsetPagination = await listRecentTodos({
  fields: ["id", "title"],
  // @ts-expect-error - offset is type never for keyset-only actions
  page: { offset: 0, limit: 10 },
});

// ERROR: listRecentTodos only supports keyset pagination, cannot use count
export const testKeysetActionWithCount = await listRecentTodos({
  fields: ["id", "title"],
  // @ts-expect-error - count is type never for keyset-only actions
  page: { after: "cursor123", limit: 10, count: true },
});

// ERROR: searchPaginatedTodos only supports offset pagination, but keyset params are being used
export const testOffsetActionWithKeysetPagination = await searchPaginatedTodos({
  input: { query: "test" },
  fields: ["id", "title"],
  // @ts-expect-error - after is type never for offset-only actions
  page: { after: "cursor123", limit: 10 },
});

// ERROR: searchPaginatedTodos only supports offset pagination, cannot use before
export const testOffsetActionWithBefore = await searchPaginatedTodos({
  input: { query: "test" },
  fields: ["id", "title"],
  // @ts-expect-error - before is type never for offset-only actions
  page: { before: "cursor456", limit: 10 },
});

console.log("These tests should NOT compile - they demonstrate type safety!");
