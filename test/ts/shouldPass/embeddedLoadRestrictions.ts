// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Load restrictions through embedded resources - shouldPass

import {
  listTodosAllowEmbedded,
  listTodosAllowFlatEmbedded,
  listTodosAllowHistory,
  listTodosDenyEmbedded,
} from "../generated";

// allowed_loads: [metadata: [:display_category]]
export const allowEmbeddedCalc = await listTodosAllowEmbedded({
  fields: ["id", { metadata: ["category", "displayCategory"] }],
});

if (allowEmbeddedCalc.success && allowEmbeddedCalc.data.length > 0) {
  const metadata = allowEmbeddedCalc.data[0].metadata;
  if (metadata) {
    const category: string = metadata.category;
    const displayCategory: string | null | undefined = metadata.displayCategory;
  }
}

// denied_loads: [metadata: [:display_category]] - other calculations stay selectable
export const denyEmbeddedOtherCalc = await listTodosDenyEmbedded({
  fields: ["id", { metadata: ["category", "isOverdue"] }],
});

if (denyEmbeddedOtherCalc.success && denyEmbeddedOtherCalc.data.length > 0) {
  const metadata = denyEmbeddedOtherCalc.data[0].metadata;
  if (metadata) {
    const category: string = metadata.category;
  }
}

// allowed_loads: [:metadata] - the embedded attribute with its attributes
export const allowFlatEmbedded = await listTodosAllowFlatEmbedded({
  fields: ["id", { metadata: ["category", "priorityScore"] }],
});

// allowed_loads: [metadata_history: [:display_category]] - array of embedded
export const allowHistory = await listTodosAllowHistory({
  fields: ["id", { metadataHistory: ["category", "displayCategory"] }],
});

if (allowHistory.success && allowHistory.data.length > 0) {
  const history = allowHistory.data[0].metadataHistory;
  if (history && history.length > 0) {
    const category: string = history[0].category;
  }
}
