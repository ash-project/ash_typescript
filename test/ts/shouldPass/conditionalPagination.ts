// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Conditional Pagination Tests - shouldPass
// Tests for optional pagination behavior where types match runtime behavior

import { listTodos } from "../generated";

// Test 1: List without page parameter - should return Array<T>
export const listWithoutPage = await listTodos({
  input: {},
  fields: ["id", "title", "completed"],
});

// Type validation: result should be an array
if (listWithoutPage.success) {
  // Should be Array<T>, not paginated structure
  const todos: Array<any> = listWithoutPage.data;
  const firstTodo = todos[0];
  const todoId: string = firstTodo.id;
  const todoTitle: string = firstTodo.title;
  const todoCompleted: boolean | null | undefined = firstTodo.completed;

  // Should NOT have pagination fields
  // @ts-expect-error - data should be array, not paginated structure
  const hasMore = listWithoutPage.data.hasMore;
}

// Test 2: List with empty page object - should return Array<T>
export const listWithEmptyPage = await listTodos({
  input: {},
  fields: ["id", "title"],
  page: {},
});

// Type validation: result should still be an array
if (listWithEmptyPage.success) {
  // Should be Array<T>, not paginated structure
  const todos: Array<any> = listWithEmptyPage.data;
  const firstTodo = todos[0];
  const todoId: string = firstTodo.id;

  // Should NOT have pagination fields
  // @ts-expect-error - data should be array, not paginated structure
  const hasMore = listWithEmptyPage.data.hasMore;
}

// Test 3: List with offset pagination - should return paginated structure
export const listWithOffset = await listTodos({
  input: {},
  fields: ["id", "title", "description"],
  page: { offset: 0, limit: 10 },
});

// Type validation: result should be paginated structure
if (listWithOffset.success) {
  // Should have pagination fields
  const hasMore: boolean = listWithOffset.data.hasMore;
  const results: Array<any> = listWithOffset.data.results;
  const count: number = listWithOffset.data.count
    ? listWithOffset.data.count
    : 0;

  // Validate result items
  const firstTodo = results[0];
  const todoId: string = firstTodo.id;
  const todoTitle: string = firstTodo.title;
  const todoDescription: string | null | undefined = firstTodo.description;

  const directAccess: {
    id: string;
    title: string;
    description: string | null | undefined;
  } = listWithOffset.data.results[0];
}

// Test 4: List with keyset pagination (after) - should return paginated structure
export const listWithAfter = await listTodos({
  input: {},
  fields: ["id", "title", "status"],
  page: { after: "some-cursor", limit: 20 },
});

// Type validation: result should be paginated structure
if (listWithAfter.success) {
  const hasMore: boolean = listWithAfter.data.hasMore;
  const results: Array<any> = listWithAfter.data.results;

  // Validate result items
  for (const todo of results) {
    const todoId: string = todo.id;
    const todoTitle: string = todo.title;
    const todoStatus: string | null | undefined = todo.status;
  }

  // Should NOT be directly an array
  // @ts-expect-error - data should be paginated structure, not array
  const directAccess = listWithAfter.data[0];
}

// Test 5: List with keyset pagination (before) - should return paginated structure
export const listWithBefore = await listTodos({
  input: {},
  fields: ["id", "title", "priority"],
  page: { before: "some-cursor", limit: 15 },
});

// Type validation: result should be paginated structure
if (listWithBefore.success) {
  const hasMore: boolean = listWithBefore.data.hasMore;
  const results: Array<any> = listWithBefore.data.results;

  // Validate result items
  for (const todo of results) {
    const todoId: string = todo.id;
    const todoTitle: string = todo.title;
    const todoPriority: string | null | undefined = todo.priority;
  }
}

// Test 6: List with nested relationships and no pagination
export const listWithNestedNoPage = await listTodos({
  input: {},
  fields: [
    "id",
    "title",
    {
      user: ["id", "name", "email"],
      comments: ["id", "content"],
    },
  ],
});

// Type validation: result should be an array with nested data
if (listWithNestedNoPage.success) {
  const todos: Array<any> = listWithNestedNoPage.data;
  const firstTodo = todos[0];
  const userName: string = firstTodo.user.name;
  const userEmail: string = firstTodo.user.email;

  for (const comment of firstTodo.comments) {
    const commentId: string = comment.id;
    const commentContent: string = comment.content;
  }
}

// Test 7: List with nested relationships and offset pagination
export const listWithNestedAndPagination = await listTodos({
  input: {},
  fields: [
    "id",
    "title",
    {
      user: ["id", "name"],
      comments: ["id", "content"],
    },
  ],
  page: { offset: 0, limit: 5 },
});

// Type validation: result should be paginated structure with nested data
if (listWithNestedAndPagination.success) {
  const hasMore: boolean = listWithNestedAndPagination.data.hasMore;
  const results: Array<any> = listWithNestedAndPagination.data.results;

  for (const todo of results) {
    const todoId: string = todo.id;
    const userName: string = todo.user.name;

    for (const comment of todo.comments) {
      const commentId: string = comment.id;
    }
  }
}

// Test 8: List with input parameters and no pagination
export const listWithInputNoPage = await listTodos({
  input: {
    filterCompleted: true,
    priorityFilter: "high",
  },
  fields: ["id", "title", "completed"],
});

// Type validation: result should be an array
if (listWithInputNoPage.success) {
  const todos: Array<any> = listWithInputNoPage.data;
  const firstTodo = todos[0];
  const todoId: string = firstTodo.id;
}

// Test 9: List with input parameters and pagination
export const listWithInputAndPage = await listTodos({
  input: {
    filterCompleted: false,
  },
  fields: ["id", "title"],
  page: { offset: 10, limit: 20 },
});

// Type validation: result should be paginated structure
if (listWithInputAndPage.success) {
  const hasMore: boolean = listWithInputAndPage.data.hasMore;
  const results: Array<any> = listWithInputAndPage.data.results;
  const count: number = listWithInputAndPage.data.count
    ? listWithInputAndPage.data.count
    : 0;
}

console.log("Conditional pagination tests should compile successfully!");
