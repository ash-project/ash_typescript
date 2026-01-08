// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// No-Argument Calculations Tests - shouldPass
// Tests for calculations that return complex types but don't take arguments
// These use direct field selection syntax: { summary: ["field1", "field2"] }
// Unlike calculations with args which use: { self: { args: {...}, fields: [...] } }

import { listTodos, getTodo } from "../generated";

// Test 1: Basic field selection from no-argument calculation
export const basicNoArgCalc = await listTodos({
  fields: ["id", "title", { summary: ["viewCount", "editCount"] }],
});

// Type assertion for basic field selection
if (
  basicNoArgCalc.success &&
  basicNoArgCalc.data &&
  basicNoArgCalc.data.length > 0
) {
  const todo = basicNoArgCalc.data[0];
  const id: string = todo.id;
  const title: string = todo.title;

  if (todo.summary) {
    const viewCount: number | null = todo.summary.viewCount;
    const editCount: number | null = todo.summary.editCount;
  }
}

// Test 2: Nested field selection within no-argument calculation
export const nestedNoArgCalc = await listTodos({
  fields: [
    "id",
    {
      summary: [
        "viewCount",
        "completionTimeSeconds",
        { performanceMetrics: ["focusTimeSeconds", "efficiencyScore"] },
      ],
    },
  ],
});

// Type assertion for nested field selection
if (
  nestedNoArgCalc.success &&
  nestedNoArgCalc.data &&
  nestedNoArgCalc.data.length > 0
) {
  const todo = nestedNoArgCalc.data[0];

  if (todo.summary) {
    const viewCount: number | null = todo.summary.viewCount;
    const completionTimeSeconds: number | null =
      todo.summary.completionTimeSeconds;

    if (todo.summary.performanceMetrics) {
      const focusTime: number =
        todo.summary.performanceMetrics.focusTimeSeconds;
      const efficiency: number =
        todo.summary.performanceMetrics.efficiencyScore;
    }
  }
}

// Test 3: All fields from no-argument calculation including nested map
export const allFieldsNoArgCalc = await listTodos({
  fields: [
    "id",
    {
      summary: [
        "viewCount",
        "editCount",
        "completionTimeSeconds",
        "difficultyRating",
        "allCompleted",
        {
          performanceMetrics: [
            "focusTimeSeconds",
            "interruptionCount",
            "efficiencyScore",
            "taskComplexity",
          ],
        },
      ],
    },
  ],
});

// Type assertion for all fields
if (
  allFieldsNoArgCalc.success &&
  allFieldsNoArgCalc.data &&
  allFieldsNoArgCalc.data.length > 0
) {
  const todo = allFieldsNoArgCalc.data[0];

  if (todo.summary) {
    const viewCount: number | null = todo.summary.viewCount;
    const editCount: number | null = todo.summary.editCount;
    const completionTime: number | null = todo.summary.completionTimeSeconds;
    const difficulty: number | null = todo.summary.difficultyRating;
    const allCompleted: boolean | null = todo.summary.allCompleted;

    if (todo.summary.performanceMetrics) {
      const focusTime: number =
        todo.summary.performanceMetrics.focusTimeSeconds;
      const interruptions: number =
        todo.summary.performanceMetrics.interruptionCount;
      const efficiency: number =
        todo.summary.performanceMetrics.efficiencyScore;
      const complexity: string | null =
        todo.summary.performanceMetrics.taskComplexity;
    }
  }
}

// Test 4: No-argument calculation alongside with-argument calculation
export const mixedCalculations = await listTodos({
  fields: [
    "id",
    // No-argument calculation with field selection
    {
      summary: ["viewCount", "editCount"],
      // With-argument calculation with field selection
      self: {
        args: { prefix: "test" },
        fields: ["title", "completed"],
      },
    },
  ],
});

// Type assertion for mixed calculations
if (
  mixedCalculations.success &&
  mixedCalculations.data &&
  mixedCalculations.data.length > 0
) {
  const todo = mixedCalculations.data[0];

  // No-arg calculation result
  if (todo.summary) {
    const viewCount: number | null = todo.summary.viewCount;
    const editCount: number | null = todo.summary.editCount;
  }

  // With-arg calculation result
  if (todo.self) {
    const selfTitle: string = todo.self.title;
    const selfCompleted: boolean | null | undefined = todo.self.completed;
  }
}

// Test 5: No-argument calculation with get action
export const getWithNoArgCalc = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: [
    "id",
    "title",
    { summary: ["viewCount", { performanceMetrics: ["efficiencyScore"] }] },
  ],
});

// Type assertion for get action
if (getWithNoArgCalc.success && getWithNoArgCalc.data) {
  const todo = getWithNoArgCalc.data;

  if (todo.summary) {
    const viewCount: number | null = todo.summary.viewCount;

    if (todo.summary.performanceMetrics) {
      const efficiency: number =
        todo.summary.performanceMetrics.efficiencyScore;
    }
  }
}

// Test 6: statistics attribute (TypedStruct, not calculation) - same syntax
export const statisticsAttr = await listTodos({
  fields: [
    "id",
    {
      statistics: [
        "viewCount",
        "editCount",
        { performanceMetrics: ["focusTimeSeconds", "taskComplexity"] },
      ],
    },
  ],
});

// Type assertion for statistics attribute
if (
  statisticsAttr.success &&
  statisticsAttr.data &&
  statisticsAttr.data.length > 0
) {
  const todo = statisticsAttr.data[0];

  if (todo.statistics) {
    const viewCount: number | null = todo.statistics.viewCount;
    const editCount: number | null = todo.statistics.editCount;

    if (todo.statistics.performanceMetrics) {
      const focusTime: number =
        todo.statistics.performanceMetrics.focusTimeSeconds;
      const complexity: string | null =
        todo.statistics.performanceMetrics.taskComplexity;
    }
  }
}

console.log("No-argument calculations tests should compile successfully!");
