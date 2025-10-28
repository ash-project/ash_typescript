// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// No Fields Read Actions Tests - shouldFail
// Tests that read actions still require fields parameter

import {
  listUsers,
  listTodos,
  getTodo,
} from "../generated";

// Test 1: List users without fields should fail
// @ts-expect-error - fields is required for read actions
listUsers({
  // Missing fields parameter - should fail
});

// Test 2: List todos without fields should fail
// @ts-expect-error - fields is required for read actions
listTodos({
  input: {},
  // Missing fields parameter - should fail
});

// Test 3: Get todo without fields should fail
// @ts-expect-error - fields is required for read actions
getTodo({
  input: {},
  // Missing fields parameter - should fail
});

// Test 4: List users with filter but no fields should fail
// @ts-expect-error - fields is required even when other params are present
listUsers({
  filter: {
    isActive: { eq: true },
  },
  // Missing fields parameter - should fail
});

// Test 5: List users with sort but no fields should fail
// @ts-expect-error - fields is required even when other params are present
listUsers({
  sort: "name",
  // Missing fields parameter - should fail
});

console.log("These read action calls without fields should fail to compile!");
