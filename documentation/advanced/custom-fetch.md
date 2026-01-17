<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Custom Fetch Functions

AshTypescript uses the standard Fetch API by default. You can customize requests using `fetchOptions` or replace the fetch implementation entirely with `customFetch`.

## Using fetchOptions

For simple customization like timeouts or cache control, use the `fetchOptions` parameter:

```typescript
import { listTodos } from './ash_rpc';

// Add timeout and cache control
const todos = await listTodos({
  fields: ["id", "title"],
  fetchOptions: {
    signal: AbortSignal.timeout(5000),
    cache: 'no-cache',
    credentials: 'include'
  }
});

// Cancellable request
const controller = new AbortController();
const todosPromise = listTodos({
  fields: ["id", "title"],
  fetchOptions: {
    signal: controller.signal
  }
});

controller.abort(); // Cancel the request
```

See the [MDN Fetch API documentation](https://developer.mozilla.org/en-US/docs/Web/API/fetch#options) for all available options.

## Custom Fetch Functions

Use `customFetch` when:
- Your JS framework provides a custom fetch function you need to use
- You want to use axios or another HTTP client instead of fetch

### Framework-Provided Fetch

Some frameworks provide their own fetch function with built-in features. Pass it directly:

```typescript
import { frameworkFetch } from 'your-framework';
import { listTodos } from './ash_rpc';

const todos = await listTodos({
  fields: ["id", "title"],
  customFetch: frameworkFetch
});
```

### Using Axios

Create an adapter that wraps axios to match the fetch interface:

```typescript
import axios from 'axios';
import { listTodos } from './ash_rpc';

const axiosAdapter = async (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
  const url = typeof input === 'string' ? input : input.toString();

  try {
    const response = await axios({
      url,
      method: init?.method || 'GET',
      headers: init?.headers as Record<string, string>,
      data: init?.body,
      validateStatus: () => true
    });

    return new Response(JSON.stringify(response.data), {
      status: response.status,
      statusText: response.statusText,
      headers: new Headers(response.headers as Record<string, string>)
    });
  } catch (error: any) {
    if (error.response) {
      return new Response(JSON.stringify(error.response.data), {
        status: error.response.status,
        statusText: error.response.statusText
      });
    }
    throw error;
  }
};

const todos = await listTodos({
  fields: ["id", "title"],
  customFetch: axiosAdapter
});
```

## Global Configuration

For settings that apply to all requests (authentication, logging, etc.), use [Lifecycle Hooks](../features/lifecycle-hooks.md) instead of passing `customFetch` to every call.

## Next Steps

- [Lifecycle Hooks](../features/lifecycle-hooks.md) - Global request/response handling
- [Error Handling](../guides/error-handling.md) - Handle errors from RPC calls
