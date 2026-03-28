// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
//
// SPDX-License-Identifier: MIT

// Invalid Sort Tests - shouldFail
// Tests that sort fields are restricted to valid field names

import {
  listTodos,
  listUsers,
} from "../generated";

// Test 1: Invalid sort field name should fail
export const invalidField = await listTodos({
  fields: ["id", "title"],
  // @ts-expect-error - "nonExistentField" is not a valid TodoSortField
  sort: "nonExistentField",
});

// Test 2: Invalid field name with prefix should fail
export const invalidFieldWithPrefix = await listTodos({
  fields: ["id", "title"],
  // @ts-expect-error - "nonExistent" is not a valid TodoSortField even with prefix
  sort: "-nonExistent",
});

// Test 3: Array with invalid field should fail
export const invalidArrayField = await listTodos({
  fields: ["id", "title"],
  // @ts-expect-error - "fakeField" is not a valid TodoSortField
  sort: ["-title", "fakeField"],
});

// Test 4: Comma-separated string should fail (must use array now)
export const commaSeparated = await listTodos({
  fields: ["id", "title"],
  // @ts-expect-error - comma-separated strings are not valid, use arrays
  sort: "-title,+createdAt",
});

// Test 5: Valid field on wrong resource should fail
export const wrongResource = await listUsers({
  fields: ["id", "name"],
  // @ts-expect-error - "commentCount" is a TodoSortField, not a UserSortField
  sort: "commentCount",
});

// These should all succeed:
export const validSingle = await listTodos({
  fields: ["id", "title"],
  sort: "-title",
});

export const validArray = await listTodos({
  fields: ["id", "title"],
  sort: ["+title", "--createdAt", "++id"],
});

export const validNoPrefix = await listTodos({
  fields: ["id", "title"],
  sort: "title",
});

console.log("Invalid sort field tests should fail to compile!");
