// SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
//
// SPDX-License-Identifier: MIT

// Operations Tests - shouldFail
// Tests for invalid operation usage that should fail TypeScript compilation

import {
  getTodo,
  listTodos,
  createTodo,
  updateTodo,
  destroyTodo,
  searchTodos,
} from "../generated";

// Test 1: Invalid field names in operations
listTodos({
  input: {},
  fields: [
    "id",
    "title",
    // @ts-expect-error - "nonExistentField" should not be valid
    "nonExistentField",
  ],
});

// Test 2: Invalid input parameters for createTodo
createTodo({
  // @ts-expect-error - title is required for createTodo
  input: {
    // title: "Required field",
    userId: "user-123",
  },
  fields: ["id", "title"],
});

// Test 3: Invalid nested field access
getTodo({
  input: {},
  fields: [
    "id",
    {
      user: [
        "id",
        "name",
        // @ts-expect-error - "invalidUserField" should not be valid
        "invalidUserField",
      ],
      nonExistentRelation: ["id", "title"],
    },
  ],
});

// Test 4: Invalid calculation arguments
listTodos({
  input: {},
  fields: [
    "id",
    {
      user: ["id"],
      self: {
        args: {
          prefix: "test_",
          invalidArg: "not allowed",
        },
        fields: ["id", "title"],
      },
    },
  ],
});

// Test 5: Invalid input field types
createTodo({
  input: {
    title: "Valid title",
    // @ts-expect-error - completed should be boolean, not string
    completed: "invalid",
    userId: "user-123",
  },
  fields: ["id", "title"],
});

// Test 6: Invalid priority enum value
createTodo({
  input: {
    title: "Valid title",
    // @ts-expect-error - "invalid" is not a valid priority value
    priority: "invalid",
    userId: "user-123",
  },
  fields: ["id", "title"],
});

// Test 7: Invalid status enum value
createTodo({
  input: {
    title: "Valid title",
    // @ts-expect-error - "invalid" is not a valid status value
    status: "invalid",
    userId: "user-123",
  },
  fields: ["id", "title"],
});

// Test 8: Missing required primaryKey for update
// @ts-expect-error - primaryKey is required for updateTodo
updateTodo({
  input: {
    title: "Updated title",
  },
  fields: ["id", "title"],
});

// Test 9: Missing required primaryKey for destroy
// @ts-expect-error - primaryKey is required for destroyTodo
destroyTodo({});

// Test 10: Invalid field selection in destroy (destroy typically doesn't return data)
destroyTodo({
  primaryKey: "todo-123",
  // @ts-expect-error - fields should not be valid for destroy operations
  fields: ["id", "title"],
});

// Test 11: Invalid nested calculation structure
getTodo({
  input: {},
  fields: [
    "id",
    {
      self: {
        // @ts-expect-error - args should be an object, not a string
        args: "invalid",
        fields: ["id"],
      },
    },
  ],
});

// Test 12: Invalid input type for search
searchTodos({
  input: {
    // @ts-expect-error - query should be string, not number
    query: 123,
  },
  fields: ["id", "title"],
});

console.log("Invalid operations tests should FAIL compilation!");
