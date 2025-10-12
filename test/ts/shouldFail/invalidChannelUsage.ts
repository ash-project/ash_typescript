// SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
//
// SPDX-License-Identifier: MIT

// Invalid Channel Usage Tests - shouldFail
// Tests for invalid channel function usage that should fail TypeScript compilation

import { Channel } from "phoenix";
import {
  getTodoChannel,
  listTodosChannel,
  createTodoChannel,
  updateTodoChannel,
  destroyTodoChannel,
  validateGetTodoChannel,
} from "../generated";

// Mock channel for testing
declare const mockChannel: Channel;

// Test 1: Missing required resultHandler
// @ts-expect-error - resultHandler is required
getTodoChannel({
  channel: mockChannel,
  input: {},
  fields: ["id", "title"],
  errorHandler: (error) => console.error("Error:", error),
  timeoutHandler: () => console.error("Timeout"),
});

// Test 2: Missing required channel
// @ts-expect-error - channel is required
listTodosChannel({
  input: {},
  fields: ["id", "title"],
  resultHandler: (result) => console.log(result),
  errorHandler: (error) => console.error("Error:", error),
  timeoutHandler: () => console.error("Timeout"),
});

// Test 3: Invalid field names in channel operations
createTodoChannel({
  channel: mockChannel,
  input: {
    title: "Test Todo",
    userId: "user-123",
  },
  fields: [
    "id",
    "title",
    // @ts-expect-error - "nonExistentField" should not be valid
    "nonExistentField",
    // @ts-expect-error - "invalidField" should not be valid
    "invalidField",
  ],
  resultHandler: (result) => console.log(result),
  errorHandler: (error) => console.error("Error:", error),
  timeoutHandler: () => console.error("Timeout"),
});

// Test 4: Invalid input parameters
updateTodoChannel({
  channel: mockChannel,
  primaryKey: "todo-123",
  input: {
    title: "Updated Title",
    // @ts-expect-error - "invalidInputField" should not be valid
    invalidInputField: "invalid",
    fakeProperty: 123,
  },
  fields: ["id", "title"],
  resultHandler: (result) => console.log(result),
  errorHandler: (error) => console.error("Error:", error),
  timeoutHandler: () => console.error("Timeout"),
});

// Test 5: Invalid nested field access in channel operations
getTodoChannel({
  channel: mockChannel,
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
      lol: "lol",
      nonExistentRelation: ["id", "title"],
    },
  ],
  resultHandler: (result) => console.log(result),
  errorHandler: (error) => console.error("Error:", error),
  timeoutHandler: () => console.error("Timeout"),
});

// Test 6: Wrong handler function signatures
getTodoChannel({
  channel: mockChannel,
  input: {},
  fields: ["id", "title"],
  resultHandler: () => console.log("Wrong signature"),
  errorHandler: (error) => console.error("Error:", error),
  timeoutHandler: () => console.error("Timeout"),
});

// Test 7: Missing required input parameters
createTodoChannel({
  channel: mockChannel,
  // @ts-expect-error - title is required for createTodo
  input: {
    // title: "Missing required field",
    userId: "user-123",
  },
  fields: ["id", "title"],
  resultHandler: (result) => console.log(result),
  errorHandler: (error) => console.error("Error:", error),
  timeoutHandler: () => console.error("Timeout"),
});

// Test 8: Invalid calculation arguments in channel operations
listTodosChannel({
  channel: mockChannel,
  input: {},
  fields: [
    "id",
    {
      self: {
        args: {
          prefix: "test_",
          invalidArg: "not allowed",
          fakeParameter: 123,
        },
        fields: ["id", "title"],
      },
    },
  ],
  resultHandler: (result) => console.log(result),
  errorHandler: (error) => console.error("Error:", error),
  timeoutHandler: () => console.error("Timeout"),
});

// Test 9: Trying to pass wrong channel type
getTodoChannel({
  // @ts-expect-error - channel should be Channel type
  channel: "not-a-channel",
  input: {},
  fields: ["id"],
  resultHandler: (result) => console.log(result),
  errorHandler: (error) => console.error("Error:", error),
  timeoutHandler: () => console.error("Timeout"),
});

// Test 10: Invalid destroy operation without required primaryKey
// @ts-expect-error - primaryKey is required for destroy operation
destroyTodoChannel({
  channel: mockChannel,
  // primaryKey: "required-id"
  resultHandler: (result) => console.log(result),
  errorHandler: (error) => console.error("Error:", error),
  timeoutHandler: () => console.error("Timeout"),
});

// Test 11: Invalid validation function usage with extra properties
validateGetTodoChannel({
  channel: mockChannel,
  input: {},
  // @ts-expect-error - fields should not be valid for validation functions
  fields: ["id", "title"],
  resultHandler: (result) => console.log(result),
  errorHandler: (error) => console.error("Error:", error),
  timeoutHandler: () => console.error("Timeout"),
});

console.log("Invalid channel usage tests should FAIL compilation!");
