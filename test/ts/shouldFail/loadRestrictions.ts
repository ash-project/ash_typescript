// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Load Restrictions Tests - shouldFail

import {
  listTodosDenyUser,
  listTodosAllowOnlyUser,
  listTodosAllowNested,
  listTodosDenyNested,
} from "../generated";

export const denyUserCannotSelectUser = await listTodosDenyUser({
  fields: [
    "id",
    "title",
    {
      // @ts-expect-error - "user" is denied by denied_loads option
      user: ["id", "email"],
    },
  ],
});

export const allowOnlyUserCannotSelectComments = await listTodosAllowOnlyUser({
  fields: [
    "id",
    "title",
    {
      // @ts-expect-error - "comments" is not in allowed_loads list
      comments: ["id", "content"],
    },
  ],
});

export const allowOnlyUserCannotSelectSelf = await listTodosAllowOnlyUser({
  fields: [
    "id",
    "title",
    {
      // @ts-expect-error - "self" is not in allowed_loads list
      self: {
        args: { prefix: "test_" },
        fields: ["id", "title"],
      },
    },
  ],
});

export const allowOnlyUserCannotSelectNestedLoads = await listTodosAllowOnlyUser({
  fields: [
    "id",
    "title",
    {
      user: [
        "id",
        "email",
        // @ts-expect-error - nested loads on user are not allowed (user uses AttributesOnlySchema)
        { todos: ["id", "title"] },
      ],
    },
  ],
});

export const denyNestedCannotSelectCommentsTodo = await listTodosDenyNested({
  fields: [
    "id",
    "title",
    {
      comments: [
        "id",
        "content",
        {
          // @ts-expect-error - "todo" on comments is denied by nested denied_loads
          todo: ["id", "title"],
        },
      ],
    },
  ],
});

export const allowNestedCannotSelectCommentsUser = await listTodosAllowNested({
  fields: [
    "id",
    "title",
    {
      comments: [
        "id",
        "content",
        {
          // @ts-expect-error - "user" on comments is not in the nested allow list
          user: ["id", "email"],
        },
      ],
    },
  ],
});

export const allowNestedCannotSelectNotExposed = await listTodosAllowNested({
  fields: [
    "id",
    "title",
    {
      // @ts-expect-error - "notExposedItems" is not in allowed_loads
      notExposedItems: ["id"],
    },
  ],
});

console.log("Load restriction fail tests should FAIL compilation!");
