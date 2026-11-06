// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Required Pagination Tests - shouldFail
// Actions whose pagination is required need a `page`

import { listKeysetRequiredTodos, listMixedRequiredTodos } from "../generated";

// @ts-expect-error - page is required
export const testRequiredKeysetWithoutPage = await listKeysetRequiredTodos({
  fields: ["id", "title"],
});

// @ts-expect-error - page is required
export const testRequiredMixedWithoutPage = await listMixedRequiredTodos({
  fields: ["id"],
});

export const testRequiredKeysetWithOffset = await listKeysetRequiredTodos({
  fields: ["id"],
  // @ts-expect-error - offset is type never for keyset-only actions
  page: { offset: 0 },
});

export const testRequiredKeysetResultIsAPage = await listKeysetRequiredTodos({
  fields: ["id"],
  page: { limit: 10 },
});

if (testRequiredKeysetResultIsAPage.success) {
  // @ts-expect-error - a required page is never a plain array
  const first = testRequiredKeysetResultIsAPage.data[0];
}
