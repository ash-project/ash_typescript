// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// The rejection half of customTypeSchemas: proves the resolved schemas actually
// enforce something, rather than being permissive shapes that accept anything.

import { z } from "zod";
import { createTodoZodSchema, createTaskZodSchema } from "../../ash_zod";

function expectZodError(fn: () => unknown, message: string) {
  try {
    fn();
  } catch (error) {
    if (error instanceof z.ZodError) {
      return error.issues;
    }
    throw error;
  }

  throw new Error(message);
}

// Storage-derived fallback: still rejects the wrong primitive.

export function testPriorityScoreStringRejected() {
  return expectZodError(
    () =>
      createTodoZodSchema.parse({
        title: "Bad",
        userId: "123e4567-e89b-12d3-a456-426614174000",
        priorityScore: "42",
      }),
    "Should have thrown for string priorityScore",
  );
}

// Overrides are enforced at runtime, not merely emitted.

export function testOverriddenCustomIdTooShort() {
  return expectZodError(
    () => createTaskZodSchema.parse({ title: "T", customId: "ab" }),
    "Should have thrown for customId shorter than the override minimum",
  );
}

export function testOverriddenGeoPointOutOfRange() {
  return expectZodError(
    () => createTaskZodSchema.parse({ title: "Nowhere", geoPoint: { lat: 999, lng: 10.75 } }),
    "Should have thrown for a latitude outside the override's range",
  );
}

// The decisive check that the override replaced the storage-derived schema:
// `z.record(z.string(), z.any())` would happily accept a half-built point.

export function testOverriddenGeoPointMissingField() {
  return expectZodError(
    () => createTaskZodSchema.parse({ title: "Partial", geoPoint: { lat: 59.91 } }),
    "Should have thrown for a geoPoint missing lng",
  );
}

console.log("Custom type schema failure tests should compile successfully!");
