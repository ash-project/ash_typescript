// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Runtime coverage for custom Ash types and the `zod` / `valibot` options of
// the test manifest's `custom_types` entries, which replace their generated
// schema.
//
// Kept separate from constraintValidation.ts: these assert how a *type* resolves
// to a schema, not how declared constraints are rendered.

import {
  createTodoZodSchema,
  createTaskZodSchema,
  LineItemZodSchema,
  MoneyZodSchema,
} from "../../ash_zod";

function createValidTodoData() {
  return {
    title: "Custom type test",
    userId: "123e4567-e89b-12d3-a456-426614174000",
  };
}

// ─── Storage-derived fallback ────────────────────────────────────────────────
//
// A hand-rolled `use Ash.Type` module with no override derives its schema from
// `storage_type/1`: PriorityScore stores `:integer` so it validates as a number
// (it previously collapsed to `z.string()` and rejected its own valid values).
// ColorPalette declares its fields (`typescript_fields/0`), so it validates as
// an object of them.

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

// ─── Entry schemas via imported schemas ──────────────────────────────────────
//
// Both entries name a schema authored in TypeScript, reached through
// `zod_import_into_generated`. See test/support/manifest.ex and
// config/config.exs.

// AshTypescript.Test.CustomIdentifier is a `scalar` entry whose `zod` names
// the schema; without it the entry's base type would only check for a string.

export function testOverriddenCustomIdAccepted() {
  const validated = createTaskZodSchema.parse({ title: "T", customId: "abc123" });

  if (validated.customId !== "abc123") {
    throw new Error("Expected customId to round-trip through validation");
  }

  return validated;
}

// AshTypescript.Test.GeoPoint is a `map` entry, so its generated schema would be
// an object of two numbers. The entry's `zod` — imported from a
// *subdirectory*, so the generated import path is not a same-directory
// sibling — replaces that with one that also checks the ranges.

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

// ─── Named schemas of declared custom types ─────────────────────────────────
//
// Every declared custom type without a `zod` replacement gets a named schema.
// LineItem references MoneyZodSchema (emitted before it) and the resource
// schema TaskMetadataZodSchema lazily (resource schemas come later in the
// file), so parsing it with `meta` proves the lazy reference resolves.

export function testMoneyZodSchemaAccepted() {
  const validated = MoneyZodSchema.parse({ currency: "NOK", amount: "1.00" });

  if (validated.currency !== "NOK" || validated.amount !== "1.00") {
    throw new Error("Expected Money to round-trip through its named schema");
  }

  return validated;
}

export function testLineItemZodSchemaAccepted() {
  const price = { currency: "NOK", amount: "1.00" };
  const withoutMeta = LineItemZodSchema.parse({ label: "Pen", price });

  if (withoutMeta.price.amount !== "1.00" || withoutMeta.meta !== undefined) {
    throw new Error("Expected a LineItem without meta to round-trip");
  }

  const withMeta = LineItemZodSchema.parse({ label: "Pen", price, meta: { createdBy: "me" } });

  if (withMeta.meta?.createdBy !== "me") {
    throw new Error("Expected LineItem.meta to round-trip through the lazy reference");
  }

  return withMeta;
}

console.log("Custom type schema tests should compile and pass successfully!");
