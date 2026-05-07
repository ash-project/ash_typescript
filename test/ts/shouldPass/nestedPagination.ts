// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Nested relationship pagination - shouldPass
// Surfaces `Ash.Query.page`-on-loads through the field-selection envelope:
//   { comments: { page: { limit, after }, fields: [...] } }
// Compile-time guarantees that the result is a NestedPageResult<...>, not an
// Array<InferResult<...>>, when the relationship's destination read action
// supports pagination (signaled by `__pagination` on the Relationship metadata).

import { listTodos, getTodo } from "../generated";

// Test 1: Plain nested relationship still works (back-compat).
export const todosWithPlainComments = await listTodos({
  input: {},
  fields: ["id", "title", { comments: ["id", "content"] }],
});

if (todosWithPlainComments.success) {
  const first = todosWithPlainComments.data[0];
  // Without `page:`, comments stays an array.
  const comments: Array<any> = first.comments;
}

// Test 2: Nested relationship with offset pagination.
export const todoWithPagedCommentsOffset = await getTodo({
  input: { id: "todo-id" },
  fields: [
    "id",
    "title",
    {
      comments: {
        page: { limit: 10, offset: 0 },
        fields: ["id", "content"],
      },
    },
  ],
});

if (todoWithPagedCommentsOffset.success && todoWithPagedCommentsOffset.data) {
  const data = todoWithPagedCommentsOffset.data;
  // `comments` is no longer an array — it's a paginated result.
  const page = data.comments;

  // Page-shape members are present.
  const limit: number = page.limit;
  const hasMore: boolean = page.hasMore;
  const results = page.results;
  const firstComment = results[0];
  const cid: string = firstComment.id;
  const ccontent: string = firstComment.content;

  // The discriminator narrows the union — checking `type` lets TS infer
  // offset-only fields safely.
  if (page.type === "offset") {
    const offset: number = page.offset;
  }
}

// Test 3: Nested relationship with keyset pagination.
export const todoWithPagedCommentsKeyset = await getTodo({
  input: { id: "todo-id" },
  fields: [
    "id",
    {
      comments: {
        page: { limit: 5, after: "cursor-x" },
        fields: ["id", "content", "rating"],
      },
    },
  ],
});

if (todoWithPagedCommentsKeyset.success && todoWithPagedCommentsKeyset.data) {
  const page = todoWithPagedCommentsKeyset.data.comments;

  if (page.type === "keyset") {
    // Keyset-only fields are reachable.
    const after: string | null = page.after;
    const before: string | null = page.before;
    const next: string = page.nextPage;
    const prev: string = page.previousPage;
  }
}
