// SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
//
// SPDX-License-Identifier: MIT

// Channel Validation Tests - shouldPass
// Tests for channel validation functions

import { Channel } from "phoenix";
import {
  validateGetTodoChannel,
  validateListTodosChannel,
  validateCreateTodoChannel,
  validateUpdateTodoChannel,
  validateDestroyTodoChannel,
  validateCreateTodoCommentChannel,
  validateListUsersChannel,
} from "../generated";

// Mock channel for testing
declare const mockChannel: Channel;

// Test 1: Validation with minimal required fields
validateGetTodoChannel({
  channel: mockChannel,
  input: {},
  resultHandler: (result) => {
    if (result.success) {
      console.log("Minimal validation passed");
    }
  },
  errorHandler: (error) => console.error("Error:", error),
  timeoutHandler: () => console.error("Timeout")
});

// Test 2: Validation with complex input parameters
validateListTodosChannel({
  channel: mockChannel,
  input: {
    filterCompleted: true,
    priorityFilter: "medium"
  },
  resultHandler: (result) => {
    if (result.success) {
      console.log("Complex validation passed");
    }
  },
  errorHandler: (error) => console.error("Complex validation error:", error),
  timeoutHandler: () => console.error("Complex validation timeout")
});

// Test 3: Validation with input parameters
validateCreateTodoChannel({
  channel: mockChannel,
  input: {
    title: "Validation Test Todo",
    status: "pending",
    priority: "high",
    userId: "user-validation-123",
    description: "This is a validation test",
    dueDate: "2024-12-31",
  },
  resultHandler: (result) => {
    if (result.success) {
      console.log("Create validation with full input passed");
    }
  },
  errorHandler: (error) => console.error("Create validation error:", error),
  timeoutHandler: () => console.error("Create validation timeout")
});

// Test 4: Validation with optional input parameters
validateUpdateTodoChannel({
  channel: mockChannel,
  primaryKey: "todo-validation-update",
  input: {
    title: "Updated Validation Title",
    // Other optional fields omitted
  },
  resultHandler: (result) => {
    if (result.success) {
      console.log("Update validation with partial input passed");
    }
  },
  errorHandler: (error) => console.error("Update validation error:", error),
  timeoutHandler: () => console.error("Update validation timeout")
});

// Test 5: Validation with no input parameters
validateDestroyTodoChannel({
  channel: mockChannel,
  primaryKey: "todo-validation-destroy",
  resultHandler: (result) => {
    if (result.success) {
      console.log("Destroy validation passed");
    }
  },
  errorHandler: (error) => console.error("Destroy validation error:", error),
  timeoutHandler: () => console.error("Destroy validation timeout")
});

// Test 6: Validation for related resource operations
validateCreateTodoCommentChannel({
  channel: mockChannel,
  input: {
    content: "This is a validation comment",
    authorName: "Validation Author",
    todoId: "todo-validation-123",
    userId: "user-validation-456",
    rating: 5,
  },
  resultHandler: (result) => {
    if (result.success) {
      console.log("Comment validation passed");
    }
  },
  errorHandler: (error) => console.error("Comment validation error:", error),
  timeoutHandler: () => console.error("Comment validation timeout")
});

// Test 7: Validation for list operations on different resources
validateListUsersChannel({
  channel: mockChannel,
  resultHandler: (result) => {
    if (result.success) {
      console.log("Users list validation passed");
    }
  },
  errorHandler: (error) => console.error("Users validation error:", error),
  timeoutHandler: () => console.error("Users validation timeout")
});

console.log("Channel validation tests should compile successfully!");