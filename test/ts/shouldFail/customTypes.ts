// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Custom Types Tests - shouldFail
// Declared custom types are selected by sub-field, and their scalar members
// keep their own TS mapping in inputs.

import { createTask, listTasks } from "../generated";
import type {
  Money,
  Theme,
  ThemeInput,
  ReadTasksWithTypedMapMetadataMetadata,
} from "../generated";

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

// Declared custom type aliases keep their declared shapes

// @ts-expect-error - amount is required
export const noAmount: Money = { currency: "NOK" };

// @ts-expect-error - Theme needs every key
export const partial: Theme = { color: "#336699", code: "code-a1" };

const themeInputValue: ThemeInput = { color: "#336699", code: "code-a1" };
// @ts-expect-error - a ThemeInput isn't a Theme
export const notTheme: Theme = themeInputValue;

// Metadata values are plain data
type CompletionInfo = NonNullable<
  ReadTasksWithTypedMapMetadataMetadata["completionInfo"]
>;
// @ts-expect-error - metadata values carry no TypedMap markers
export const marker = ({} as CompletionInfo).__type;

console.log("Custom types tests should FAIL compilation!");
