// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
//
// SPDX-License-Identifier: MIT

// Non-Field Calculations Tests - shouldFail
// Tests that calculations with field?: false are excluded from generated types

import {
  listTodos,
  getTodo,
} from "../generated";

// Test 1: field?: false calculation should not be valid in top-level fields
export const invalidNonFieldCalcInFields = await listTodos({
  fields: [
    "id",
    "title",
    // @ts-expect-error - "internalScore" has field?: false, should not be in generated types
    "internalScore",
  ],
});

// Test 2: field?: false calculation should not be valid in get action fields
export const invalidNonFieldCalcInGet = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: [
    "id",
    "title",
    // @ts-expect-error - "internalScore" has field?: false, should not be in generated types
    "internalScore",
  ],
});

// Test 3: field?: false calculation should not be valid in nested self calculation fields
export const invalidNonFieldCalcInSelf = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: [
    "id",
    {
      self: {
        args: { prefix: "test_" },
        fields: [
          "id",
          "title",
          // @ts-expect-error - "internalScore" has field?: false, should not be in nested fields
          "internalScore",
        ],
      },
    },
  ],
});

console.log("Non-field calculation tests should FAIL compilation!");
