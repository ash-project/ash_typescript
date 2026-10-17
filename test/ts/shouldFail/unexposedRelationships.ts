// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
//
// SPDX-License-Identifier: MIT

// Unexposed Relationship Tests - shouldFail
// A relationship to a resource without the AshTypescript.Resource extension is
// not selectable or filterable: the runtime rejects it (unknown_field)

import { listTodos } from "../generated";

export const selectUnexposedRelationship = await listTodos({
  fields: [
    "id",
    {
      // @ts-expect-error - notExposedItems targets an unexposed resource
      notExposedItems: ["id"],
    },
  ],
});

export const filterUnexposedRelationship = await listTodos({
  fields: ["id"],
  filter: {
    // @ts-expect-error - notExposedItems targets an unexposed resource
    notExposedItems: { name: { eq: "x" } },
  },
});
