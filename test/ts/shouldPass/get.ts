// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Get Tests - shouldPass
// Tests for get? RPC option - constrains read action to return single resource
// Note: get? uses Ash.read_one - it does NOT add primary key as input

import {
  getSingleTodo,
  GetSingleTodoResult,
  InferGetSingleTodoResult,
  getSingleTodoNullable,
  InferGetSingleTodoNullableResult,
} from "../generated";

// Test 1: Basic get with simple fields - input is optional
export const getSingleTodoBasic = await getSingleTodo({
  fields: ["id", "title", "description", "completed", "status"],
});

// Type validation for basic get result
if (getSingleTodoBasic.success) {
  // Result should be single item or null (not an array)
  const data = getSingleTodoBasic.data;

  if (data !== null) {
    const todoId: string = data.id;
    const todoTitle: string = data.title;
    const todoDescription: string | null | undefined = data.description;
    const todoCompleted: boolean | null | undefined = data.completed;
    const todoStatus: string | null | undefined = data.status;
  }
}

// Test 2: Get with input parameters (action's built-in arguments)
export const getSingleTodoWithInput = await getSingleTodo({
  input: {
    filterCompleted: false,
    priorityFilter: "high",
  },
  fields: ["id", "title", "priority", "completed"],
});

// Type validation for get with input
if (getSingleTodoWithInput.success) {
  const data = getSingleTodoWithInput.data;

  if (data !== null) {
    const todoId: string = data.id;
    const todoTitle: string = data.title;
    const todoPriority: string | null | undefined = data.priority;
    const todoCompleted: boolean | null | undefined = data.completed;
  }
}

// Test 3: Get with relationship fields
export const getSingleTodoWithUser = await getSingleTodo({
  fields: [
    "id",
    "title",
    {
      user: ["id", "name", "email"],
    },
  ],
});

// Type validation for get with relationships
if (getSingleTodoWithUser.success) {
  const data = getSingleTodoWithUser.data;

  if (data !== null) {
    const todoId: string = data.id;
    const todoTitle: string = data.title;
    const userName: string = data.user.name;
    const userEmail: string = data.user.email;
  }
}

// Test 4: Get with aggregate fields
export const getSingleTodoWithAggregates = await getSingleTodo({
  fields: ["id", "title", "commentCount", "hasComments", "averageRating"],
});

// Type validation for get with aggregates
if (getSingleTodoWithAggregates.success) {
  const data = getSingleTodoWithAggregates.data;

  if (data !== null) {
    const todoId: string = data.id;
    const todoTitle: string = data.title;
    const commentCount: number = data.commentCount;
    const hasComments: boolean = data.hasComments;
    const averageRating: number | null | undefined = data.averageRating;
  }
}

// Test 5: Get with calculation fields
export const getSingleTodoWithCalculations = await getSingleTodo({
  fields: ["id", "title", "isOverdue", "daysUntilDue"],
});

// Type validation for get with calculations
if (getSingleTodoWithCalculations.success) {
  const data = getSingleTodoWithCalculations.data;

  if (data !== null) {
    const todoId: string = data.id;
    const isOverdue: boolean | null | undefined = data.isOverdue;
    const daysUntilDue: number | null | undefined = data.daysUntilDue;
  }
}

// Test 6: Get with embedded resource fields
export const getSingleTodoWithMetadata = await getSingleTodo({
  fields: [
    "id",
    "title",
    {
      metadata: ["category", "priorityScore"],
    },
  ],
});

// Type validation for get with embedded resources
if (getSingleTodoWithMetadata.success) {
  const data = getSingleTodoWithMetadata.data;

  if (data !== null && data.metadata) {
    const category: string | null | undefined = data.metadata.category;
    const priorityScore: number | null | undefined =
      data.metadata.priorityScore;
  }
}

// Test 7: Get with self calculation
export const getSingleTodoWithSelf = await getSingleTodo({
  fields: [
    "id",
    "title",
    {
      self: {
        args: { prefix: "get_" },
        fields: ["id", "title", "description", "completed"],
      },
    },
  ],
});

// Type validation for get with self calculation
if (getSingleTodoWithSelf.success) {
  const data = getSingleTodoWithSelf.data;

  if (data !== null && data.self) {
    const selfId: string = data.self.id;
    const selfTitle: string = data.self.title;
    const selfDescription: string | null | undefined = data.self.description;
    const selfCompleted: boolean | null | undefined = data.self.completed;
  }
}

// Test 8: Get with nested self calculation
export const getSingleTodoWithNestedSelf = await getSingleTodo({
  fields: [
    "id",
    "title",
    {
      self: {
        args: { prefix: "outer_" },
        fields: [
          "id",
          "title",
          {
            self: {
              args: { prefix: "inner_" },
              fields: ["id", "status", "priority"],
            },
          },
        ],
      },
    },
  ],
});

// Type validation for nested self calculation
if (getSingleTodoWithNestedSelf.success) {
  const data = getSingleTodoWithNestedSelf.data;

  if (data !== null && data.self?.self) {
    const innerSelfId: string = data.self.self.id;
    const innerSelfStatus: string | null | undefined = data.self.self.status;
    const innerSelfPriority: string | null | undefined =
      data.self.self.priority;
  }
}

// Test 9: Get with comments relationship
export const getSingleTodoWithComments = await getSingleTodo({
  fields: [
    "id",
    "title",
    {
      comments: ["id", "content", "authorName", "isHelpful"],
    },
  ],
});

// Type validation for get with comments relationship
if (getSingleTodoWithComments.success) {
  const data = getSingleTodoWithComments.data;

  if (data !== null) {
    const todoId: string = data.id;
    const todoTitle: string = data.title;

    for (const comment of data.comments) {
      const commentId: string = comment.id;
      const commentContent: string = comment.content;
      const authorName: string = comment.authorName;
      const isHelpful: boolean | null | undefined = comment.isHelpful;
    }
  }
}

// Test 10: Get with multiple relationship and calculation fields
export const getSingleTodoComplex = await getSingleTodo({
  fields: [
    "id",
    "title",
    "completed",
    "isOverdue",
    "commentCount",
    {
      user: ["id", "name"],
      comments: ["id", "content"],
      metadata: ["category"],
      self: {
        args: { prefix: "complex_" },
        fields: ["id", "title"],
      },
    },
  ],
});

// Type validation for complex get
if (getSingleTodoComplex.success) {
  const data = getSingleTodoComplex.data;

  if (data !== null) {
    // Basic fields
    const todoId: string = data.id;
    const todoTitle: string = data.title;
    const todoCompleted: boolean | null | undefined = data.completed;

    // Calculation
    const isOverdue: boolean | null | undefined = data.isOverdue;

    // Aggregate
    const commentCount: number = data.commentCount;

    // Relationships
    const userName: string = data.user.name;

    for (const comment of data.comments) {
      const commentId: string = comment.id;
      const commentContent: string = comment.content;
    }

    // Embedded resource
    if (data.metadata) {
      const category: string | null | undefined = data.metadata.category;
    }

    // Self calculation
    if (data.self) {
      const selfId: string = data.self.id;
      const selfTitle: string = data.self.title;
    }
  }
}

// Test 11: Verify result type is T | null (not T[]) for nullable get actions
// This is a compile-time type check to ensure get actions with not_found_error?: false return T | null
type GetSingleTodoNullableFieldsTest = ["id", "title"];
type ExpectedNullableResultType =
  InferGetSingleTodoNullableResult<GetSingleTodoNullableFieldsTest>;

// This should compile - the result can be null when not_found_error?: false
const nullableResult: ExpectedNullableResultType = null;

// Test 12: Verify input is now optional (get? doesn't require primary key)
export const getSingleTodoOptionalInput = await getSingleTodo({
  fields: ["id", "title"],
});

if (
  getSingleTodoOptionalInput.success &&
  getSingleTodoOptionalInput.data !== null
) {
  const todoId: string = getSingleTodoOptionalInput.data.id;
  const todoTitle: string = getSingleTodoOptionalInput.data.title;
}

console.log("Get tests should compile successfully!");
