<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Custom Fetch Functions and Request Options

This guide covers how to customize HTTP requests made by AshTypescript-generated RPC functions using fetch options and custom fetch implementations.

## Overview

AshTypescript provides two ways to customize HTTP requests:
- **fetchOptions**: Customize individual requests using standard Fetch API options
- **customFetch**: Replace the fetch implementation entirely for advanced use cases

These features enable:
- Request timeouts and cancellation
- Custom authentication and headers
- Request/response interceptors
- Alternative HTTP clients (axios, etc.)
- Request tracking and monitoring
- Cache control
- Credential management

> **💡 Global Configuration Alternative**: The `customFetch` and `fetchOptions` parameters shown in this guide are ideal for per-request customization. However, if you need to apply the same custom fetch function or fetch options to all RPC calls globally, use **[Lifecycle Hooks](../topics/lifecycle-hooks.md)** instead. Configure them once in your application settings rather than passing them to every RPC call. You can still override these global defaults on a per-action basis by passing `customFetch` or `fetchOptions` to individual RPC calls. Lifecycle hooks also support other global concerns like authentication, request/response logging, and error tracking.

## Using fetchOptions

All generated RPC functions accept an optional `fetchOptions` parameter that passes standard [Fetch API options](https://developer.mozilla.org/en-US/docs/Web/API/fetch#options) to customize the underlying request.

### Example: Request with Fetch Options

```typescript
import { createTodo, listTodos } from './ash_rpc';

// Example: Add timeout and cache control
const todo = await createTodo({
  fields: ["id", "title"],
  input: {
    title: "New Todo",
    userId: "user-id-123"
  },
  fetchOptions: {
    signal: AbortSignal.timeout(5000), // 5 second timeout
    cache: 'no-cache',
    credentials: 'include'
  }
});

// Example: Cancellable request
const controller = new AbortController();
const todosPromise = listTodos({
  fields: ["id", "title"],
  fetchOptions: {
    signal: controller.signal
  }
});

// Cancel the request
controller.abort();
```

Any valid Fetch API option can be passed, including `signal`, `cache`, `credentials`, `mode`, `redirect`, `referrerPolicy`, and more. See the [MDN Fetch API documentation](https://developer.mozilla.org/en-US/docs/Web/API/fetch#options) for the complete list of available options.

## Custom Fetch Functions

For advanced use cases, you can replace the fetch implementation entirely by providing a `customFetch` parameter.

### Basic Custom Fetch

Create a simple custom fetch wrapper:

```typescript
import { listTodos } from './ash_rpc';

const loggingFetch = async (url: RequestInfo | URL, init?: RequestInit) => {
  console.log("Request:", url, init);
  const response = await fetch(url, init);
  console.log("Response:", response.status);
  return response;
};

const todos = await listTodos({
  fields: ["id", "title"],
  customFetch: loggingFetch
});
```

### Request Tracking and Monitoring

Add correlation IDs and request tracking:

```typescript
import { createTodo, listTodos } from './ash_rpc';

const enhancedFetch = async (url: RequestInfo | URL, init?: RequestInit) => {
  // Get user preferences from localStorage (safe, non-sensitive data)
  const userLanguage = localStorage.getItem('userLanguage') || 'en';
  const userTimezone = localStorage.getItem('userTimezone') || 'UTC';
  const apiVersion = localStorage.getItem('preferredApiVersion') || 'v1';

  // Generate correlation ID for request tracking
  const correlationId = `req_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;

  const customHeaders = {
    'Accept-Language': userLanguage,
    'X-User-Timezone': userTimezone,
    'X-API-Version': apiVersion,
    'X-Correlation-ID': correlationId,
  };

  // Log request start
  console.log(`[${correlationId}] Request started:`, url);

  const startTime = performance.now();

  const response = await fetch(url, {
    ...init,
    headers: {
      ...init?.headers,
      ...customHeaders
    }
  });

  const duration = performance.now() - startTime;

  // Log request completion
  console.log(`[${correlationId}] Request completed in ${duration}ms:`, response.status);

  return response;
};

// Use custom fetch function
const todos = await listTodos({
  fields: ["id", "title"],
  customFetch: enhancedFetch
});
```

### Global Authentication

Add authentication tokens to all requests:

```typescript
async function getAuthToken(): Promise<string> {
  // Get token from storage, refresh if needed
  const token = localStorage.getItem('authToken');
  if (!token) {
    throw new Error('Not authenticated');
  }
  return token;
}

const authenticatedFetch = async (url: RequestInfo | URL, init?: RequestInit) => {
  const token = await getAuthToken();

  return fetch(url, {
    ...init,
    headers: {
      ...init?.headers,
      'Authorization': `Bearer ${token}`
    }
  });
};

// All requests now include authentication
const todos = await listTodos({
  fields: ["id", "title"],
  customFetch: authenticatedFetch
});
```

### Request/Response Interceptors

Implement middleware-style interceptors:

```typescript
type FetchInterceptor = {
  request?: (url: RequestInfo | URL, init?: RequestInit) => Promise<RequestInit | undefined>;
  response?: (response: Response) => Promise<Response>;
};

function createInterceptedFetch(interceptors: FetchInterceptor[]) {
  return async (url: RequestInfo | URL, init?: RequestInit) => {
    let modifiedInit = init;

    // Request interceptors
    for (const interceptor of interceptors) {
      if (interceptor.request) {
        modifiedInit = await interceptor.request(url, modifiedInit);
      }
    }

    let response = await fetch(url, modifiedInit);

    // Response interceptors
    for (const interceptor of interceptors) {
      if (interceptor.response) {
        response = await interceptor.response(response);
      }
    }

    return response;
  };
}

// Define interceptors
const loggingInterceptor: FetchInterceptor = {
  request: async (url, init) => {
    console.log("Request:", url);
    return init;
  },
  response: async (response) => {
    console.log("Response:", response.status);
    return response;
  }
};

const authInterceptor: FetchInterceptor = {
  request: async (url, init) => {
    const token = await getAuthToken();
    return {
      ...init,
      headers: {
        ...init?.headers,
        'Authorization': `Bearer ${token}`
      }
    };
  }
};

// Create fetch with interceptors
const interceptedFetch = createInterceptedFetch([
  loggingInterceptor,
  authInterceptor
]);

// Use in requests
const todos = await listTodos({
  fields: ["id", "title"],
  customFetch: interceptedFetch
});
```

### Error Retry Logic

Implement automatic retry on failure:

```typescript
function createRetryFetch(maxRetries = 3, delayMs = 1000) {
  return async (url: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
    for (let attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        const response = await fetch(url, init);

        // Retry on server errors (5xx)
        if (response.status >= 500 && attempt < maxRetries) {
          console.log(`Retry attempt ${attempt + 1}/${maxRetries}`);
          await new Promise(resolve => setTimeout(resolve, delayMs * Math.pow(2, attempt)));
          continue;
        }

        return response;
      } catch (error) {
        // Retry on network errors
        if (attempt < maxRetries) {
          console.log(`Retry attempt ${attempt + 1}/${maxRetries} after error:`, error);
          await new Promise(resolve => setTimeout(resolve, delayMs * Math.pow(2, attempt)));
          continue;
        }
        throw error;
      }
    }

    throw new Error("Max retries exceeded");
  };
}

const retryFetch = createRetryFetch(3, 1000);

const todos = await listTodos({
  fields: ["id", "title"],
  customFetch: retryFetch
});
```

### Response Validation

Validate responses before returning:

```typescript
const validatingFetch = async (url: RequestInfo | URL, init?: RequestInit) => {
  const response = await fetch(url, init);

  // Validate response
  if (!response.ok) {
    const errorBody = await response.text();
    console.error("Request failed:", response.status, errorBody);
  }

  // Check content type
  const contentType = response.headers.get('content-type');
  if (contentType && !contentType.includes('application/json')) {
    console.warn("Unexpected content type:", contentType);
  }

  return response;
};

const todos = await listTodos({
  fields: ["id", "title"],
  customFetch: validatingFetch
});
```

## Using Axios with AshTypescript

While AshTypescript uses the Fetch API by default, you can create an adapter to use axios or other HTTP clients.

### Basic Axios Adapter

Create an adapter that converts axios to fetch:

```typescript
import axios from 'axios';

const axiosAdapter = async (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
  try {
    const url = typeof input === 'string' ? input : input.toString();

    const axiosResponse = await axios({
      url,
      method: init?.method || 'GET',
      headers: init?.headers,
      data: init?.body,
      timeout: 10000,
      validateStatus: () => true // Don't throw on HTTP errors
    });

    // Convert axios response to fetch Response
    return new Response(JSON.stringify(axiosResponse.data), {
      status: axiosResponse.status,
      statusText: axiosResponse.statusText,
      headers: new Headers(axiosResponse.headers as any)
    });
  } catch (error) {
    if (error.response) {
      // HTTP error status
      return new Response(JSON.stringify(error.response.data), {
        status: error.response.status,
        statusText: error.response.statusText
      });
    }
    throw error; // Network error
  }
};

// Use axios for all requests
const todos = await listTodos({
  fields: ["id", "title"],
  customFetch: axiosAdapter
});
```

### Axios with Interceptors

Leverage axios interceptors:

```typescript
import axios, { AxiosInstance } from 'axios';

const axiosInstance: AxiosInstance = axios.create({
  timeout: 10000,
  headers: {
    'Content-Type': 'application/json'
  }
});

// Add request interceptor
axiosInstance.interceptors.request.use(
  (config) => {
    const token = localStorage.getItem('authToken');
    if (token) {
      config.headers.Authorization = `Bearer ${token}`;
    }
    console.log("Request:", config.url);
    return config;
  },
  (error) => {
    return Promise.reject(error);
  }
);

// Add response interceptor
axiosInstance.interceptors.response.use(
  (response) => {
    console.log("Response:", response.status);
    return response;
  },
  (error) => {
    if (error.response?.status === 401) {
      // Handle unauthorized
      console.error("Unauthorized - redirecting to login");
    }
    return Promise.reject(error);
  }
);

// Create adapter using the configured instance
const axiosInstanceAdapter = async (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
  try {
    const url = typeof input === 'string' ? input : input.toString();

    const axiosResponse = await axiosInstance({
      url,
      method: init?.method || 'GET',
      headers: init?.headers,
      data: init?.body,
      validateStatus: () => true
    });

    return new Response(JSON.stringify(axiosResponse.data), {
      status: axiosResponse.status,
      statusText: axiosResponse.statusText,
      headers: new Headers(axiosResponse.headers as any)
    });
  } catch (error) {
    if (error.response) {
      return new Response(JSON.stringify(error.response.data), {
        status: error.response.status,
        statusText: error.response.statusText
      });
    }
    throw error;
  }
};

// Use in requests
const todos = await listTodos({
  fields: ["id", "title"],
  customFetch: axiosInstanceAdapter
});
```

## Advanced Patterns

### Global Fetch Configuration

Create a configured fetch function for your application:

```typescript
import { buildCSRFHeaders } from './ash_rpc';

interface AppFetchOptions {
  includeAuth?: boolean;
  includeCsrf?: boolean;
  timeout?: number;
  retries?: number;
}

function createAppFetch(options: AppFetchOptions = {}) {
  const {
    includeAuth = true,
    includeCsrf = true,
    timeout = 10000,
    retries = 3
  } = options;

  return async (url: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
    const headers: Record<string, string> = {
      ...(init?.headers as Record<string, string> || {})
    };

    // Add authentication
    if (includeAuth) {
      const token = localStorage.getItem('authToken');
      if (token) {
        headers['Authorization'] = `Bearer ${token}`;
      }
    }

    // Add CSRF headers
    if (includeCsrf) {
      const csrfHeaders = buildCSRFHeaders();
      Object.assign(headers, csrfHeaders);
    }

    // Add timeout
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), timeout);

    try {
      // Implement retry logic
      for (let attempt = 0; attempt <= retries; attempt++) {
        try {
          const response = await fetch(url, {
            ...init,
            headers,
            signal: controller.signal
          });

          if (response.status >= 500 && attempt < retries) {
            await new Promise(resolve => setTimeout(resolve, 1000 * Math.pow(2, attempt)));
            continue;
          }

          return response;
        } catch (error) {
          if (attempt < retries && error.name !== 'AbortError') {
            await new Promise(resolve => setTimeout(resolve, 1000 * Math.pow(2, attempt)));
            continue;
          }
          throw error;
        }
      }

      throw new Error("Max retries exceeded");
    } finally {
      clearTimeout(timeoutId);
    }
  };
}

// Create configured fetch
const appFetch = createAppFetch({
  includeAuth: true,
  includeCsrf: true,
  timeout: 10000,
  retries: 3
});

// Use in all requests
const todos = await listTodos({
  fields: ["id", "title"],
  customFetch: appFetch
});
```

### Per-Request Custom Fetch

Combine global configuration with per-request customization:

```typescript
// Default fetch for most requests
const defaultFetch = createAppFetch({
  includeAuth: true,
  includeCsrf: true
});

// Public fetch without authentication
const publicFetch = createAppFetch({
  includeAuth: false,
  includeCsrf: false
});

// Admin fetch with longer timeout
const adminFetch = createAppFetch({
  includeAuth: true,
  includeCsrf: true,
  timeout: 30000
});

// Use different fetch functions based on context
const publicTodos = await listTodos({
  fields: ["id", "title"],
  customFetch: publicFetch
});

const adminUsers = await listUsers({
  fields: ["id", "name", "role"],
  customFetch: adminFetch
});
```

### Conditional Fetch Configuration

Choose fetch configuration based on environment:

```typescript
function getFetchForEnvironment() {
  if (process.env.NODE_ENV === 'development') {
    // Development: verbose logging
    return async (url: RequestInfo | URL, init?: RequestInit) => {
      console.log("DEV Request:", url, init);
      const response = await fetch(url, init);
      console.log("DEV Response:", response.status, await response.clone().text());
      return response;
    };
  } else if (process.env.NODE_ENV === 'production') {
    // Production: error tracking
    return async (url: RequestInfo | URL, init?: RequestInit) => {
      try {
        return await fetch(url, init);
      } catch (error) {
        // Send to error tracking service
        trackError(error);
        throw error;
      }
    };
  }

  return fetch; // Default
}

const environmentFetch = getFetchForEnvironment();

const todos = await listTodos({
  fields: ["id", "title"],
  customFetch: environmentFetch
});
```

## Best Practices

### 1. Use fetchOptions for Simple Customization

For simple timeout or cache control, use fetchOptions:

```typescript
// Good: Simple and clear
const todos = await listTodos({
  fields: ["id", "title"],
  fetchOptions: {
    signal: AbortSignal.timeout(5000),
    cache: 'no-cache'
  }
});

// Overkill: Don't use customFetch for simple cases
const customFetch = async (url: RequestInfo | URL, init?: RequestInit) => {
  return fetch(url, {
    ...init,
    signal: AbortSignal.timeout(5000)
  });
};
```

### 2. Create Reusable Fetch Functions

Extract custom fetch logic into reusable functions:

```typescript
// Good: Reusable
const authenticatedFetch = createAuthenticatedFetch();

const todos = await listTodos({
  fields: ["id", "title"],
  customFetch: authenticatedFetch
});

const users = await listUsers({
  fields: ["id", "name"],
  customFetch: authenticatedFetch
});
```

### 3. Handle Errors Appropriately

Don't swallow errors in custom fetch:

```typescript
// Bad: Swallowing errors
const badFetch = async (url: RequestInfo | URL, init?: RequestInit) => {
  try {
    return await fetch(url, init);
  } catch (error) {
    console.error("Error:", error);
    return new Response("Error", { status: 500 }); // Masks the real error
  }
};

// Good: Let errors propagate
const goodFetch = async (url: RequestInfo | URL, init?: RequestInit) => {
  try {
    return await fetch(url, init);
  } catch (error) {
    console.error("Error:", error);
    throw error; // Let caller handle
  }
};
```

### 4. Document Custom Fetch Behavior

Document what your custom fetch does:

```typescript
/**
 * Authenticated fetch function that:
 * - Adds Bearer token from localStorage
 * - Includes CSRF headers
 * - Retries on 5xx errors
 * - Times out after 10 seconds
 */
const authenticatedFetch = createAuthenticatedFetch();
```

### 5. Test Custom Fetch Functions

Test your custom fetch implementations:

```typescript
// Test that custom fetch adds authentication
test('authenticatedFetch adds auth header', async () => {
  const mockFetch = jest.fn().mockResolvedValue(new Response('{}'));
  global.fetch = mockFetch;

  localStorage.setItem('authToken', 'test-token');

  const customFetch = createAuthenticatedFetch();
  await customFetch('http://example.com', {});

  expect(mockFetch).toHaveBeenCalledWith(
    'http://example.com',
    expect.objectContaining({
      headers: expect.objectContaining({
        'Authorization': 'Bearer test-token'
      })
    })
  );
});
```

## Related Documentation

- [Basic CRUD Operations](./basic-crud.md) - Learn about basic RPC operations
- [Error Handling](./error-handling.md) - Handle errors from custom fetch functions
- [Phoenix Channels](../topics/phoenix-channels.md) - Alternative to HTTP-based requests
- [Configuration](../reference/configuration.md) - Configure RPC settings
