// Custom Fetch Tests - shouldFail
// Tests for invalid usage patterns of customFetch and fetchOptions

import {
  listTodos,
  createTodo,
} from "../generated";

// Test 1: Invalid customFetch function signature (wrong return type)
const invalidCustomFetch1 = async (
  input: RequestInfo | URL,
  init?: RequestInit
): Promise<string> => { // Should return Promise<Response>, not Promise<string>
  return "invalid";
};

export const testInvalidCustomFetch1 = await listTodos({
  input: {},
  fields: ["id", "title"],
  // @ts-expect-error - customFetch should return Promise<Response>, not Promise<string>
  customFetch: invalidCustomFetch1,
});

// Test 2: Invalid customFetch return type (return void instead of Promise<Response>)
const invalidCustomFetch2 = (input: RequestInfo | URL, init?: RequestInit) => {
  // Returns void, which is wrong
};

export const testInvalidCustomFetch2 = await createTodo({
  input: { title: "Test", userId: "user-123" },
  fields: ["id", "title"],
  // @ts-expect-error - customFetch should return Promise<Response>, not void
  customFetch: invalidCustomFetch2,
});

// Test 3: Invalid customFetch function signature (wrong parameter types)
const invalidCustomFetch3 = async (
  input: string, // Should be RequestInfo | URL
  init?: string  // Should be RequestInit
): Promise<Response> => {
  return new Response();
};

export const testInvalidCustomFetch3 = await listTodos({
  input: {},
  fields: ["id", "title"],
  // @ts-expect-error - customFetch parameters should be (RequestInfo | URL, RequestInit?)
  customFetch: invalidCustomFetch3,
});

// Test 4: Invalid fetchOptions type (wrong property types)
export const testInvalidFetchOptions1 = await listTodos({
  input: {},
  fields: ["id", "title"],
  fetchOptions: {
    // @ts-expect-error - method should be string, not number
    method: 123,
    // @ts-expect-error - headers should be HeadersInit, not string
    headers: "invalid",
  },
});

// Test 5: Invalid fetchOptions type (non-existent properties)
export const testInvalidFetchOptions2 = await createTodo({
  input: { title: "Test", userId: "user-123" },
  fields: ["id", "title"],
  fetchOptions: {
    // @ts-expect-error - invalidProperty doesn't exist on RequestInit
    invalidProperty: "should not exist",
    anotherInvalid: true,
  },
});

// Test 6: Passing non-function as customFetch
export const testNonFunctionCustomFetch = await listTodos({
  input: {},
  fields: ["id", "title"],
  // @ts-expect-error - customFetch should be a function, not a string
  customFetch: "not a function",
});

// Test 7: Passing null incorrectly
export const testNullCustomFetch = await listTodos({
  input: {},
  fields: ["id", "title"],
  // @ts-expect-error - customFetch should be undefined or a valid function, not null
  customFetch: null,
});

// Test 8: Invalid fetchOptions with wrong signal type
export const testInvalidSignal = await listTodos({
  input: {},
  fields: ["id", "title"],
  fetchOptions: {
    // @ts-expect-error - signal should be AbortSignal, not string
    signal: "invalid signal",
  },
});

console.log("These custom fetch error tests should fail TypeScript compilation!");