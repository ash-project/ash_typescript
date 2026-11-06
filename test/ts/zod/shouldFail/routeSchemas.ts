// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
//
// SPDX-License-Identifier: MIT

// The rejection half of routeSchemas: the route schemas require their
// required arguments, and the Theme schema enforces its members' constraints.

import { z } from "zod";
import { createTaskRouteZodSchema, loginZodSchema, ThemeZodSchema } from "../../ash_zod";

function expectZodError(fn: () => unknown, message: string) {
  try {
    fn();
  } catch (error) {
    if (error instanceof z.ZodError) return error.issues;
    throw error;
  }
  throw new Error(message);
}

export function testLoginRouteSchemaRejectsMissingCode() {
  return expectZodError(() => loginZodSchema.parse({}), "Should have thrown for a login without code");
}

export function testCreateTaskRouteSchemaRejectsMissingTitle() {
  return expectZodError(
    () => createTaskRouteZodSchema.parse({ metadata: {} }),
    "Should have thrown for a createTask without title",
  );
}

export function testThemeSchemaRejectsNonHexColor() {
  return expectZodError(
    () => ThemeZodSchema.parse({ color: "red", code: "code-42" }),
    "Should have thrown for a color that is not a hex color",
  );
}

export function testThemeSchemaRejectsCodeWithoutPrefix() {
  return expectZodError(
    () => ThemeZodSchema.parse({ color: "#a1b2c3", code: "42" }),
    "Should have thrown for an ExternalCode without its prefix",
  );
}
