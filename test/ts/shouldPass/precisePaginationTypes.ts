// Precise Pagination Type Tests - shouldPass
// Tests that pagination result types are inferred correctly based on what params are used

import { listRecentTodos, listTodos } from "../generated";

// Test 1: Offset pagination → result should be precisely the offset type
export const testOffsetPagination = await listTodos({
  input: {},
  fields: ["id", "title"],
  page: { offset: 0, limit: 10 },
});

if (testOffsetPagination.success) {
  // Should have offset pagination fields
  const hasMore: boolean = testOffsetPagination.data.hasMore;
  const offset: number = testOffsetPagination.data.offset;
  const limit: number = testOffsetPagination.data.limit;
  const results: Array<any> = testOffsetPagination.data.results;
  const type: "offset" = testOffsetPagination.data.type;

  // Should NOT have keyset fields (this would fail if type was union)
  // @ts-expect-error - offset pagination should not have 'after' field
  const after = testOffsetPagination.data.after;

  // @ts-expect-error - offset pagination should not have 'before' field
  const before = testOffsetPagination.data.before;

  // @ts-expect-error - offset pagination should not have 'previousPage' field
  const previousPage = testOffsetPagination.data.previousPage;
}

// Test 2: Keyset pagination with 'after' → result should be precisely the keyset type
export const testKeysetAfterPagination = await listTodos({
  input: {},
  fields: ["id", "title"],
  page: { after: "cursor123", limit: 10 },
});

if (testKeysetAfterPagination.success) {
  // Should have keyset pagination fields
  const hasMore: boolean = testKeysetAfterPagination.data.hasMore;
  const after: string | null = testKeysetAfterPagination.data.after;
  const before: string | null = testKeysetAfterPagination.data.before;
  const limit: number = testKeysetAfterPagination.data.limit;
  const previousPage: string = testKeysetAfterPagination.data.previousPage;
  const nextPage: string = testKeysetAfterPagination.data.nextPage;
  const results: Array<any> = testKeysetAfterPagination.data.results;
  const type: "keyset" = testKeysetAfterPagination.data.type;

  // Should NOT have offset field (this would fail if type was union)
  // @ts-expect-error - keyset pagination should not have 'offset' field
  const offset = testKeysetAfterPagination.data.offset;
}

// Test 3: Keyset pagination with 'before' → result should be precisely the keyset type
export const testKeysetBeforePagination = await listTodos({
  input: {},
  fields: ["id", "title"],
  page: { before: "cursor456", limit: 10 },
});

if (testKeysetBeforePagination.success) {
  // Should have keyset pagination fields
  const hasMore: boolean = testKeysetBeforePagination.data.hasMore;
  const after: string | null = testKeysetBeforePagination.data.after;
  const before: string | null = testKeysetBeforePagination.data.before;
  const limit: number = testKeysetBeforePagination.data.limit;
  const previousPage: string = testKeysetBeforePagination.data.previousPage;
  const nextPage: string = testKeysetBeforePagination.data.nextPage;
  const results: Array<any> = testKeysetBeforePagination.data.results;
  const type: "keyset" = testKeysetBeforePagination.data.type;

  // Should NOT have offset field
  // @ts-expect-error - keyset pagination should not have 'offset' field
  const offset = testKeysetBeforePagination.data.offset;
}

// Test 4: No pagination → result should be array
export const testNoPagination = await listTodos({
  input: {},
  fields: ["id", "title"],
});

if (testNoPagination.success) {
  // Should be an array, not paginated structure
  const todos: Array<any> = testNoPagination.data;
  const firstTodo = todos[0];
  const todoId: string = firstTodo.id;

  // Should NOT have pagination fields
  // @ts-expect-error - non-paginated should not have 'hasMore'
  const hasMore = testNoPagination.data.hasMore;
}

// Test 5: Empty page object → result should be array
export const testEmptyPage = await listTodos({
  input: {},
  fields: ["id", "title"],
  page: {},
});

if (testEmptyPage.success) {
  // Should be an array, not paginated structure
  const todos: Array<any> = testEmptyPage.data;
  const firstTodo = todos[0];
  const todoId: string = firstTodo.id;

  // Should NOT have pagination fields
  // @ts-expect-error - non-paginated should not have 'hasMore'
  const hasMore = testEmptyPage.data.hasMore;
}

// Test 6: Offset pagination with count
export const testOffsetWithCount = await listTodos({
  input: {},
  fields: ["id", "title"],
  page: { offset: 0, limit: 10, count: true },
});

if (testOffsetWithCount.success) {
  const hasMore: boolean = testOffsetWithCount.data.hasMore;
  const offset: number = testOffsetWithCount.data.offset;
  const count: number | null | undefined = testOffsetWithCount.data.count;
  const type: "offset" = testOffsetWithCount.data.type;

  // Should NOT have keyset fields
  // @ts-expect-error - offset pagination should not have 'after'
  const after = testOffsetWithCount.data.after;
}

// Test 7: Nested fields with pagination
export const testNestedWithPagination = await listTodos({
  input: {},
  fields: [
    "id",
    "title",
    {
      user: ["id", "name"],
      comments: ["id", "content"],
    },
  ],
  page: { offset: 0, limit: 5 },
});

if (testNestedWithPagination.success) {
  const hasMore: boolean = testNestedWithPagination.data.hasMore;
  const results: Array<any> = testNestedWithPagination.data.results;
  const type: "offset" = testNestedWithPagination.data.type;

  for (const todo of results) {
    const userName: string = todo.user.name;
    for (const comment of todo.comments) {
      const commentContent: string = comment.content;
    }
  }

  // Should NOT have keyset fields
  // @ts-expect-error - offset pagination should not have 'after'
  const after = testNestedWithPagination.data.after;
}

console.log("Precise pagination type tests should compile successfully!");
