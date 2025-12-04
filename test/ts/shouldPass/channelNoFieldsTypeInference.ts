// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Type Inference Tests for Channel Functions with Optional Fields
// Validates that TypeScript correctly infers empty object type when fields are omitted for channel operations

import { Channel } from "phoenix";
import { createUserChannel, updateUserChannel } from "../generated";

// Mock channel for testing
declare const mockChannel: Channel;

// Test 1: When fields is omitted, resultHandler should receive data typed as {}
createUserChannel({
  channel: mockChannel,
  input: {
    name: "Test User",
    email: "test@example.com",
  },
  resultHandler: (result) => {
    if (result.success) {
      // TypeScript should infer data as InferResult<UserResourceSchema, []> which is {}
      const data: {} = result.data;

      // This should compile - empty object type
      const isEmpty = Object.keys(data).length === 0;

      // @ts-expect-error - Should NOT have id property when no fields requested
      const shouldNotExist = result.data.id;
    }
  },
  errorHandler: (error) => console.error("Error:", error),
});

// Test 2: When fields is explicitly [], resultHandler should also receive data typed as {}
createUserChannel({
  channel: mockChannel,
  input: {
    name: "Test User 2",
    email: "test2@example.com",
  },
  fields: [],
  resultHandler: (result) => {
    if (result.success) {
      // @ts-expect-error - Should NOT have name property when fields is empty
      const shouldNotExist = result.data.name;
    }
  },
});

// Test 3: When fields are provided, resultHandler should receive those specific fields
createUserChannel({
  channel: mockChannel,
  input: {
    name: "Test User 3",
    email: "test3@example.com",
  },
  fields: ["id", "name"],
  resultHandler: (result) => {
    if (result.success) {
      // These properties SHOULD exist
      const id: string = result.data.id;
      const name: string = result.data.name;

      // @ts-expect-error - email was not requested so should not exist on type
      const shouldNotExist = result.data.email;
    }
  },
});

// Test 4: Update channel operations should have the same behavior
updateUserChannel({
  channel: mockChannel,
  identity: "user-id",
  input: {
    name: "Updated Name",
  },
  resultHandler: (result) => {
    if (result.success) {
      const data: {} = result.data;

      // @ts-expect-error - Should NOT have properties when no fields
      const shouldNotExist = result.data.id;
    }
  },
});

// Test 5: Update with explicit empty array
updateUserChannel({
  channel: mockChannel,
  identity: "user-id",
  input: {
    name: "Updated Name",
  },
  fields: [],
  resultHandler: (result) => {
    if (result.success) {
      // @ts-expect-error - Should NOT have properties when fields is []
      const shouldNotExist = result.data.name;
    }
  },
});

// Test 6: Update with specific fields
updateUserChannel({
  channel: mockChannel,
  identity: "user-id",
  input: {
    name: "Updated Name",
  },
  fields: ["id", "email"],
  resultHandler: (result) => {
    if (result.success) {
      // These properties SHOULD exist
      const id: string = result.data.id;
      const email: string = result.data.email;

      // @ts-expect-error - name was not requested so should not exist on type
      const shouldNotExist = result.data.name;
    }
  },
});

console.log(
  "Channel type inference tests for optional fields compiled successfully!",
);
