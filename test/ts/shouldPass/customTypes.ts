// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Custom Types Tests - shouldPass
// Tests for custom type field selection and usage

import {
  getTodo,
  createTodo,
  listTasks,
  createTask,
  echoLineItem,
} from "../generated";
import type {
  Money,
  Theme,
  ThemeInput,
  GeoPoint,
  ColorPalette,
  LineItem,
  LineItemInput,
} from "../generated";
import type { Decimal } from "../ash_types";

// Test 0: Custom type field selection
export const customTypeTest = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: ["id", "title", "priorityScore"],
});

// Type assertion: priorityScore should be number type (PriorityScore maps to number)
if (customTypeTest.success && customTypeTest.data?.priorityScore) {
  const score: number = customTypeTest.data.priorityScore;
  console.log(`Priority score: ${score}`);
}

// Test 0.1: ColorPalette custom type field selection
export const colorPaletteTest = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: ["id", "title", { colorPalette: ["primary", "secondary", "accent"] }],
});

// Type assertion: colorPalette is a typed map of its declared fields
if (colorPaletteTest.success && colorPaletteTest.data?.colorPalette) {
  const palette: { primary: string; secondary: string; accent: string } =
    colorPaletteTest.data.colorPalette;
  const primary: string = palette.primary;
  const secondary: string = palette.secondary;
  const accent: string = palette.accent;
  console.log(
    `Color palette: primary=${primary}, secondary=${secondary}, accent=${accent}`,
  );
}

// Test 5.1: Create operation with colorPalette custom type in input
export const createWithColorPalette = await createTodo({
  input: {
    title: "Color Palette Todo",
    status: "pending",
    userId: "user-id-123",
    colorPalette: {
      primary: "#FF5733",
      secondary: "#33FF57",
      accent: "#3357FF",
    },
  },
  fields: [
    "id",
    "title",
    { colorPalette: ["primary", "secondary", "accent"] },
    "createdAt",
  ],
});

// Type validation for created color palette todo
if (createWithColorPalette.success) {
  const createdColorPaletteId: string = createWithColorPalette.data.id;
  const createdColorPaletteTitle: string = createWithColorPalette.data.title;
  const createdAt: string = createWithColorPalette.data.createdAt;

  if (createWithColorPalette.data.colorPalette) {
    const createdPalette: {
      primary: string;
      secondary: string;
      accent: string;
    } = createWithColorPalette.data.colorPalette;
    const createdPrimary: string = createdPalette.primary;
    const createdSecondary: string = createdPalette.secondary;
    const createdAccent: string = createdPalette.accent;
  }
}

// Test 6: built-in Money (a declared map) is selected by sub-field
export const priceTest = await listTasks({
  fields: ["id", { price: ["currency", "amount"] }],
});

if (priceTest.success) {
  for (const task of priceTest.data) {
    // A selected Money result is assignable to the alias
    const price: Money | null = task.price;
    console.log(price);

    if (task.price) {
      const currency: string = task.price.currency;
      const amount: Decimal = task.price.amount;
      console.log(`Price: ${currency} ${amount}`);
    }
  }
}

// Test 7: a scalar member with its own TS mapping (HexColor) keeps it inside
// a declared custom type (Theme), in results and inputs
export const themeTest = await createTask({
  input: {
    title: "Themed",
    theme: { color: "#336699", code: "code-a1" },
  },
  fields: ["id", { theme: ["color", "accent"] }],
});

if (themeTest.success && themeTest.data.theme) {
  const color: `#${string}` = themeTest.data.theme.color;
  const accent: `#${string}` | null = themeTest.data.theme.accent;
  console.log(`Theme: ${color} ${accent}`);
}

// Test 8: declared custom types have exported aliases (Money, GeoPoint,
// ColorPalette, Theme, LineItem) and Input aliases where the input shape
// differs (ThemeInput, LineItemInput)

// An alias value is accepted as input
const money: Money = { currency: "NOK", amount: "10.00" };
export const pricedTask = await createTask({
  input: { title: "Priced", price: money },
  fields: ["id"],
});

const geoPoint: GeoPoint = { lat: 59.9, lng: 10.7 };
const palette: ColorPalette = {
  primary: "#FF5733",
  secondary: "#33FF57",
  accent: "#3357FF",
};
console.log(geoPoint, palette);

// ThemeInput omits nullable keys
const themeInput: ThemeInput = { color: "#336699", code: "code-a1" };
export const themedTask = await createTask({
  input: { title: "Themed", theme: themeInput },
  fields: ["id"],
});

// A full Theme is a ThemeInput
const fullTheme: Theme = {
  color: "#336699",
  accent: null,
  score: null,
  code: "code-a1",
  codes: null,
};
const asInput: ThemeInput = fullTheme;
console.log(asInput);

// LineItem: a nested declared type (Money) and an embedded resource
export const lineItemTest = await echoLineItem({
  input: { lineItem: { label: "A", price: money } },
  fields: ["label", { price: ["currency", "amount"] }],
});

if (lineItemTest.success) {
  const label: string = lineItemTest.data.label;
  const lineItemPrice: Money = lineItemTest.data.price;
  console.log(label, lineItemPrice);
}

const lineItemInput: LineItemInput = { label: "A", price: money };
const lineItem: LineItem = { label: "A", price: money, meta: null };
console.log(lineItemInput, lineItem);

// A Money filter value is writable: filter values are plain (no TypedMap
// markers) and reference the alias
export const moneyEqFilter = await listTasks({
  fields: ["id"],
  filter: { price: { eq: money } },
});
export const moneyInFilter = await listTasks({
  fields: ["id"],
  filter: { price: { in: [money] } },
});

console.log("Custom types tests should compile successfully!");
