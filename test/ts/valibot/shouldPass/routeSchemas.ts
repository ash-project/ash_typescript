// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
//
// SPDX-License-Identifier: MIT

// Typed controller route schemas and the Theme schema (a typed map whose
// HexColor and ExternalCode members keep their own constraints) accept
// valid input.

import * as v from "valibot";
import {
  createTaskRouteValibotSchema,
  loginValibotSchema,
  ThemeValibotSchema,
} from "../../ash_valibot";

export function testLoginRouteSchemaAccepted() {
  const parsed = v.parse(loginValibotSchema, { code: "abc" });
  if (parsed.code !== "abc") throw new Error("Expected the login code to round-trip");
  return parsed;
}

export function testCreateTaskRouteSchemaAccepted() {
  const parsed = v.parse(createTaskRouteValibotSchema, {
    title: "Write tests",
    metadata: { notes: "soon", priorityLevel: 2 },
    priority: 3,
  });
  if (parsed.metadata.priorityLevel !== 2) throw new Error("Expected metadata to round-trip");
  return parsed;
}

export function testThemeSchemaAccepted() {
  const parsed = v.parse(ThemeValibotSchema, { color: "#a1b2c3", code: "code-42", codes: ["code-1"] });
  if (parsed.color !== "#a1b2c3") throw new Error("Expected the color to round-trip");
  return parsed;
}
