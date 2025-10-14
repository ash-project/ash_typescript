// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Advanced fetchOptions Tests - shouldPass
// Real-world usage patterns for fetchOptions and customFetch

import {
  listTodos,
  createTodo,
  getTodo,
  updateTodo,
  validateCreateTodo,
  buildCSRFHeaders,
} from "../generated";

// Advanced custom fetch with comprehensive header management
const advancedCustomFetch = async (
  input: RequestInfo | URL,
  init?: RequestInit
): Promise<Response> => {
  // Simulate getting user preferences from safe storage
  const preferences = {
    language: "en-US",
    timezone: "America/New_York",
    apiVersion: "v2",
    theme: "dark",
  };

  // Generate correlation ID for request tracking
  const correlationId = `adv_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;

  // Build comprehensive headers
  const enhancedHeaders = {
    // Preserve existing headers
    ...init?.headers,
    // Add user preference headers
    'Accept-Language': preferences.language,
    'X-User-Timezone': preferences.timezone,
    'X-API-Version': preferences.apiVersion,
    'X-User-Theme': preferences.theme,
    // Add tracking headers
    'X-Correlation-ID': correlationId,
    'X-Request-Source': 'ash-typescript-client',
    'X-Timestamp': new Date().toISOString(),
  };

  // Apply default timeout if not specified
  const timeoutMs = 30000; // 30 seconds default
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const response = await fetch(input, {
      ...init,
      headers: enhancedHeaders,
      // Use provided signal or our timeout signal
      signal: init?.signal || controller.signal,
    });

    clearTimeout(timeoutId);
    return response;
  } catch (error) {
    clearTimeout(timeoutId);
    throw error;
  }
};

// Test 1: Production-like request with comprehensive options
export const productionLikeRequest = await listTodos({
  input: {},
  fields: [
    "id",
    "title",
    "completed",
    "priority",
    "createdAt",
    { user: ["id", "name"] }
  ],
  filter: {
    and: [
      { completed: { eq: false } },
      { priority: { in: ["high", "urgent"] } }
    ]
  },
  page: { limit: 50, offset: 0 },
  sort: "-priority,+createdAt",
  headers: buildCSRFHeaders(),
  customFetch: advancedCustomFetch,
  fetchOptions: {
    credentials: 'include',
    mode: 'cors',
    cache: 'no-cache',
    referrerPolicy: 'strict-origin-when-cross-origin',
    keepalive: true,
  },
});

// Test 2: Request with manual abort controller
const manualAbortController = new AbortController();

export const abortableRequest = await getTodo({
  input: { id: "todo-789" },
  fields: ["id", "title", "description", "tags"],
  customFetch: advancedCustomFetch,
  fetchOptions: {
    signal: manualAbortController.signal,
    priority: 'high',
  },
});

// In a real app, you might cancel the request based on user action
// setTimeout(() => manualAbortController.abort(), 5000);

// Test 3: Retry logic with custom fetch
let retryCount = 0;
const retryFetch = async (
  input: RequestInfo | URL,
  init?: RequestInit
): Promise<Response> => {
  const maxRetries = 3;

  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      retryCount = attempt;
      const response = await advancedCustomFetch(input, {
        ...init,
        headers: {
          ...init?.headers,
          'X-Retry-Attempt': attempt.toString(),
          'X-Max-Retries': maxRetries.toString(),
        }
      });

      // If response is successful, return it
      if (response.ok) {
        return response;
      }

      // If it's the last attempt or a non-retryable error, return the response
      if (attempt === maxRetries || response.status < 500) {
        return response;
      }

      // Wait before retrying (exponential backoff)
      await new Promise(resolve => setTimeout(resolve, Math.pow(2, attempt) * 1000));

    } catch (error) {
      if (attempt === maxRetries) {
        throw error;
      }
      // Wait before retrying on network errors
      await new Promise(resolve => setTimeout(resolve, Math.pow(2, attempt) * 1000));
    }
  }

  throw new Error('Maximum retries exceeded');
};

export const requestWithRetry = await createTodo({
  input: {
    title: "Todo with Retry Logic",
    description: "This request will retry on failure",
    userId: "retry-user-123"
  },
  fields: ["id", "title", "createdAt"],
  customFetch: retryFetch,
  fetchOptions: {
    credentials: 'include',
  },
});

// Test 4: Request with custom content-type and body processing
const jsonApiCustomFetch = async (
  input: RequestInfo | URL,
  init?: RequestInit
): Promise<Response> => {
  // Modify requests to use JSON API format
  const enhancedInit = {
    ...init,
    headers: {
      ...init?.headers,
      'Content-Type': 'application/vnd.api+json',
      'Accept': 'application/vnd.api+json',
    }
  };

  return advancedCustomFetch(input, enhancedInit);
};

export const jsonApiRequest = await updateTodo({
  primaryKey: "todo-456",
  input: {
    title: "Updated via JSON API",
    completed: true
  },
  fields: ["id", "title", "completed", "createdAt"],
  customFetch: jsonApiCustomFetch,
});

// Test 5: Validation with comprehensive error handling
const validationCustomFetch = async (
  input: RequestInfo | URL,
  init?: RequestInit
): Promise<Response> => {
  try {
    const response = await advancedCustomFetch(input, init);

    // Log validation requests specifically
    if (input.toString().includes('/validate')) {
      console.log('Validation request completed:', {
        status: response.status,
        url: input,
        timestamp: new Date().toISOString()
      });
    }

    return response;
  } catch (error) {
    console.error('Validation request failed:', error);
    throw error;
  }
};

export const comprehensiveValidation = await validateCreateTodo({
  input: {
    title: "Validation Test Todo",
    priority: "high",
    tags: ["validation", "test", "comprehensive"],
    userId: "validation-user-123"
  },
  headers: buildCSRFHeaders(),
  customFetch: validationCustomFetch,
  fetchOptions: {
    cache: 'no-store', // Never cache validation requests
    credentials: 'include',
  },
});

// Test 6: Streaming/large response handling
const streamingCustomFetch = async (
  input: RequestInfo | URL,
  init?: RequestInit
): Promise<Response> => {
  return advancedCustomFetch(input, {
    ...init,
    // Enable streaming for large responses
    headers: {
      ...init?.headers,
      'Accept-Encoding': 'gzip, deflate, br',
    }
  });
};

export const largeDatasetRequest = await listTodos({
  input: {},
  fields: [
    "id",
    "title",
    "description",
    "tags",
    {
      user: ["id", "name", "email"],
      comments: ["id", "content", "authorName"]
    }
  ],
  page: { limit: 1000, offset: 0 },
  customFetch: streamingCustomFetch,
  fetchOptions: {
    credentials: 'include',
    // Use high priority for important data
    priority: 'high',
  },
});

// Type validation for advanced usage
if (productionLikeRequest.success) {
  const todos = productionLikeRequest.data.results;
  todos.forEach(todo => {
    const id: string = todo.id;
    const title: string = todo.title;
    const completed: boolean | null = todo.completed;
    const priority: "low" | "medium" | "high" | "urgent" | null = todo.priority;
    const createdAt: string = todo.createdAt;

    if (todo.user) {
      const userId: string = todo.user.id;
      const userName: string = todo.user.name;
    }
  });

  // Pagination metadata
  const hasMore: boolean = productionLikeRequest.data.hasMore;
  const limit: number = productionLikeRequest.data.limit;
}

if (requestWithRetry.success) {
  const newTodo = requestWithRetry.data;
  const id: string = newTodo.id;
  const title: string = newTodo.title;
  const createdAt: string = newTodo.createdAt;

  console.log(`Todo created after ${retryCount} attempts`);
}

if (comprehensiveValidation.success) {
  console.log("Comprehensive validation passed");
} else {
  const errors = comprehensiveValidation.errors;
  errors.forEach(error => {
    const type: string = error.type;
    const message: string = error.message;
    const field: string | undefined = error.field;
    const fieldPath: string | undefined = error.fieldPath;
  });
}

console.log("Advanced fetchOptions tests completed successfully!");
