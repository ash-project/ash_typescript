// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Load Restrictions Tests - shouldPass

import {
  listTodosDenyUser,
  listTodosAllowOnlyUser,
  listTodosAllowNested,
  listTodosDenyNested,
} from "../generated";

export const denyUserCanSelectComments = await listTodosDenyUser({
  fields: [
    "id",
    "title",
    {
      comments: ["id", "content"],
    },
  ],
});

if (denyUserCanSelectComments.success) {
  const todos = denyUserCanSelectComments.data;
  if (todos.length > 0) {
    const id: string = todos[0].id;
    const title: string = todos[0].title;
    const comments = todos[0].comments;
    if (comments && comments.length > 0) {
      const commentId: string = comments[0].id;
      const content: string = comments[0].content;
    }
  }
}

export const allowOnlyUserCanSelectUser = await listTodosAllowOnlyUser({
  fields: [
    "id",
    "title",
    {
      user: ["id", "email"],
    },
  ],
});

if (allowOnlyUserCanSelectUser.success) {
  const todos = allowOnlyUserCanSelectUser.data;
  if (todos.length > 0) {
    const id: string = todos[0].id;
    const title: string = todos[0].title;
    const user = todos[0].user;
    if (user) {
      const userId: string = user.id;
      const email: string = user.email;
    }
  }
}

export const allowNestedCanSelectAllowed = await listTodosAllowNested({
  fields: [
    "id",
    "title",
    {
      user: ["id", "email"],
    },
    {
      comments: [
        "id",
        "content",
        {
          todo: ["id", "title"],
        },
      ],
    },
  ],
});

if (allowNestedCanSelectAllowed.success) {
  const todos = allowNestedCanSelectAllowed.data;
  if (todos.length > 0) {
    const id: string = todos[0].id;
    const user = todos[0].user;
    const comments = todos[0].comments;
    if (comments && comments.length > 0) {
      const commentId: string = comments[0].id;
      const commentTodo = comments[0].todo;
      if (commentTodo) {
        const todoId: string = commentTodo.id;
        const todoTitle: string = commentTodo.title;
      }
    }
  }
}

export const denyNestedCanSelectComments = await listTodosDenyNested({
  fields: [
    "id",
    "title",
    {
      comments: ["id", "content"],
    },
  ],
});

if (denyNestedCanSelectComments.success) {
  const todos = denyNestedCanSelectComments.data;
  if (todos.length > 0) {
    const id: string = todos[0].id;
    const comments = todos[0].comments;
    if (comments && comments.length > 0) {
      const commentId: string = comments[0].id;
      const content: string = comments[0].content;
    }
  }
}

export const denyUserPrimitivesOnly = await listTodosDenyUser({
  fields: ["id", "title", "description", "status"],
});

if (denyUserPrimitivesOnly.success) {
  const todos = denyUserPrimitivesOnly.data;
  if (todos.length > 0) {
    const id: string = todos[0].id;
    const title: string = todos[0].title;
    const description: string | null = todos[0].description;
    const status: string | null = todos[0].status;
  }
}

export const allowOnlyUserPrimitivesOnly = await listTodosAllowOnlyUser({
  fields: ["id", "title", "priority"],
});

if (allowOnlyUserPrimitivesOnly.success) {
  const todos = allowOnlyUserPrimitivesOnly.data;
  if (todos.length > 0) {
    const id: string = todos[0].id;
    const title: string = todos[0].title;
    const priority: "low" | "medium" | "high" | "urgent" | null =
      todos[0].priority;
  }
}

// ============================================================================
// PAGINATION SCENARIOS
// ============================================================================

export const denyUserWithPagination = await listTodosDenyUser({
  fields: [
    "id",
    "title",
    {
      comments: ["id", "content"],
    },
  ],
  page: { offset: 0, limit: 10 },
});

if (denyUserWithPagination.success) {
  const hasMore: boolean = denyUserWithPagination.data.hasMore;
  const results = denyUserWithPagination.data.results;
  const count: number = denyUserWithPagination.data.count
    ? denyUserWithPagination.data.count
    : 0;

  if (results.length > 0) {
    const id: string = results[0].id;
    const title: string = results[0].title;
    const comments = results[0].comments;
    if (comments && comments.length > 0) {
      const commentId: string = comments[0].id;
      const content: string = comments[0].content;
    }
  }
}

export const allowOnlyUserWithAfterPagination = await listTodosAllowOnlyUser({
  fields: [
    "id",
    "title",
    {
      user: ["id", "email"],
    },
  ],
  page: { after: "some-cursor", limit: 20 },
});

if (allowOnlyUserWithAfterPagination.success) {
  const hasMore: boolean = allowOnlyUserWithAfterPagination.data.hasMore;
  const results = allowOnlyUserWithAfterPagination.data.results;

  for (const todo of results) {
    const id: string = todo.id;
    const title: string = todo.title;
    const user = todo.user;
    if (user) {
      const userId: string = user.id;
      const email: string = user.email;
    }
  }
}

export const allowNestedWithPagination = await listTodosAllowNested({
  fields: [
    "id",
    "title",
    {
      user: ["id", "email"],
    },
    {
      comments: [
        "id",
        "content",
        {
          todo: ["id", "title"],
        },
      ],
    },
  ],
  page: { offset: 5, limit: 15 },
});

if (allowNestedWithPagination.success) {
  const hasMore: boolean = allowNestedWithPagination.data.hasMore;
  const results = allowNestedWithPagination.data.results;

  for (const todo of results) {
    const id: string = todo.id;
    const user = todo.user;
    const comments = todo.comments;
    if (comments && comments.length > 0) {
      const commentId: string = comments[0].id;
      const commentTodo = comments[0].todo;
      if (commentTodo) {
        const todoId: string = commentTodo.id;
        const todoTitle: string = commentTodo.title;
      }
    }
  }
}

export const denyNestedWithBeforePagination = await listTodosDenyNested({
  fields: [
    "id",
    "title",
    {
      comments: ["id", "content"],
    },
  ],
  page: { before: "another-cursor", limit: 10 },
});

if (denyNestedWithBeforePagination.success) {
  const hasMore: boolean = denyNestedWithBeforePagination.data.hasMore;
  const results = denyNestedWithBeforePagination.data.results;

  for (const todo of results) {
    const id: string = todo.id;
    const title: string = todo.title;
    const comments = todo.comments;
    if (comments && comments.length > 0) {
      const commentId: string = comments[0].id;
      const content: string = comments[0].content;
    }
  }
}

export const denyUserEmptyPage = await listTodosDenyUser({
  fields: ["id", "title", { comments: ["id"] }],
  page: {},
});

if (denyUserEmptyPage.success) {
  const todos = denyUserEmptyPage.data;
  if (todos.length > 0) {
    const id: string = todos[0].id;
    const title: string = todos[0].title;
  }
}

export const allowOnlyUserWithCount = await listTodosAllowOnlyUser({
  fields: ["id", "title", { user: ["id"] }],
  page: { offset: 0, limit: 5, count: true },
});

if (allowOnlyUserWithCount.success) {
  const hasMore: boolean = allowOnlyUserWithCount.data.hasMore;
  const results = allowOnlyUserWithCount.data.results;
  const count: number = allowOnlyUserWithCount.data.count
    ? allowOnlyUserWithCount.data.count
    : 0;

  for (const todo of results) {
    const id: string = todo.id;
    const title: string = todo.title;
    const user = todo.user;
    if (user) {
      const userId: string = user.id;
    }
  }
}

console.log("Load restriction tests should compile successfully!");
