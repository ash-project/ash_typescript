// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Type Aliases Tests - shouldFail
// Aliases of field-bearing NewTypes keep their fields' shape.

import type {
  TaskStats,
  AshTypescriptTestTodoTimestampInput,
} from "../generated";

// @ts-expect-error - createdAt is required
const t: AshTypescriptTestTodoTimestampInput = { createdBy: "a" };

// @ts-expect-error - TaskStats needs every key
const s: TaskStats = {};

console.log(t, s);
