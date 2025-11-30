// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// GetBy Tests - shouldPass
// Tests for get_by RPC option - retrieving single resource by specified fields
// Note: get_by uses a separate getBy config field (not input) for the lookup fields

import {
  getUserByEmail,
  GetUserByEmailResult,
  InferGetUserByEmailResult,
  getUserByEmailNullable,
  InferGetUserByEmailNullableResult,
  getTodoByUserAndStatus,
  InferGetTodoByUserAndStatusResult,
  createUser,
  createTodo,
} from "../generated";

// Test 1: Basic get by email with simple fields - getBy is required
export const getUserByEmailBasic = await getUserByEmail({
  getBy: {
    email: "alice@example.com",
  },
  fields: ["id", "name", "email"],
});

// Type validation for basic get_by result
if (getUserByEmailBasic.success) {
  // Result should be single item or null (not an array)
  const data = getUserByEmailBasic.data;

  if (data !== null) {
    const userId: string = data.id;
    const userName: string = data.name;
    const userEmail: string = data.email;
  }
}

// Test 2: Get by email with additional fields
export const getUserByEmailWithActive = await getUserByEmail({
  getBy: {
    email: "bob@example.com",
  },
  fields: ["id", "name", "email", "active", "isSuperAdmin"],
});

// Type validation for get_by with more fields
if (getUserByEmailWithActive.success) {
  const data = getUserByEmailWithActive.data;

  if (data !== null) {
    const userId: string = data.id;
    const userName: string = data.name;
    const userEmail: string = data.email;
    const userActive: boolean | null | undefined = data.active;
    const isSuperAdmin: boolean | null | undefined = data.isSuperAdmin;
  }
}

// Test 3: Get by email with relationship fields (todos)
export const getUserByEmailWithTodos = await getUserByEmail({
  getBy: {
    email: "alice@example.com",
  },
  fields: [
    "id",
    "name",
    "email",
    {
      todos: ["id", "title", "completed", "status"],
    },
  ],
});

// Type validation for get_by with relationships
if (getUserByEmailWithTodos.success) {
  const data = getUserByEmailWithTodos.data;

  if (data !== null) {
    const userId: string = data.id;
    const userName: string = data.name;
    const userEmail: string = data.email;

    for (const todo of data.todos) {
      const todoId: string = todo.id;
      const todoTitle: string = todo.title;
      const todoCompleted: boolean | null | undefined = todo.completed;
      const todoStatus: string | null | undefined = todo.status;
    }
  }
}

// Test 4: Get by email with comments relationship
export const getUserByEmailWithComments = await getUserByEmail({
  getBy: {
    email: "alice@example.com",
  },
  fields: [
    "id",
    "name",
    {
      comments: ["id", "content", "authorName"],
    },
  ],
});

// Type validation for get_by with comments
if (getUserByEmailWithComments.success) {
  const data = getUserByEmailWithComments.data;

  if (data !== null) {
    for (const comment of data.comments) {
      const commentId: string = comment.id;
      const commentContent: string = comment.content;
      const authorName: string = comment.authorName;
    }
  }
}

// Test 5: Get by email with calculation fields
export const getUserByEmailWithCalculations = await getUserByEmail({
  getBy: {
    email: "alice@example.com",
  },
  fields: ["id", "name", "isActive"],
});

// Type validation for get_by with calculations
if (getUserByEmailWithCalculations.success) {
  const data = getUserByEmailWithCalculations.data;

  if (data !== null) {
    const userId: string = data.id;
    const userName: string = data.name;
    // isActive is a calculation (is_active? in Elixir)
    const isActive: boolean | null | undefined = data.isActive;
  }
}

// Test 6: Get by email with self calculation
export const getUserByEmailWithSelf = await getUserByEmail({
  getBy: {
    email: "alice@example.com",
  },
  fields: [
    "id",
    "name",
    {
      self: {
        args: { prefix: "user_" },
        fields: ["id", "name", "email"],
      },
    },
  ],
});

// Type validation for get_by with self calculation
if (getUserByEmailWithSelf.success) {
  const data = getUserByEmailWithSelf.data;

  if (data !== null && data.self) {
    const selfId: string = data.self.id;
    const selfName: string = data.self.name;
    const selfEmail: string = data.self.email;
  }
}

// Test 7: Get by email with nested self calculation
export const getUserByEmailWithNestedSelf = await getUserByEmail({
  getBy: {
    email: "alice@example.com",
  },
  fields: [
    "id",
    "name",
    {
      self: {
        args: { prefix: "outer_" },
        fields: [
          "id",
          "name",
          {
            self: {
              args: { prefix: "inner_" },
              fields: ["id", "email"],
            },
          },
        ],
      },
    },
  ],
});

// Type validation for nested self calculation
if (getUserByEmailWithNestedSelf.success) {
  const data = getUserByEmailWithNestedSelf.data;

  if (data !== null && data.self?.self) {
    const innerSelfId: string = data.self.self.id;
    const innerSelfEmail: string = data.self.self.email;
  }
}

// Test 8: Get by email with address field (field name mapping test)
export const getUserByEmailWithAddress = await getUserByEmail({
  getBy: {
    email: "alice@example.com",
  },
  fields: ["id", "name", "addressLine1"],
});

// Type validation for get_by with mapped field names
if (getUserByEmailWithAddress.success) {
  const data = getUserByEmailWithAddress.data;

  if (data !== null) {
    const userId: string = data.id;
    const userName: string = data.name;
    // addressLine1 is mapped from address_line_1
    const addressLine1: string | null | undefined = data.addressLine1;
  }
}

// Test 9: Get by email with multiple relationships
export const getUserByEmailWithMultipleRelationships = await getUserByEmail({
  getBy: {
    email: "alice@example.com",
  },
  fields: [
    "id",
    "name",
    "email",
    {
      todos: ["id", "title"],
      comments: ["id", "content"],
      posts: ["id"],
    },
  ],
});

// Type validation for get_by with multiple relationships
if (getUserByEmailWithMultipleRelationships.success) {
  const data = getUserByEmailWithMultipleRelationships.data;

  if (data !== null) {
    // Todos
    for (const todo of data.todos) {
      const todoId: string = todo.id;
      const todoTitle: string = todo.title;
    }

    // Comments
    for (const comment of data.comments) {
      const commentId: string = comment.id;
      const commentContent: string = comment.content;
    }

    // Posts
    for (const post of data.posts) {
      const postId: string = post.id;
    }
  }
}

// Test 10: Get by email with todos and their nested user
export const getUserByEmailWithNestedTodoUser = await getUserByEmail({
  getBy: {
    email: "alice@example.com",
  },
  fields: [
    "id",
    "name",
    {
      todos: [
        "id",
        "title",
        {
          user: ["id", "name"],
        },
      ],
    },
  ],
});

// Type validation for get_by with nested relationship
if (getUserByEmailWithNestedTodoUser.success) {
  const data = getUserByEmailWithNestedTodoUser.data;

  if (data !== null) {
    for (const todo of data.todos) {
      const todoId: string = todo.id;
      const todoTitle: string = todo.title;
      const todoUserName: string = todo.user.name;
    }
  }
}

// Test 11: Verify result type is T | null (not T[]) for nullable get_by actions
// This is a compile-time type check to ensure get_by actions with not_found_error?: false return T | null
type GetUserByEmailNullableFieldsTest = ["id", "name", "email"];
type ExpectedNullableResultType =
  InferGetUserByEmailNullableResult<GetUserByEmailNullableFieldsTest>;

// This should compile - the result can be null when not_found_error?: false
const nullableResult: ExpectedNullableResultType = null;

// Test 12: Verify getBy is required for get_by actions
// This is a compile-time type check - the following would fail to compile if getBy was optional:
// await getUserByEmail({ fields: ["id"] }); // Would fail - getBy is required

// Test 13: Complex get_by with everything
export const getUserByEmailComplex = await getUserByEmail({
  getBy: {
    email: "complex@example.com",
  },
  fields: [
    "id",
    "name",
    "email",
    "active",
    "isSuperAdmin",
    "addressLine1",
    "isActive",
    {
      todos: [
        "id",
        "title",
        "completed",
        "isOverdue",
        "commentCount",
        {
          user: ["id", "name"],
          comments: ["id", "content"],
        },
      ],
      comments: ["id", "content", "authorName"],
      self: {
        args: { prefix: "complex_" },
        fields: ["id", "name", "email"],
      },
    },
  ],
});

// Type validation for complex get_by
if (getUserByEmailComplex.success) {
  const data = getUserByEmailComplex.data;

  if (data !== null) {
    // Basic fields
    const userId: string = data.id;
    const userName: string = data.name;
    const userEmail: string = data.email;
    const userActive: boolean | null | undefined = data.active;
    const isSuperAdmin: boolean | null | undefined = data.isSuperAdmin;
    const addressLine1: string | null | undefined = data.addressLine1;

    // Calculation
    const isActive: boolean | null | undefined = data.isActive;

    // Todos relationship with nested data
    for (const todo of data.todos) {
      const todoId: string = todo.id;
      const todoTitle: string = todo.title;
      const isOverdue: boolean | null | undefined = todo.isOverdue;
      const commentCount: number = todo.commentCount;

      // Nested user
      const todoUserName: string = todo.user.name;

      // Nested comments
      for (const comment of todo.comments) {
        const commentId: string = comment.id;
        const commentContent: string = comment.content;
      }
    }

    // Direct comments relationship
    for (const comment of data.comments) {
      const commentId: string = comment.id;
      const authorName: string = comment.authorName;
    }

    // Self calculation
    if (data.self) {
      const selfId: string = data.self.id;
      const selfName: string = data.self.name;
      const selfEmail: string = data.self.email;
    }
  }
}

// =============================================================================
// Composite get_by Tests (multiple fields)
// =============================================================================

// Test 14: Basic composite get_by with userId and status
export const getTodoByUserAndStatusBasic = await getTodoByUserAndStatus({
  getBy: {
    userId: "00000000-0000-0000-0000-000000000001",
    status: "pending",
  },
  fields: ["id", "title", "status", "completed"],
});

// Type validation for composite get_by result
if (getTodoByUserAndStatusBasic.success) {
  // Result should be single item or null (not an array)
  const data = getTodoByUserAndStatusBasic.data;

  if (data !== null) {
    const todoId: string = data.id;
    const todoTitle: string = data.title;
    const todoStatus:
      | "pending"
      | "ongoing"
      | "finished"
      | "cancelled"
      | null
      | undefined = data.status;
    const todoCompleted: boolean | null | undefined = data.completed;
  }
}

// Test 15: Composite get_by with additional fields
export const getTodoByUserAndStatusWithPriority = await getTodoByUserAndStatus({
  getBy: {
    userId: "00000000-0000-0000-0000-000000000001",
    status: "pending",
  },
  fields: ["id", "title", "status", "priority", "dueDate"],
});

// Type validation for composite get_by with more fields
if (getTodoByUserAndStatusWithPriority.success) {
  const data = getTodoByUserAndStatusWithPriority.data;

  if (data !== null) {
    const todoId: string = data.id;
    const todoTitle: string = data.title;
    const todoStatus:
      | "pending"
      | "ongoing"
      | "finished"
      | "cancelled"
      | null
      | undefined = data.status;
    const todoPriority:
      | "low"
      | "medium"
      | "high"
      | "urgent"
      | null
      | undefined = data.priority;
    const todoDueDate: string | null | undefined = data.dueDate;
  }
}

// Test 16: Composite get_by with relationship fields
export const getTodoByUserAndStatusWithUser = await getTodoByUserAndStatus({
  getBy: {
    userId: "00000000-0000-0000-0000-000000000001",
    status: "pending",
  },
  fields: [
    "id",
    "title",
    "status",
    {
      user: ["id", "name", "email"],
    },
  ],
});

// Type validation for composite get_by with relationships
if (getTodoByUserAndStatusWithUser.success) {
  const data = getTodoByUserAndStatusWithUser.data;

  if (data !== null) {
    const todoId: string = data.id;
    const todoTitle: string = data.title;

    // Nested user relationship
    const userId: string = data.user.id;
    const userName: string = data.user.name;
    const userEmail: string = data.user.email;
  }
}

// Test 17: Composite get_by with comments relationship
export const getTodoByUserAndStatusWithComments = await getTodoByUserAndStatus({
  getBy: {
    userId: "00000000-0000-0000-0000-000000000001",
    status: "pending",
  },
  fields: [
    "id",
    "title",
    {
      comments: ["id", "content", "authorName"],
    },
  ],
});

// Type validation for composite get_by with comments
if (getTodoByUserAndStatusWithComments.success) {
  const data = getTodoByUserAndStatusWithComments.data;

  if (data !== null) {
    for (const comment of data.comments) {
      const commentId: string = comment.id;
      const commentContent: string = comment.content;
      const authorName: string = comment.authorName;
    }
  }
}

// Test 18: Composite get_by with calculation fields
export const getTodoByUserAndStatusWithCalculations =
  await getTodoByUserAndStatus({
    getBy: {
      userId: "00000000-0000-0000-0000-000000000001",
      status: "pending",
    },
    fields: ["id", "title", "isOverdue", "daysUntilDue", "commentCount"],
  });

// Type validation for composite get_by with calculations
if (getTodoByUserAndStatusWithCalculations.success) {
  const data = getTodoByUserAndStatusWithCalculations.data;

  if (data !== null) {
    const todoId: string = data.id;
    const todoTitle: string = data.title;
    const isOverdue: boolean | null | undefined = data.isOverdue;
    const daysUntilDue: number | null | undefined = data.daysUntilDue;
    const commentCount: number = data.commentCount;
  }
}

// Test 19: Composite get_by with self calculation
export const getTodoByUserAndStatusWithSelf = await getTodoByUserAndStatus({
  getBy: {
    userId: "00000000-0000-0000-0000-000000000001",
    status: "pending",
  },
  fields: [
    "id",
    "title",
    {
      self: {
        args: { prefix: "todo_" },
        fields: ["id", "title", "status"],
      },
    },
  ],
});

// Type validation for composite get_by with self calculation
if (getTodoByUserAndStatusWithSelf.success) {
  const data = getTodoByUserAndStatusWithSelf.data;

  if (data !== null && data.self) {
    const selfId: string = data.self.id;
    const selfTitle: string = data.self.title;
    const selfStatus:
      | "pending"
      | "ongoing"
      | "finished"
      | "cancelled"
      | null
      | undefined = data.self.status;
  }
}

// Test 20: Verify result type is T (not T[]) for composite get_by
// Note: This action uses default not_found_error?: true, so result is NOT nullable
// (errors are returned instead of null when not found)
type GetTodoByUserAndStatusFieldsTest = ["id", "title", "status"];
type ExpectedCompositeResultType =
  InferGetTodoByUserAndStatusResult<GetTodoByUserAndStatusFieldsTest>;

// Verify the type is a single object (not array) - this compiles because we're assigning a valid object shape
const compositeResultTypeCheck: ExpectedCompositeResultType = {
  id: "test-id",
  title: "Test Title",
  status: "pending",
};

// Test 21: Composite get_by with filter arguments (from the read action)
// getBy fields are separate from input - action arguments stay in input
export const getTodoByUserAndStatusWithFilter = await getTodoByUserAndStatus({
  getBy: {
    userId: "00000000-0000-0000-0000-000000000001",
    status: "pending",
  },
  input: {
    // These are optional arguments from the read action
    filterCompleted: false,
    priorityFilter: "high",
  },
  fields: ["id", "title", "status", "priority", "completed"],
});

// Type validation for composite get_by with action arguments
if (getTodoByUserAndStatusWithFilter.success) {
  const data = getTodoByUserAndStatusWithFilter.data;

  if (data !== null) {
    const todoId: string = data.id;
    const todoTitle: string = data.title;
    const todoPriority:
      | "low"
      | "medium"
      | "high"
      | "urgent"
      | null
      | undefined = data.priority;
    const todoCompleted: boolean | null | undefined = data.completed;
  }
}

// Test 22: Complex composite get_by with everything
export const getTodoByUserAndStatusComplex = await getTodoByUserAndStatus({
  getBy: {
    userId: "00000000-0000-0000-0000-000000000001",
    status: "pending",
  },
  input: {
    filterCompleted: false,
  },
  fields: [
    "id",
    "title",
    "description",
    "status",
    "priority",
    "completed",
    "dueDate",
    "isOverdue",
    "daysUntilDue",
    "commentCount",
    {
      user: ["id", "name", "email"],
      comments: ["id", "content", "authorName"],
      self: {
        args: { prefix: "complex_" },
        fields: ["id", "title"],
      },
    },
  ],
});

// Type validation for complex composite get_by
if (getTodoByUserAndStatusComplex.success) {
  const data = getTodoByUserAndStatusComplex.data;

  if (data !== null) {
    // Basic fields
    const todoId: string = data.id;
    const todoTitle: string = data.title;
    const todoDescription: string | null | undefined = data.description;
    const todoStatus:
      | "pending"
      | "ongoing"
      | "finished"
      | "cancelled"
      | null
      | undefined = data.status;
    const todoPriority:
      | "low"
      | "medium"
      | "high"
      | "urgent"
      | null
      | undefined = data.priority;
    const todoCompleted: boolean | null | undefined = data.completed;
    const todoDueDate: string | null | undefined = data.dueDate;

    // Calculations
    const isOverdue: boolean | null | undefined = data.isOverdue;
    const daysUntilDue: number | null | undefined = data.daysUntilDue;
    const commentCount: number = data.commentCount;

    // User relationship
    const userId: string = data.user.id;
    const userName: string = data.user.name;
    const userEmail: string = data.user.email;

    // Comments relationship
    for (const comment of data.comments) {
      const commentId: string = comment.id;
      const commentContent: string = comment.content;
      const authorName: string = comment.authorName;
    }

    // Self calculation
    if (data.self) {
      const selfId: string = data.self.id;
      const selfTitle: string = data.self.title;
    }
  }
}

console.log("GetBy tests should compile successfully!");
