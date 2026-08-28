// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Nested Relationship Query Options - shouldFail

import { getTodo, listTodosNoFilter, listTodosNoSort } from "../generated";

// Test 1: filter key on an enable_filter?: false action's nested envelope
export const filterDisabled = await listTodosNoFilter({
  fields: [
    "id",
    {
      comments: {
        // @ts-expect-error - filter is not offered when enable_filter? is false
        filter: { rating: { greaterThan: 2 } },
        fields: ["id"],
      },
    },
  ],
});

// Test 2: sort key on an enable_sort?: false action's nested envelope
export const sortDisabled = await listTodosNoSort({
  fields: [
    "id",
    {
      comments: {
        // @ts-expect-error - sort is not offered when enable_sort? is false
        sort: "-rating",
        fields: ["id"],
      },
    },
  ],
});

// Test 3: filter on a filterable?: false relationship
export const filterUnfilterable = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: [
    "id",
    {
      unfilterableComments: {
        // @ts-expect-error - relationship is not filterable
        filter: { rating: { greaterThan: 2 } },
        fields: ["id"],
      },
    },
  ],
});

// Test 4: sort on a sortable?: false relationship
export const sortUnsortable = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: [
    "id",
    {
      unsortableComments: {
        // @ts-expect-error - relationship is not sortable
        sort: "-rating",
        fields: ["id"],
      },
    },
  ],
});

// Test 5: page on a non-paginatable relationship
export const pageUnpaginated = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: [
    "id",
    {
      // @ts-expect-error - relationship read action has no pagination
      unpaginatedComments: {
        page: { limit: 1 },
        fields: ["id"],
      },
    },
  ],
});

// Test 6: envelope on a to-one relationship
export const envelopeOnToOne = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: [
    "id",
    {
      // @ts-expect-error - to-one relationships take a plain field list
      user: { limit: 1, fields: ["id"] },
    },
  ],
});

// Test 7: envelope on an embedded resource attribute
export const envelopeOnEmbedded = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: [
    "id",
    {
      // @ts-expect-error - embedded resources take a plain field list
      metadata: { limit: 1, fields: ["category"] },
    },
  ],
});

// Test 8: treating a paged result as an array
export const pagedResult = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: ["id", { comments: { page: { limit: 3 }, fields: ["id"] } }],
});

if (pagedResult.success && pagedResult.data) {
  // @ts-expect-error - a paged nested result is a page object, not an array
  pagedResult.data.comments.map((c) => c.id);
}

// Test 9: filter is typed to the destination resource's FilterInput
export const filterWrongField = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: [
    "id",
    {
      comments: {
        // @ts-expect-error - bogusField is not a TodoComment filter field
        filter: { bogusField: { eq: 1 } },
        fields: ["id"],
      },
    },
  ],
});

// Test 10: sort is typed to the destination resource's SortField union
export const sortWrongField = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: [
    "id",
    {
      // @ts-expect-error - bogusField is not a TodoComment sort field
      comments: {
        sort: "-bogusField",
        fields: ["id"],
      },
    },
  ],
});

// Test 11: offset and keyset page keys cannot be mixed in one page object.
// (A completely unknown page key is rejected at runtime only — excess-property
// checking does not fire through the envelope's conditional types.)
export const pageMixedFamilies = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: [
    "id",
    {
      // @ts-expect-error - offset (offset family) and after (keyset family) are exclusive
      comments: {
        page: { offset: 0, after: "cursor" },
        fields: ["id"],
      },
    },
  ],
});

// Test 11b: page is exclusive with bare limit
export const pageWithLimit = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: [
    "id",
    {
      comments: {
        page: { limit: 2 },
        // @ts-expect-error - page and bare limit are mutually exclusive
        limit: 3,
        fields: ["id"],
      },
    },
  ],
});

// Test 11c: page is exclusive with bare offset
export const pageWithOffset = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: [
    "id",
    {
      comments: {
        page: { limit: 2 },
        // @ts-expect-error - page and bare offset are mutually exclusive
        offset: 1,
        fields: ["id"],
      },
    },
  ],
});

// Test 11d: keyset page keys are rejected on an offset-only relationship
export const keysetKeysOnOffsetOnly = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: [
    "id",
    {
      // @ts-expect-error - after is a keyset key; relationship is offset-only
      offsetComments: {
        page: { limit: 2, after: "cursor" },
        fields: ["id"],
      },
    },
  ],
});

// Test 11e: offset page keys are rejected on a keyset-only relationship
export const offsetKeysOnKeysetOnly = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: [
    "id",
    {
      // @ts-expect-error - offset is an offset key; relationship is keyset-only
      keysetComments: {
        page: { limit: 2, offset: 1 },
        fields: ["id"],
      },
    },
  ],
});

// Test 12: the envelope requires a fields key
export const missingFields = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: [
    "id",
    {
      // @ts-expect-error - fields is required inside a query envelope
      comments: { limit: 2 },
    },
  ],
});
