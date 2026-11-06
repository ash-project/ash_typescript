// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Load restrictions through embedded resources - shouldFail

import {
  listTodosAllowEmbedded,
  listTodosAllowFlatEmbedded,
  listTodosAllowHistory,
  listTodosDenyEmbedded,
} from "../generated";

export const denyEmbeddedCannotSelectDeniedCalc = await listTodosDenyEmbedded({
  fields: [
    "id",
    {
      metadata: [
        "category",
        // @ts-expect-error - displayCategory is denied by denied_loads: [metadata: [:display_category]]
        "displayCategory",
      ],
    },
  ],
});

export const allowEmbeddedCannotSelectOtherCalc = await listTodosAllowEmbedded({
  fields: [
    "id",
    {
      metadata: [
        "category",
        // @ts-expect-error - only displayCategory is allowed on metadata
        "isOverdue",
      ],
    },
  ],
});

export const allowFlatEmbeddedCannotSelectCalc = await listTodosAllowFlatEmbedded({
  fields: [
    "id",
    {
      metadata: [
        "category",
        // @ts-expect-error - a flat allow gives the attributes only
        "displayCategory",
      ],
    },
  ],
});

export const allowHistoryCannotSelectOtherCalc = await listTodosAllowHistory({
  fields: [
    "id",
    {
      // @ts-expect-error - only displayCategory is allowed on metadataHistory
      metadataHistory: ["category", "isOverdue"],
    },
  ],
});
