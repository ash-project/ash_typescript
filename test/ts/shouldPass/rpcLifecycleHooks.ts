// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Test file demonstrating RPC lifecycle hooks usage

import {
  listTodos,
  createTodo,
  updateTodo,
  destroyTodo,
  validateCreateTodo,
  validateUpdateTodo,
} from "../generated";
import type { ActionHookContext, ValidationHookContext } from "../generated";

// Example 1: RPC action with full hook context (logging + timing)
async function listTodosWithLogging() {
  const hookCtx: ActionHookContext = {
    enableLogging: true,
    enableTiming: true,
  };

  const result = await listTodos({
    fields: ["id", "title", "description"],
    input: {},
    hookCtx,
  });

  return result;
}

// Example 2: RPC action with custom headers via hook context
async function createTodoWithCustomHeaders() {
  const hookCtx: ActionHookContext = {
    customHeaders: {
      "X-Request-ID": "unique-request-id-123",
      "X-Custom-Header": "custom-value",
    },
  };

  const result = await createTodo({
    fields: ["id", "title"],
    input: {
      title: "New Todo",
      description: "Created with custom headers",
      userId: "user-123",
    },
    hookCtx,
  });

  return result;
}

// Example 3: RPC action with partial hook context (only timing)
async function updateTodoWithTiming() {
  const hookCtx: ActionHookContext = {
    enableTiming: true,
  };

  const result = await updateTodo({
    primaryKey: "todo-id-123",
    fields: ["id", "title", "description"],
    input: {
      title: "Updated Title",
    },
    hookCtx,
  });

  return result;
}

// Example 4: RPC action without hook context (hooks still run for global behavior)
async function destroyTodoWithoutContext() {
  const result = await destroyTodo({
    primaryKey: "todo-id-456",
  });

  return result;
}

// Example 5: Validation with strict mode
async function validateCreateTodoStrict() {
  const hookCtx: ValidationHookContext = {
    enableLogging: true,
    validationLevel: "strict",
  };

  const result = await validateCreateTodo({
    input: {
      title: "Test Todo",
      userId: "user-123",
    },
    hookCtx,
  });

  return result;
}

// Example 6: Validation with normal mode
async function validateUpdateTodoNormal() {
  const hookCtx: ValidationHookContext = {
    validationLevel: "normal",
  };

  const result = await validateUpdateTodo({
    primaryKey: "update-todo-validation",
    input: {
      title: "Updated Test Todo",
    },
    hookCtx,
  });

  return result;
}

// Example 7: Validation without hook context
async function validateCreateTodoWithoutContext() {
  const result = await validateCreateTodo({
    input: {
      title: "Test Todo Without Context",
      userId: "user-123",
    },
  });

  return result;
}

// Example 8: Combining multiple hook context features
async function listTodosWithAllFeatures() {
  const hookCtx: ActionHookContext = {
    enableLogging: true,
    enableTiming: true,
    customHeaders: {
      "X-Request-ID": "combined-features-request",
      "X-Feature-Flag": "new-ui",
    },
  };

  const result = await listTodos({
    fields: ["id", "title", "description", { user: ["id", "name"] }],
    filter: {
      title: { eq: "test" },
    },
    input: {},
    hookCtx,
  });

  return result;
}

// Example 9: Using hook context with pagination
async function listTodosWithPagination() {
  const hookCtx: ActionHookContext = {
    enableLogging: true,
    enableTiming: true,
  };

  const result = await listTodos({
    fields: ["id", "title"],
    input: {},
    page: {
      limit: 10,
      offset: 0,
    },
    hookCtx,
  });

  return result;
}

// Example 10: Type-safe hook context (demonstrating optional fields)
async function createTodoMinimalContext() {
  // Only providing one field - all others are optional
  const hookCtx: ActionHookContext = {
    enableLogging: true,
  };

  const result = await createTodo({
    fields: ["id"],
    input: {
      title: "Minimal Context Todo",
      userId: "user-123",
    },
    hookCtx,
  });

  return result;
}

// Example 11: Empty hook context (still triggers hooks)
async function listTodosWithEmptyContext() {
  const hookCtx: ActionHookContext = {};

  const result = await listTodos({
    fields: ["id", "title"],
    input: {},
    hookCtx,
  });

  return result;
}

// Export examples for potential use in other test files
export {
  listTodosWithLogging,
  createTodoWithCustomHeaders,
  updateTodoWithTiming,
  destroyTodoWithoutContext,
  validateCreateTodoStrict,
  validateUpdateTodoNormal,
  validateCreateTodoWithoutContext,
  listTodosWithAllFeatures,
  listTodosWithPagination,
  createTodoMinimalContext,
  listTodosWithEmptyContext,
};
