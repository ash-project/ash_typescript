// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Typed Controller Result Types Tests - shouldPass
// Tests for routes declaring `returns` — exported result types and typed responses

import {
  login,
  logout,
  updateProvider,
  search,
  searchPath,
  profile,
} from "../generated_routes";

import type {
  LoginResult,
  SearchResult,
  UpdateProviderResult,
  TypedControllerResponse,
} from "../generated_routes";

export async function testLoginResult() {
  const response = await login({ code: "abc" });

  if (response.ok) {
    const body: LoginResult = await response.json();
    const userId: string = body.userId;
    const rememberMe: boolean | null = body.rememberMe;
    const expiresAt: string | null = body.session.expiresAt;
    console.log(userId, rememberMe, expiresAt);
  } else {
    const errorBody: unknown = await response.json();
    console.log(errorBody, response.status);
  }

  // Non-body Response members stay accessible without narrowing
  console.log(response.status, response.headers.get("content-type"));
}

export async function testMappedFieldNames() {
  const response = await updateProvider(
    { provider: "github" },
    { enabled: true },
  );

  if (response.ok) {
    const body = await response.json();
    const field1: string = body.field1;
    const isActive: boolean = body.isActive;
    const line2: string | null = body.line2;
    console.log(field1, isActive, line2);
  }
}

// GET routes declaring `returns` get a fetch function built on their path helper
export async function testGetFetchFunction() {
  const response = await search(
    { q: "term", tags: ["elixir", "ash"] },
    { headers: { "X-Trace": "1" } },
  );

  if (response.ok) {
    const results: SearchResult = await response.json();

    for (const item of results) {
      const id: string = item.id;
      const tagNames: string[] = item.tagNames;
      console.log(id, tagNames);
    }
  }

  // All-optional query args make the query parameter optional
  const profileResponse = await profile();
  if (profileResponse.ok) {
    const body: Record<string, any> = await profileResponse.json();
    console.log(body);
  }
}

// The result type is still exported for fetching the path helper URL manually
export async function testGetRouteResult() {
  const response = await fetch(searchPath({ q: "term" }));
  const results = (await response.json()) as SearchResult;

  for (const item of results) {
    const id: string = item.id;
    const title: string | null = item.title;
    const tagNames: string[] = item.tagNames;
    console.log(id, title, tagNames);
  }
}

// Routes without `returns` keep resolving to a plain Response
export async function testUntypedRoute() {
  const response: Response = await logout();
  const body: unknown = await response.json();
  console.log(body);
}

// A typed response is still usable wherever a Response is expected
export async function testAssignableToResponse() {
  const response: TypedControllerResponse<UpdateProviderResult> =
    await updateProvider({ provider: "github" }, { enabled: false });
  const asResponse: Omit<Response, "json"> = response;
  console.log(asResponse.status);
}
