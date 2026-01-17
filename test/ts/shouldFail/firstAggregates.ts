// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// First Aggregates Complex Types Tests - shouldFail

import { getTodo } from "../generated";

export const cannotSelectSimpleCalculation = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: [
    "id",
    "title",
    {
      firstCommentMetadata: [
        "category",
        // @ts-expect-error - displayCategory is a calculation, not available in AttributesOnlySchema
        "displayCategory",
      ],
    },
  ],
});

export const cannotSelectBooleanCalculation = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: [
    "id",
    {
      firstCommentMetadata: [
        "category",
        // @ts-expect-error - isOverdue is a calculation, not available in AttributesOnlySchema
        "isOverdue",
      ],
    },
  ],
});

export const cannotSelectCalculationWithArgs = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: [
    "id",
    {
      firstCommentMetadata: [
        "priorityScore",
        // @ts-expect-error - adjustedPriority is a calculation, not available in AttributesOnlySchema
        { adjustedPriority: { args: { urgencyMultiplier: 1.5 }, fields: true } },
      ],
    },
  ],
});

export const cannotSelectFormattedSummary = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: [
    "id",
    {
      firstCommentMetadata: [
        "category",
        // @ts-expect-error - formattedSummary is a calculation, not available in AttributesOnlySchema
        { formattedSummary: { args: { format: "detailed" }, fields: true } },
      ],
    },
  ],
});

console.log("First aggregates fail tests should FAIL compilation!");
