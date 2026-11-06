// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Restricted schemas agree with the runtime - shouldFail
//
// One load per restricted rpc_action of the test domain that the types
// reject. `restricted_schema_agreement_test.exs` sends each call's `fields`
// through ash_rpc's `Pipeline.parse_request` and expects a load_denied or
// load_not_allowed error, so each call holds exactly one rejected load and
// stays in the form `export const x = await <function>({ ... });`, with
// JSON-compatible literals.

import {
  listTodosAllowEmbedded,
  listTodosAllowFlatEmbedded,
  listTodosAllowHistory,
  listTodosAllowNested,
  listTodosAllowNestedCalc,
  listTodosAllowOnlyUser,
  listTodosAllowUnionMember,
  listTodosDenyAggregateEmbedded,
  listTodosDenyBareFields,
  listTodosDenyBlockMember,
  listTodosDenyEmbedded,
  listTodosDenyHistoryCalc,
  listTodosDenyMappedCalc,
  listTodosDenyNested,
  listTodosDenyNestedCalc,
  listTodosDenySelfUser,
  listTodosDenyUnionMember,
  listTodosDenyUser,
  listUsersDenyMappedCalc,
} from "../generated";

export const allowEmbedded = await listTodosAllowEmbedded({
  fields: [
    "id",
    {
      metadata: [
        // @ts-expect-error - only displayCategory is allowed on metadata
        "isOverdue",
      ],
    },
  ],
});

export const allowFlatEmbedded = await listTodosAllowFlatEmbedded({
  fields: [
    "id",
    {
      metadata: [
        // @ts-expect-error - a flat allow gives the attributes only
        "displayCategory",
      ],
    },
  ],
});

export const allowHistory = await listTodosAllowHistory({
  fields: [
    "id",
    {
      // @ts-expect-error - only displayCategory is allowed on metadataHistory
      metadataHistory: ["isOverdue"],
    },
  ],
});

export const allowNested = await listTodosAllowNested({
  fields: [
    "id",
    {
      comments: [
        "id",
        // @ts-expect-error - only todo is allowed on comments
        "weightedScore",
      ],
    },
  ],
});

// A load inside a union member of a resource typed with its attributes only
// (todo is a flat allowed relationship under comments).
export const allowNestedDeepUnion = await listTodosAllowNested({
  fields: [
    "id",
    {
      comments: [
        "id",
        {
          todo: [
            "id",
            {
              content: [
                {
                  text: [
                    "text",
                    // @ts-expect-error - todo keeps its attributes only, union members included
                    "displayText",
                  ],
                },
              ],
            },
          ],
        },
      ],
    },
  ],
});

// A load inside a union member of an attribute the nested allow doesn't name.
export const allowNestedCommentUnion = await listTodosAllowNested({
  fields: [
    "id",
    {
      comments: [
        "id",
        {
          authorInfo: [
            {
              metadata: [
                "category",
                // @ts-expect-error - authorInfo is not named, so its members keep their attributes only
                "displayCategory",
              ],
            },
          ],
        },
      ],
    },
  ],
});

export const allowNestedCalc = await listTodosAllowNestedCalc({
  fields: [
    "id",
    {
      comments: [
        "id",
        // @ts-expect-error - only weightedScore is allowed on comments
        { todo: ["id"] },
      ],
    },
  ],
});

// A load under an embedded attribute the allow list doesn't name.
export const allowOnlyUserEmbedded = await listTodosAllowOnlyUser({
  fields: [
    "id",
    {
      metadata: [
        "category",
        // @ts-expect-error - metadata is not named, so it keeps its attributes only
        "displayCategory",
      ],
    },
  ],
});

// A load under a union attribute the allow list doesn't name.
export const allowOnlyUserUnion = await listTodosAllowOnlyUser({
  fields: [
    "id",
    {
      content: [
        {
          text: [
            "text",
            // @ts-expect-error - content is not named, so its members keep their attributes only
            "displayText",
          ],
        },
      ],
    },
  ],
});

export const allowUnionMember = await listTodosAllowUnionMember({
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

export const denyAggregateEmbedded = await listTodosDenyAggregateEmbedded({
  fields: [
    "id",
    {
      firstCommentMetadata: [
        "category",
        // @ts-expect-error - displayCategory is denied under firstCommentMetadata
        "displayCategory",
      ],
    },
  ],
});

export const denyBareFields = await listTodosDenyBareFields({
  fields: [
    "id",
    {
      metadata: [
        "category",
        // @ts-expect-error - the loads under a bare denied attribute are denied
        "displayCategory",
      ],
    },
  ],
});

export const denyBareFieldsMember = await listTodosDenyBareFields({
  fields: [
    "id",
    {
      content: [
        {
          text: [
            "text",
            // @ts-expect-error - the loads under a bare denied member are denied
            "displayText",
          ],
        },
      ],
    },
  ],
});

export const denyBlockMember = await listTodosDenyBlockMember({
  fields: [
    "id",
    {
      blocks: [
        {
          text: [
            // @ts-expect-error - displayText is denied on the text member of blocks
            "displayText",
          ],
        },
      ],
    },
  ],
});

export const denyEmbedded = await listTodosDenyEmbedded({
  fields: [
    "id",
    {
      metadata: [
        // @ts-expect-error - displayCategory is denied on metadata
        "displayCategory",
      ],
    },
  ],
});

export const denyHistoryCalc = await listTodosDenyHistoryCalc({
  fields: [
    "id",
    {
      // @ts-expect-error - displayCategory is denied on metadataHistory
      metadataHistory: ["displayCategory"],
    },
  ],
});

export const denyMappedCalc = await listTodosDenyMappedCalc({
  fields: [
    "id",
    {
      user: [
        "id",
        // @ts-expect-error - isActive is denied on user
        "isActive",
      ],
    },
  ],
});

export const denyNested = await listTodosDenyNested({
  fields: [
    "id",
    {
      comments: [
        "id",
        // @ts-expect-error - todo is denied on comments
        { todo: ["id"] },
      ],
    },
  ],
});

export const denyNestedCalc = await listTodosDenyNestedCalc({
  fields: [
    "id",
    {
      comments: [
        "id",
        // @ts-expect-error - weightedScore is denied on comments
        "weightedScore",
      ],
    },
  ],
});

export const denySelfUser = await listTodosDenySelfUser({
  fields: [
    "id",
    {
      self: {
        args: { prefix: "x" },
        fields: [
          "id",
          // @ts-expect-error - user is denied under self
          { user: ["id"] },
        ],
      },
    },
  ],
});

export const denyUnionMember = await listTodosDenyUnionMember({
  fields: [
    "id",
    {
      content: [
        {
          text: [
            // @ts-expect-error - displayText is denied on the text member of content
            "displayText",
          ],
        },
      ],
    },
  ],
});

export const denyUser = await listTodosDenyUser({
  fields: [
    "id",
    {
      // @ts-expect-error - user is denied
      user: ["id"],
    },
  ],
});

export const usersDenyMappedCalc = await listUsersDenyMappedCalc({
  fields: [
    "id",
    // @ts-expect-error - isActive is denied
    "isActive",
  ],
});
