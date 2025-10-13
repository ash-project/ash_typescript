// SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
//
// SPDX-License-Identifier: MIT

// Custom Types Tests - shouldPass
// Tests for custom type field selection and usage

import { getTodo, createTodo } from "../generated";

// Test 0: Custom type field selection
export const customTypeTest = await getTodo({
  input: {},
  fields: ["id", "title", "priorityScore"],
});

// Type assertion: priorityScore should be number type (PriorityScore maps to number)
if (customTypeTest.success && customTypeTest.data?.priorityScore) {
  const score: number = customTypeTest.data.priorityScore;
  console.log(`Priority score: ${score}`);
}

// Test 0.1: ColorPalette custom type field selection
export const colorPaletteTest = await getTodo({
  input: {},
  fields: ["id", "title", "colorPalette"],
});

// Type assertion: colorPalette should be ColorPalette type (custom type with complex structure)
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
  fields: ["id", "title", "colorPalette", "createdAt"],
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

console.log("Custom types tests should compile successfully!");
