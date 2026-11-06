// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
//
// SPDX-License-Identifier: MIT

// The rejection half of routeSchemas: the route schemas require their
// required arguments, and the Theme schema enforces its members' constraints.

import * as v from "valibot";
import {
  createTaskRouteValibotSchema,
  loginValibotSchema,
  ThemeValibotSchema,
} from "../../ash_valibot";

function expectValiError(fn: () => unknown, message: string) {
  try {
    fn();
  } catch (error) {
    if (error instanceof v.ValiError) return error.issues;
    throw error;
  }
  throw new Error(message);
}

export function testLoginRouteSchemaRejectsMissingCode() {
  return expectValiError(
    () => v.parse(loginValibotSchema, {}),
    "Should have thrown for a login without code",
  );
}

export function testCreateTaskRouteSchemaRejectsMissingTitle() {
  return expectValiError(
    () => v.parse(createTaskRouteValibotSchema, { metadata: {} }),
    "Should have thrown for a createTask without title",
  );
}

export function testThemeSchemaRejectsNonHexColor() {
  return expectValiError(
    () => v.parse(ThemeValibotSchema, { color: "red", code: "code-42" }),
    "Should have thrown for a color that is not a hex color",
  );
}

export function testThemeSchemaRejectsCodeWithoutPrefix() {
  return expectValiError(
    () => v.parse(ThemeValibotSchema, { color: "#a1b2c3", code: "42" }),
    "Should have thrown for an ExternalCode without its prefix",
  );
}
