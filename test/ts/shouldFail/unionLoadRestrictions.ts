// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Load restrictions through union members and a calculation returning a
// resource - shouldFail

import {
  listTodosAllowUnionMember,
  listTodosDenyBlockMember,
  listTodosDenySelfUser,
  listTodosDenyUnionMember,
} from "../generated";

export const denyUnionMemberCannotSelectDeniedCalc = await listTodosDenyUnionMember({
  fields: [
    "id",
    {
      content: [
        {
          text: [
            "text",
            // @ts-expect-error - displayText is denied by denied_loads: [content: [text: [:display_text]]]
            "displayText",
          ],
        },
      ],
    },
  ],
});

export const allowUnionMemberCannotSelectOtherCalc = await listTodosAllowUnionMember({
  fields: [
    "id",
    {
      content: [
        {
          text: [
            "text",
            // @ts-expect-error - only displayText is allowed on the text member
            "isFormatted",
          ],
        },
      ],
    },
  ],
});

export const allowUnionMemberCannotSelectOtherMemberCalc = await listTodosAllowUnionMember({
  fields: [
    "id",
    {
      content: [
        {
          checklist: [
            "title",
            // @ts-expect-error - members the entry doesn't name keep their attributes only
            "totalItems",
          ],
        },
      ],
    },
  ],
});

export const denyBlockMemberCannotSelectDeniedCalc = await listTodosDenyBlockMember({
  fields: [
    "id",
    {
      blocks: [
        {
          text: [
            "text",
            // @ts-expect-error - displayText is denied by denied_loads: [blocks: [text: [:display_text]]]
            "displayText",
          ],
        },
      ],
    },
  ],
});

export const denySelfUserCannotSelectUser = await listTodosDenySelfUser({
  fields: [
    "id",
    {
      self: {
        args: { prefix: "x" },
        fields: [
          "id",
          // @ts-expect-error - user is denied by denied_loads: [self: [:user]]
          { user: ["id"] },
        ],
      },
    },
  ],
});
