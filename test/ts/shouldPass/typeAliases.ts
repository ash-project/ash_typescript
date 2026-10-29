// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Type Aliases Tests - shouldPass
// Field-bearing NewTypes that opt into an alias: TaskStats (named by
// typescript_type_alias/0) and TodoTimestamp (a field-less map entry, joined
// name) are exported and referenced at input and plain positions.

import { listTasks, updateTask } from "../generated";
import type {
  TaskStats,
  TaskStatsInput,
  AshTypescriptTestTodoTimestamp,
  AshTypescriptTestTodoTimestampInput,
} from "../generated";

// A full selection of a NewType result is assignable to its alias
export const statsTest = await listTasks({
  fields: [
    "id",
    { stats: ["totalCount", "completed", "isUrgent", "averageDuration"] },
  ],
});

if (statsTest.success) {
  for (const task of statsTest.data) {
    const stats: TaskStats | null = task.stats;
    console.log(stats);
  }
}

// An input alias without nullable keys is accepted as input
const statsInput: TaskStatsInput = {};

export const updateStatsTest = await updateTask({
  identity: "00000000-0000-0000-0000-000000000001",
  input: { stats: statsInput },
  fields: ["id"],
});

// Filter values take the plain alias
export const statsFilterTest = await listTasks({
  fields: ["id"],
  filter: {
    stats: {
      eq: {
        totalCount: 1,
        completed: null,
        isUrgent: null,
        averageDuration: null,
      },
    },
  },
});

// The joined-name alias and its input alias
const timestampInput: AshTypescriptTestTodoTimestampInput = {
  createdBy: "a",
  createdAt: "2026-01-01T00:00:00Z",
};

const timestamp: AshTypescriptTestTodoTimestamp = {
  createdBy: "a",
  createdAt: "2026-01-01T00:00:00Z",
  updatedBy: null,
  updatedAt: null,
};

console.log(timestampInput, timestamp);
