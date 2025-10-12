// SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
//
// SPDX-License-Identifier: MIT

// Custom Fetch Tests - shouldPass
// Tests for customFetch and fetchOptions parameters

import {
  getTodo,
  listTodos,
  createTodo,
  updateTodo,
  validateCreateTodo,
  validateListTodos,
} from "../generated";

// Mock custom fetch function for testing
const mockEnhancedFetch = async (
  input: RequestInfo | URL,
  init?: RequestInit
): Promise<Response> => {
  // Add user preferences (safe localStorage usage)
  const userLanguage = "en-US";
  const userTimezone = "America/New_York";
  const correlationId = `test_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;

  // Simulate enhanced headers
  const enhancedHeaders = {
    ...init?.headers,
    'Accept-Language': userLanguage,
    'X-User-Timezone': userTimezone,
    'X-Correlation-ID': correlationId,
  };

  // Use native fetch with enhanced headers
  return fetch(input, {
    ...init,
    headers: enhancedHeaders,
  });
};

// Mock axios-style adapter for testing
const mockAxiosAdapter = async (
  input: RequestInfo | URL,
  init?: RequestInit
): Promise<Response> => {
  const url = typeof input === 'string' ? input : input.toString();

  // Simulate axios-style response structure
  const mockAxiosResponse = {
    data: { success: true, data: [] },
    status: 200,
    statusText: 'OK',
    headers: {
      'content-type': 'application/json',
      'x-powered-by': 'axios-adapter',
    }
  };

  // Convert to Response object
  return new Response(JSON.stringify(mockAxiosResponse.data), {
    status: mockAxiosResponse.status,
    statusText: mockAxiosResponse.statusText,
    headers: new Headers(mockAxiosResponse.headers),
  });
};

// Test 1: Basic customFetch usage
export const listTodosWithCustomFetch = await listTodos({
  input: {},
  fields: ["id", "title", "completed"],
  customFetch: mockEnhancedFetch,
});

// Test 2: fetchOptions with timeout
export const getTodoWithFetchOptions = await getTodo({
  input: { id: "todo-123" },
  fields: ["id", "title", "description"],
  fetchOptions: {
    signal: AbortSignal.timeout(5000),
    cache: 'no-cache',
    credentials: 'include',
  },
});

// Test 3: Both customFetch and fetchOptions together
export const createTodoWithBothOptions = await createTodo({
  input: { title: "Test Todo", userId: "user-123" },
  fields: ["id", "title", "createdAt"],
  customFetch: mockEnhancedFetch,
  fetchOptions: {
    signal: AbortSignal.timeout(10000),
    mode: 'cors',
    credentials: 'include',
  },
});

// Test 4: Validation function with custom fetch
export const validateCreateTodoWithCustomFetch = await validateCreateTodo({
  input: { title: "Validation Test", userId: "user-123" },
  customFetch: mockEnhancedFetch,
  fetchOptions: {
    cache: 'no-store',
  },
});

// Test 5: axios adapter usage
export const listTodosWithAxiosAdapter = await listTodos({
  input: {},
  fields: ["id", "title", "priority"],
  customFetch: mockAxiosAdapter,
});

// Test 6: Complex scenario with pagination and custom fetch
export const searchTodosWithCustomFetch = await listTodos({
  input: {},
  fields: [
    "id",
    "title",
    "priority",
    { user: ["id", "name", "email"] }
  ],
  filter: { completed: { eq: false } },
  page: { limit: 20, offset: 0 },
  sort: "-priority,+createdAt",
  customFetch: mockEnhancedFetch,
  fetchOptions: {
    signal: AbortSignal.timeout(15000),
    keepalive: true,
  },
});

// Test 7: Update operation with custom fetch
export const updateTodoWithCustomFetch = await updateTodo({
  primaryKey: "todo-123",
  input: { title: "Updated Todo Title" },
  fields: ["id", "title", "createdAt"],
  customFetch: mockEnhancedFetch,
  fetchOptions: {
    credentials: 'same-origin',
    referrer: 'strict-origin-when-cross-origin',
  },
});

// Test 8: AbortController integration
const controller = new AbortController();

export const listTodosWithAbortController = await listTodos({
  input: {},
  fields: ["id", "title"],
  fetchOptions: {
    signal: controller.signal,
  },
});

// Simulate cancellation (in real usage, this would be called separately)
// controller.abort();

// Test 9: Custom fetch with error handling simulation
const errorHandlingFetch = async (
  input: RequestInfo | URL,
  init?: RequestInit
): Promise<Response> => {
  // Add request logging
  console.log(`Making request to: ${input}`);
  console.log(`Request options:`, init);

  try {
    const response = await fetch(input, init);

    // Log response details
    if (!response.ok) {
      console.error(`Request failed: ${response.status} ${response.statusText}`);
    }

    return response;
  } catch (error) {
    console.error(`Network error:`, error);
    throw error;
  }
};

export const getTodoWithErrorHandling = await getTodo({
  input: { id: "todo-456" },
  fields: ["id", "title"],
  customFetch: errorHandlingFetch,
});

// Type validation tests
if (listTodosWithCustomFetch.success) {
  const todos = listTodosWithCustomFetch.data;
  todos.forEach(todo => {
    const id: string = todo.id;
    const title: string = todo.title;
    const completed: boolean | null = todo.completed;
  });
}

if (createTodoWithBothOptions.success) {
  const newTodo = createTodoWithBothOptions.data;
  const id: string = newTodo.id;
  const title: string = newTodo.title;
  const createdAt: string = newTodo.createdAt;
}

if (validateCreateTodoWithCustomFetch.success) {
  console.log("Validation passed with custom fetch");
} else {
  const errors = validateCreateTodoWithCustomFetch.errors;
  errors.forEach(error => {
    const type: string = error.type;
    const message: string = error.message;
  });
}

console.log("Custom fetch tests completed successfully!");