// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Struct Arguments Tests - shouldPass
// Tests for actions that accept resource structs as arguments
// These test the InputSchema type generation (vs ResourceSchema)

import {
  assignToUserTodo,
  assignToUsersTodo,
  AssignToUserTodoInput,
  AssignToUsersTodoInput,
  UserInputSchema,
} from "../generated";

// Test 1: Single struct argument - assign a user to a todo
// The input type should use UserInputSchema (without __type, __primitiveFields metadata)
export const assignSingleUser = await assignToUserTodo({
  input: {
    assignee: {
      id: "17b3279e-d1f1-11f0-993d-4ea1aae63366",
      name: "Test User",
      email: "test@example.com",
    },
    reason: "Testing struct argument",
  },
  fields: ["assigneeId", "assigneeName", "reason"],
});

// Type validation for single struct argument result
if (assignSingleUser.success) {
  const assigneeId: string = assignSingleUser.data.assigneeId;
  const assigneeName: string = assignSingleUser.data.assigneeName;
  const reason: string | null = assignSingleUser.data.reason;
}

// Test 2: Single struct argument without optional reason
export const assignWithoutReason = await assignToUserTodo({
  input: {
    assignee: {
      id: "17b3279e-d1f1-11f0-993d-4ea1aae63366",
      name: "Another User",
      email: "another@example.com",
    },
    // reason is optional, so we can omit it
  },
  fields: ["assigneeId", "assigneeName"],
});

// Type validation
if (assignWithoutReason.success) {
  const assigneeId: string = assignWithoutReason.data.assigneeId;
  const assigneeName: string = assignWithoutReason.data.assigneeName;
}

// Test 3: Array of struct arguments - assign multiple users
export const assignMultipleUsers = await assignToUsersTodo({
  input: {
    assignees: [
      {
        id: "17b3279e-d1f1-11f0-993d-4ea1aae63367",
        name: "User One",
        email: "one@example.com",
      },
      {
        id: "17b3279e-d1f1-11f0-993d-4ea1aae63366",
        name: "User Two",
        email: "two@example.com",
      },
    ],
  },
  fields: ["assigneeId", "assigneeName"],
});

// Type validation for array result
if (assignMultipleUsers.success) {
  for (const assignment of assignMultipleUsers.data) {
    const assigneeId: string = assignment.assigneeId;
    const assigneeName: string = assignment.assigneeName;
  }
}

// Test 4: Empty array of struct arguments
export const assignEmptyArray = await assignToUsersTodo({
  input: {
    assignees: [],
  },
  fields: ["assigneeId", "assigneeName"],
});

// Type validation for empty result
if (assignEmptyArray.success) {
  const emptyData: Array<{ assigneeId: string; assigneeName: string }> =
    assignEmptyArray.data;
}

// Test 5: Type-level validation - UserInputSchema should NOT have metadata fields
// This is a compile-time test - if UserInputSchema had __type or __primitiveFields,
// this would cause a type error
const userInput: UserInputSchema = {
  id: "test-id",
  name: "Test",
  email: "test@test.com",
  // Note: We should NOT be able to add __type or __primitiveFields here
  // because UserInputSchema only contains the public attributes
};

// Test 6: Input type validation - the input types are correctly typed
const assignInput: AssignToUserTodoInput = {
  assignee: {
    name: "Required Name",
    email: "required@email.com",
    // id is optional in input
  },
  // reason is optional
};

const assignArrayInput: AssignToUsersTodoInput = {
  assignees: [
    {
      name: "User",
      email: "user@test.com",
    },
  ],
};

// Test 7: UserInputSchema with all optional fields
const minimalUserInput: UserInputSchema = {
  name: "Minimal User", // required
  email: "minimal@test.com", // required
  // Everything else is optional
};

const fullUserInput: UserInputSchema = {
  id: "full-id",
  name: "Full User",
  email: "full@test.com",
  active: true,
  isSuperAdmin: false,
  addressLine1: "123 Main St",
};
