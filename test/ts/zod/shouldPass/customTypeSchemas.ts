// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Runtime coverage for custom Ash types (manifest `kind: :unknown`) and the
// per-library schema mapping overrides that can replace their generated schema.
//
// Kept separate from constraintValidation.ts: these assert how a *type* resolves
// to a schema, not how declared constraints are rendered.

import { createTodoZodSchema, createTaskZodSchema } from "../../ash_zod";

function createValidTodoData() {
  return {
    title: "Custom type test",
    userId: "123e4567-e89b-12d3-a456-426614174000",
  };
}

// ─── Storage-derived fallback ────────────────────────────────────────────────
//
// A hand-rolled `use Ash.Type` module with no override derives its schema from
// `storage_type/1`: PriorityScore stores `:integer` so it validates as a number,
// ColorPalette stores `:map` so it validates as a record. Both previously
// collapsed to `z.string()` and rejected their own valid values.

export function testColorPaletteObjectAccepted() {
  const validated = createTodoZodSchema.parse({
    ...createValidTodoData(),
    colorPalette: { primary: "#fff", secondary: "#000", accent: "#f00" },
  });

  if (validated.colorPalette?.primary !== "#fff") {
    throw new Error("Expected colorPalette to round-trip through validation");
  }

  return validated;
}

export function testPriorityScoreNumberAccepted() {
  const validated = createTodoZodSchema.parse({
    ...createValidTodoData(),
    priorityScore: 42,
  });

  if (validated.priorityScore !== 42) {
    throw new Error("Expected priorityScore to round-trip as a number");
  }

  return validated;
}

// ─── Mapping overrides via imported schemas ──────────────────────────────────
//
// Both overrides name a schema authored in TypeScript, reached through
// `zod_import_into_generated`. See config/config.exs.

// AshTypescript.Test.CustomIdentifier has no `typescript_type_name`, so without
// its override it would generate `z.any()` and validate nothing at all.

export function testOverriddenCustomIdAccepted() {
  const validated = createTaskZodSchema.parse({ title: "T", customId: "abc123" });

  if (validated.customId !== "abc123") {
    throw new Error("Expected customId to round-trip through validation");
  }

  return validated;
}

// AshTypescript.Test.GeoPoint stores `:map`, so its storage-derived schema would
// be a permissive `z.record(z.string(), z.any())`. The override — imported from
// a *subdirectory*, so the generated import path is not a same-directory
// sibling — replaces that with a precise object schema.

export function testOverriddenGeoPointAccepted() {
  const validated = createTaskZodSchema.parse({
    title: "Oslo",
    geoPoint: { lat: 59.91, lng: 10.75 },
  });

  if (validated.geoPoint?.lat !== 59.91 || validated.geoPoint?.lng !== 10.75) {
    throw new Error("Expected geoPoint to round-trip through validation");
  }

  return validated;
}

console.log("Custom type schema tests should compile and pass successfully!");
