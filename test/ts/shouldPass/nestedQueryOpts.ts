// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Nested Relationship Query Options - shouldPass

import {
  getTodo,
  createTodo,
  listTodosNoFilter,
  listTodosNoSort,
} from "../generated";

// Test 1: back-compat — plain nested arrays still work and infer arrays
export const plainArray = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: ["id", { comments: ["id", "content"] }],
});

if (plainArray.success && plainArray.data) {
  const contents: string[] = plainArray.data.comments.map((c) => c.content);
  console.log(contents);
}

// Test 2: each envelope key alone
export const fieldsOnly = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: ["id", { comments: { fields: ["id"] } }],
});

export const limitOnly = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: ["id", { comments: { limit: 3, fields: ["id"] } }],
});

export const offsetOnly = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: ["id", { comments: { offset: 2, fields: ["id"] } }],
});

export const filterOnly = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: [
    "id",
    { comments: { filter: { rating: { greaterThan: 2 } }, fields: ["id"] } },
  ],
});

export const sortOnly = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: ["id", { comments: { sort: "-rating", fields: ["id"] } }],
});

// Test 2b: bare limit + offset combined (a plain slice, no page)
export const limitAndOffset = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: ["id", { comments: { limit: 3, offset: 2, fields: ["id"] } }],
});

// Test 2c: sort accepts the array form
export const sortArray = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: [
    "id",
    { comments: { sort: ["-rating", "content"], fields: ["id"] } },
  ],
});

// Test 3: combined keys + offset page, type narrowing on the discriminator
export const offsetPaged = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: [
    "id",
    {
      comments: {
        page: { limit: 3, offset: 0, count: true },
        filter: { rating: { greaterThan: 2 } },
        sort: "-rating",
        fields: ["id", "content"],
      },
    },
  ],
});

if (offsetPaged.success && offsetPaged.data) {
  const page = offsetPaged.data.comments;
  const results: Array<{ id: string; content: string }> = page.results;
  const hasMore: boolean = page.hasMore;
  console.log(results, hasMore);

  // Offset page input narrows the mixed relationship to the offset shape.
  const offsetType: "offset" = page.type;
  const offset: number = page.offset;
  console.log(offsetType, offset);
}

// Test 4: keyset page input on a mixed relationship
export const keysetPaged = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: [
    "id",
    { comments: { page: { limit: 3, after: "cursor" }, fields: ["id"] } },
  ],
});

if (keysetPaged.success && keysetPaged.data) {
  const page = keysetPaged.data.comments;
  // mixed pagination: keyset side has nullable string cursors (PR #75 fix)
  const keysetType: "keyset" = page.type;
  const next: string | null = page.nextPage;
  const prev: string | null = page.previousPage;
  console.log(keysetType, next, prev);
}

// Test 5: no page key => plain array result (filter/sort/limit don't change shape)
if (sortOnly.success && sortOnly.data) {
  const ids: string[] = sortOnly.data.comments.map((c) => c.id);
  console.log(ids);
}

// Test 6: envelope at depth >= 2 (comments -> user -> comments)
export const deepEnvelope = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: [
    "id",
    {
      comments: {
        limit: 2,
        fields: [
          "id",
          {
            user: [
              "id",
              { comments: { page: { limit: 1 }, fields: ["id"] } },
            ],
          },
        ],
      },
    },
  ],
});

// Test 7: envelope on a mutation result
export const createdWithEnvelope = await createTodo({
  input: {
    title: "Test",
    userId: "00000000-0000-0000-0000-000000000001",
  },
  fields: ["id", { comments: { limit: 1, fields: ["id"] } }],
});

// Test 8: gates only remove their own key — everything else stays usable.

// 8a: unfilterable relationship still accepts page, sort, limit, and offset
export const unfilterableStillSortsAndPages = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: [
    "id",
    {
      unfilterableComments: {
        page: { limit: 2, offset: 0, count: true },
        sort: "-rating",
        fields: ["id", "content"],
      },
    },
  ],
});

export const unfilterableBareSlice = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: [
    "id",
    { unfilterableComments: { limit: 2, offset: 1, fields: ["id"] } },
  ],
});

// 8b: unsortable relationship still accepts page, filter, limit, and offset
export const unsortableStillFiltersAndPages = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: [
    "id",
    {
      unsortableComments: {
        page: { limit: 2, after: "cursor" },
        filter: { rating: { greaterThan: 2 } },
        fields: ["id"],
      },
    },
  ],
});

export const unsortableBareSlice = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: [
    "id",
    { unsortableComments: { limit: 2, offset: 1, fields: ["id"] } },
  ],
});

// 8c: unpaginated relationship still accepts filter, sort, limit, and offset
export const unpaginatedStillFiltersAndSorts = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: [
    "id",
    {
      unpaginatedComments: {
        filter: { rating: { greaterThan: 2 } },
        sort: "-rating",
        limit: 2,
        offset: 1,
        fields: ["id", "rating"],
      },
    },
  ],
});

// 8c2: offset-only relationship — offset page keys accepted, result is the
// offset shape without needing input-based narrowing
export const offsetOnlyRel = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: [
    "id",
    {
      offsetComments: {
        page: { limit: 2, offset: 0, count: true },
        fields: ["id"],
      },
    },
  ],
});

if (offsetOnlyRel.success && offsetOnlyRel.data) {
  const page = offsetOnlyRel.data.offsetComments;
  const offsetType: "offset" = page.type;
  const offset: number = page.offset;
  console.log(offsetType, offset);
}

// 8c3: keyset-only relationship — keyset page keys accepted, result is the
// keyset shape with nullable cursors
export const keysetOnlyRel = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: [
    "id",
    {
      keysetComments: {
        page: { limit: 2, after: "cursor" },
        fields: ["id"],
      },
    },
  ],
});

if (keysetOnlyRel.success && keysetOnlyRel.data) {
  const page = keysetOnlyRel.data.keysetComments;
  const keysetType: "keyset" = page.type;
  const next: string | null = page.nextPage;
  console.log(keysetType, next);
}

// 8c4: many_to_many relationships take the full envelope like has_many
export const manyToManyEnvelope = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: [
    "id",
    {
      commenters: {
        page: { limit: 2, offset: 0 },
        filter: { name: { eq: "Bob" } },
        sort: "name",
        fields: ["id", "name"],
      },
    },
  ],
});

if (manyToManyEnvelope.success && manyToManyEnvelope.data) {
  const names: string[] = manyToManyEnvelope.data.commenters.results.map(
    (c) => c.name,
  );
  console.log(names);
}

export const manyToManyBareSlice = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: ["id", { commenters: { limit: 2, offset: 1, fields: ["id"] } }],
});

// 8d: enable_filter?: false action still accepts sort, page, limit, and offset
export const noFilterActionStillSortsAndPages = await listTodosNoFilter({
  fields: [
    "id",
    {
      comments: {
        page: { limit: 2, offset: 0 },
        sort: "-rating",
        fields: ["id"],
      },
    },
  ],
});

export const noFilterActionBareSlice = await listTodosNoFilter({
  fields: ["id", { comments: { limit: 2, offset: 1, fields: ["id"] } }],
});

// 8e: enable_sort?: false action still accepts filter, page, limit, and offset
export const noSortActionStillFiltersAndPages = await listTodosNoSort({
  fields: [
    "id",
    {
      comments: {
        page: { limit: 2, offset: 0 },
        filter: { rating: { greaterThan: 2 } },
        fields: ["id"],
      },
    },
  ],
});

export const noSortActionBareSlice = await listTodosNoSort({
  fields: ["id", { comments: { limit: 2, offset: 1, fields: ["id"] } }],
});
