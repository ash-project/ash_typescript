// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Operations Tests - shouldPass
// Tests for basic CRUD operations (create, list, get, update)

import {
  getTodo,
  listTodos,
  createTodo,
  searchTodos,
  getStatisticsTodo,
} from "../generated";

// Test 4: List operation with nested self calculations
export const listWithNestedSelf = await listTodos({
  input: {},
  fields: [
    "id",
    "title",
    "completed",
    {
      self: {
        args: { prefix: "list_" },
        fields: [
          "id",
          "title",
          "status",
          "priority",
          {
            self: {
              args: { prefix: "list_nested_" },
              fields: [
                "description",
                "tags",
                {
                  metadata: ["category", "priorityScore"],
                },
              ],
            },
          },
        ],
      },
    },
  ],
});

// Type validation for list results with nested calculations
if (listWithNestedSelf.success) {
  for (const todo of listWithNestedSelf.data) {
    // Each todo should have the basic fields
    const todoId: string = todo.id;
    const todoTitle: string = todo.title;
    const todoCompleted: boolean | null | undefined = todo.completed;

    // Each todo should have the self calculation
    if (todo.self) {
      const selfStatus: string | null | undefined = todo.self.status;
      const selfPriority: string | null | undefined = todo.self.priority;

      // Each self should have the nested self calculation
      if (todo.self.self) {
        const nestedDescription: string | null | undefined =
          todo.self.self.description;
        const nestedTags: string[] | null | undefined = todo.self.self.tags;
        const nestedMetadata: Record<string, any> | null | undefined =
          todo.self.self.metadata;
      }
    }
  }
}

// Test 5: Create operation with nested self calculations in response
export const createWithNestedSelf = await createTodo({
  input: {
    title: "Test Todo",
    status: "pending",
    userId: "user-id-123",
  },
  fields: [
    "id",
    "title",
    "createdAt",
    {
      self: {
        args: { prefix: "created_" },
        fields: [
          "id",
          "title",
          "status",
          "userId",
          {
            self: {
              args: { prefix: "created_nested_" },
              fields: ["completed", "priority", "dueDate"],
            },
          },
        ],
      },
    },
  ],
});

// Type validation for created result
if (createWithNestedSelf.success) {
  const createdId: string = createWithNestedSelf.data.id;
  const createdTitle: string = createWithNestedSelf.data.title;

  if (createWithNestedSelf.data.self?.self) {
    const nestedCompleted: boolean | null | undefined =
      createWithNestedSelf.data.self.self.completed;
    const nestedPriority: string | null | undefined =
      createWithNestedSelf.data.self.self.priority;
    const nestedDueDate: string | null | undefined =
      createWithNestedSelf.data.self.self.dueDate;
  }
}

// Test 6: Read operations with input parameters
export const listWithInputParams = await listTodos({
  input: {
    filterCompleted: true,
    priorityFilter: "high",
  },
  fields: ["id", "title", "completed", "priority"],
});

// Type validation for list with input parameters
if (listWithInputParams.success) {
  for (const todo of listWithInputParams.data) {
    const todoId: string = todo.id;
    const todoTitle: string = todo.title;
    const todoCompleted: boolean | null | undefined = todo.completed;
    const todoPriority: string | null | undefined = todo.priority;
  }
}

// Test 7: Read operations with partial input parameters (optional fields)
export const listWithPartialInput = await listTodos({
  input: {
    filterCompleted: false,
    // priorityFilter is optional and omitted
  },
  fields: ["id", "title", "status"],
});

// Test 8: Read operations with no input parameters (should still work)
export const listWithoutInput = await listTodos({
  input: {},
  fields: ["id", "title"],
});

const searchTodosResult = await searchTodos({
  input: {
    query: "example",
  },
  fields: [
    "id",
    "title",
    { comments: ["id", "content"], user: ["id", "email"] },
  ],
});

if (searchTodosResult.success) {
  const id: string = searchTodosResult.data[0].id;
  const userEmail: string = searchTodosResult.data[0].user.email;
}

const getStatisticsTodoResult = await getStatisticsTodo({
  fields: ["completed", "pending"],
});

if (getStatisticsTodoResult.success) {
  const completed: number = getStatisticsTodoResult.data.completed;
}

// Test 9: Get single todo with basic fields
export const getTodoBasic = await getTodo({
  input: {},
  fields: ["id", "title", "description", "completed", "status", "priority"],
});

// Type validation for getTodo result
if (getTodoBasic.success) {
  const todoId: string = getTodoBasic.data!.id;
  const todoTitle: string = getTodoBasic.data!.title;
  const todoDescription: string | null | undefined =
    getTodoBasic.data!.description;
  const todoCompleted: boolean | null | undefined =
    getTodoBasic.data!.completed;
  const todoStatus: string | null | undefined = getTodoBasic.data!.status;
  const todoPriority: string | null | undefined = getTodoBasic.data!.priority;
}

// Test 10: Get todo with relationships
export const getTodoWithRelations = await getTodo({
  input: {},
  fields: [
    "id",
    "title",
    {
      user: ["id", "name", "email"],
      comments: ["id", "content", "authorName"],
    },
  ],
});

// Type validation for getTodo with relationships
if (getTodoWithRelations.success) {
  const todoId: string = getTodoWithRelations.data!.id;
  const todoTitle: string = getTodoWithRelations.data!.title;
  const userName: string = getTodoWithRelations.data!.user.name;
  const userEmail: string = getTodoWithRelations.data!.user.email;

  for (const comment of getTodoWithRelations.data!.comments) {
    const commentId: string = comment.id;
    const commentContent: string = comment.content;
    const commentAuthor: string = comment.authorName;
  }
}

// Test 11: Get todo with self calculation
export const getTodoWithSelf = await getTodo({
  input: {},
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

// Type validation for getTodo with self calculation
if (getTodoWithSelf.success) {
  const todoId: string = getTodoWithSelf.data!.id;
  const todoTitle: string = getTodoWithSelf.data!.title;

  if (getTodoWithSelf.data!.self) {
    const selfId: string = getTodoWithSelf.data!.self.id;
    const selfTitle: string = getTodoWithSelf.data!.self.title;
    const selfDescription: string | null | undefined =
      getTodoWithSelf.data!.self.description;
    const selfCompleted: boolean | null | undefined =
      getTodoWithSelf.data!.self.completed;
  }
}

console.log("Operations tests should compile successfully!");
