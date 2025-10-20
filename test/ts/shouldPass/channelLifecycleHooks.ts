//SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Test file demonstrating Phoenix Channel lifecycle hooks usage

import { Channel } from "phoenix";
import {
  listTodosChannel,
  createTodoChannel,
  updateTodoChannel,
  destroyTodoChannel,
  validateCreateTodoChannel,
  validateUpdateTodoChannel,
} from "../generated";
import type {
  ActionChannelHookContext,
  ValidationChannelHookContext,
} from "../generated";

// Mock channel for testing
const mockChannel: Channel = {} as Channel;

// Example 1: Channel action with performance tracking
function listTodosWithChannelHooks() {
  const hookCtx: ActionChannelHookContext = {
    trackPerformance: true,
    correlationId: "request-123",
  };

  listTodosChannel({
    channel: mockChannel,
    input: {},
    fields: ["id", "title", "description"],
    hookCtx,
    resultHandler: (result) => {
      if (result.success) {
        console.log("Todos loaded:", result.data);
      } else {
        console.error("Failed to load todos:", result.errors);
      }
    },
  });
}

// Example 2: Channel action with custom timeout
function createTodoWithChannelTimeout() {
  const hookCtx: ActionChannelHookContext = {
    trackPerformance: true,
    correlationId: "timeout-request",
  };

  createTodoChannel({
    channel: mockChannel,
    fields: ["id", "title"],
    input: {
      title: "New Todo via Channel",
      description: "Created with timeout configuration",
      userId: "user-123",
    },
    timeout: 5000, // 5 second timeout
    hookCtx,
    resultHandler: (result) => {
      console.log("Todo created:", result);
    },
    timeoutHandler: () => {
      console.error("Request timed out after 5 seconds");
    },
  });
}

// Example 3: Channel action with correlation ID
function updateTodoWithChannelTracking() {
  const hookCtx: ActionChannelHookContext = {
    trackPerformance: true,
    correlationId: "update-456",
  };

  updateTodoChannel({
    channel: mockChannel,
    primaryKey: "todo-id-123",
    fields: ["id", "title", "description"],
    input: {
      title: "Updated via Channel",
    },
    hookCtx,
    resultHandler: (result) => {
      console.log("Update result:", result);
    },
    errorHandler: (error) => {
      console.error("Update failed:", error);
    },
  });
}

// Example 4: Channel action without hook context (hooks still run for global behavior)
function destroyTodoWithoutChannelContext() {
  destroyTodoChannel({
    channel: mockChannel,
    primaryKey: "todo-id-456",
    resultHandler: (result) => {
      console.log("Todo destroyed:", result);
    },
  });
}

// Example 5: Channel validation with strict mode
function validateCreateTodoViaChannelStrict() {
  const hookCtx: ValidationChannelHookContext = {
    formId: "create-todo-form",
    validationLevel: "strict",
  };

  validateCreateTodoChannel({
    channel: mockChannel,
    input: {
      title: "Test Todo",
      userId: "user-123",
    },
    hookCtx,
    resultHandler: (result) => {
      if (result.success) {
        console.log("Validation passed");
      } else {
        console.log("Validation errors:", result.errors);
      }
    },
  });
}

// Example 6: Channel validation with normal mode
function validateUpdateTodoViaChannelNormal() {
  const hookCtx: ValidationChannelHookContext = {
    formId: "update-todo-form",
    validationLevel: "normal",
  };

  validateUpdateTodoChannel({
    channel: mockChannel,
    primaryKey: "update-todo-validation",
    input: {
      title: "Updated Test Todo",
    },
    hookCtx,
    resultHandler: (result) => {
      console.log("Validation result:", result);
    },
  });
}

// Example 7: Channel validation without hook context
function validateCreateTodoViaChannelWithoutContext() {
  validateCreateTodoChannel({
    channel: mockChannel,
    input: {
      title: "Test Todo Without Context",
      userId: "user-123",
    },
    resultHandler: (result) => {
      console.log("Validation result:", result);
    },
  });
}

// Example 8: Combining multiple hook context features for channel
function listTodosViaChannelWithAllFeatures() {
  const hookCtx: ActionChannelHookContext = {
    trackPerformance: true,
    correlationId: "combined-features-channel-request",
  };

  listTodosChannel({
    channel: mockChannel,
    input: {},
    fields: ["id", "title", "description", { user: ["id", "name"] }],
    filter: {
      title: { eq: "test" },
    },
    hookCtx,
    resultHandler: (result) => {
      console.log("Todos loaded with all features:", result);
    },
    errorHandler: (error) => {
      console.error("Failed to load todos:", error);
    },
    timeoutHandler: () => {
      console.error("Request timed out");
    },
  });
}

// Example 9: Using hook context with pagination via channel
function listTodosViaChannelWithPagination() {
  const hookCtx: ActionChannelHookContext = {
    trackPerformance: true,
    correlationId: "pagination-request",
  };

  listTodosChannel({
    channel: mockChannel,
    input: {},
    fields: ["id", "title"],
    page: {
      limit: 10,
      offset: 0,
    },
    hookCtx,
    resultHandler: (result) => {
      console.log("Paginated todos:", result);
    },
  });
}

// Example 10: Type-safe channel hook context (demonstrating optional fields)
function createTodoViaChannelMinimalContext() {
  // Only providing correlationId - all other fields are optional
  const hookCtx: ActionChannelHookContext = {
    correlationId: "minimal-context",
  };

  createTodoChannel({
    channel: mockChannel,
    fields: ["id"],
    input: {
      title: "Minimal Context Todo",
      userId: "user-123",
    },
    hookCtx,
    resultHandler: (result) => {
      console.log("Todo created:", result);
    },
  });
}

// Example 11: Empty hook context (still triggers hooks)
function listTodosViaChannelWithEmptyContext() {
  const hookCtx: ActionChannelHookContext = {};

  listTodosChannel({
    channel: mockChannel,
    input: {},
    fields: ["id", "title"],
    hookCtx,
    resultHandler: (result) => {
      console.log("Todos loaded:", result);
    },
  });
}

// Example 12: Channel action with auth token in context
function listTodosWithChannelAuth() {
  const hookCtx: ActionChannelHookContext = {
    enableAuth: true,
    authToken: "user-auth-token-xyz",
    correlationId: "auth-request",
  };

  listTodosChannel({
    channel: mockChannel,
    input: {},
    fields: ["id", "title", { user: ["id", "name"] }],
    hookCtx,
    resultHandler: (result) => {
      console.log("Authenticated todos:", result);
    },
  });
}

// Example 13: Performance tracking with channel hooks
function updateTodoWithPerformanceTracking() {
  const hookCtx: ActionChannelHookContext = {
    trackPerformance: true,
    correlationId: "update-perf-test",
  };

  updateTodoChannel({
    channel: mockChannel,
    primaryKey: "todo-perf-123",
    fields: ["id", "title"],
    input: {
      title: "Performance Tracked Update",
    },
    hookCtx,
    resultHandler: (result) => {
      console.log("Update completed:", result);
    },
  });
}

// Example 14: Validation with form tracking
function validateTodoWithFormTracking() {
  const hookCtx: ValidationChannelHookContext = {
    formId: "todo-form-advanced",
    validationLevel: "strict",
  };

  validateCreateTodoChannel({
    channel: mockChannel,
    input: {
      title: "Validated with Tracking",
      userId: "user-123",
    },
    hookCtx,
    resultHandler: (result) => {
      if (result.success) {
        console.log("Validation passed with tracking");
      } else {
        console.log("Validation failed:", result.errors);
      }
    },
  });
}

// Example 15: Channel action with explicit timeout override
function createTodoWithExplicitTimeout() {
  const hookCtx: ActionChannelHookContext = {
    trackPerformance: true,
    correlationId: "timeout-override",
  };

  createTodoChannel({
    channel: mockChannel,
    fields: ["id", "title"],
    input: {
      title: "Todo with Timeout",
      userId: "user-123",
    },
    timeout: 7000, // Explicit timeout takes precedence
    hookCtx,
    resultHandler: (result) => {
      console.log("Todo created:", result);
    },
  });
}

// Export examples for potential use in other test files
export {
  listTodosWithChannelHooks,
  createTodoWithChannelTimeout,
  updateTodoWithChannelTracking,
  destroyTodoWithoutChannelContext,
  validateCreateTodoViaChannelStrict,
  validateUpdateTodoViaChannelNormal,
  validateCreateTodoViaChannelWithoutContext,
  listTodosViaChannelWithAllFeatures,
  listTodosViaChannelWithPagination,
  createTodoViaChannelMinimalContext,
  listTodosViaChannelWithEmptyContext,
  listTodosWithChannelAuth,
  updateTodoWithPerformanceTracking,
  validateTodoWithFormTracking,
  createTodoWithExplicitTimeout,
};
