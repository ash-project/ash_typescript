// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Typed Controller Result Types Tests - shouldFail
// Tests for invalid usage of route result types that should fail TypeScript compilation

import * as routes from "../generated_routes";
import { login, updateProvider, search } from "../generated_routes";
import type { LoginResult, SearchResult } from "../generated_routes";

export async function testBodyUntypedBeforeNarrowing() {
  const response = await login({ code: "abc" });

  // @ts-expect-error - body is only typed as LoginResult once `ok` is checked
  const body: LoginResult = await response.json();
  console.log(body);
}

export async function testErrorBodyIsNotResult() {
  const response = await login({ code: "abc" });

  if (!response.ok) {
    // @ts-expect-error - a failed response's body is unknown, not LoginResult
    const body: LoginResult = await response.json();
    console.log(body);
  }
}

export async function testWrongFieldTypes() {
  const response = await login({ code: "abc" });

  if (response.ok) {
    const body = await response.json();
    // @ts-expect-error - userId is a UUID string, not a number
    const userId: number = body.userId;
    // @ts-expect-error - snake_case keys are not part of the result type
    console.log(body.user_id, userId);
  }
}

export async function testUnmappedFieldName() {
  const response = await updateProvider({ provider: "github" }, { enabled: true });

  if (response.ok) {
    const body = await response.json();
    // @ts-expect-error - field_1 is mapped to field1 via typescript_field_names
    console.log(body.field_1);
  }
}

export function testResultShape(results: SearchResult) {
  // @ts-expect-error - tagNames is a non-nullable array
  const tagNames: null = results[0].tagNames;
  console.log(tagNames);
}

export async function testGetFetchFunctionOnlyWithReturns() {
  // @ts-expect-error - GET routes without `returns` only get a path helper
  await routes.providerPage({ provider: "github" });
  // @ts-expect-error - same for routes without any arguments
  await routes.auth();
}

export async function testGetFetchFunctionArgs() {
  // @ts-expect-error - q is a required query argument
  await search({ page: 1 });

  const response = await search({ q: "term" });
  // @ts-expect-error - the body is only typed once `ok` is checked
  const results: SearchResult = await response.json();
  console.log(results);
}
