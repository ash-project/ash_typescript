// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Custom Types Tests - shouldFail
// Declared custom types are selected by sub-field, and their scalar members
// keep their own TS mapping in inputs.

import { createTask, listTasks } from "../generated";

const plainString: string = "336699";

// A plain string isn't a HexColor (`#${string}`)
export const plainStringMember = await createTask({
  input: {
    title: "Themed",
    // @ts-expect-error - color is `#${string}`, not string
    theme: { color: plainString, code: "code-a1" },
  },
  fields: ["id"],
});

// A declared custom type can't be selected bare
export const barePrice = await listTasks({
  // @ts-expect-error - price needs a sub-field selection
  fields: ["id", "price"],
});

console.log("Custom types tests should FAIL compilation!");
