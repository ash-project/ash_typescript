<!--
SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>

SPDX-License-Identifier: MIT
-->

# Lifecycle Hooks

AshTypescript provides comprehensive lifecycle hooks for both HTTP and Phoenix Channel-based RPC actions. These hooks enable cross-cutting concerns like logging, telemetry, performance tracking, and error monitoring. HTTP hooks additionally support authentication header injection.

## Table of Contents

- [HTTP Lifecycle Hooks](#http-lifecycle-hooks)
  - [Why Use HTTP Lifecycle Hooks?](#why-use-http-lifecycle-hooks)
  - [HTTP Configuration](#http-configuration)
  - [Hook Types: Actions vs Validations](#hook-types-actions-vs-validations)
  - [Hook Function Signatures](#hook-function-signatures)
  - [beforeRequest Hook](#beforerequest-hook)
  - [afterRequest Hook](#afterrequest-hook)
  - [Config Precedence Rules](#config-precedence-rules)
  - [Exception Handling](#exception-handling)
  - [Complete Working Example](#complete-working-example)
- [Channel Lifecycle Hooks](#channel-lifecycle-hooks)
  - [Why Use Channel Lifecycle Hooks?](#why-use-channel-lifecycle-hooks)
  - [Key Differences from HTTP Hooks](#key-differences-from-http-hooks)
  - [Channel Configuration](#channel-configuration)
  - [Channel Hook Function Signatures](#channel-hook-function-signatures)
  - [beforeChannelPush Hook](#beforechannelpush-hook)
  - [afterChannelResponse Hook](#afterchannelresponse-hook)
  - [Channel Config Precedence Rules](#channel-config-precedence-rules)
  - [Complete Channel Working Example](#complete-channel-working-example)
- [Troubleshooting](#troubleshooting)

## HTTP Lifecycle Hooks

AshTypescript provides lifecycle hooks that let you inject custom logic before and after HTTP requests. These hooks enable cross-cutting concerns like authentication, logging, telemetry, performance tracking, and error monitoring.

### Why Use HTTP Lifecycle Hooks?

Lifecycle hooks provide a centralized way to:
- **Add authentication tokens** - Automatically inject auth headers from localStorage
- **Log requests and responses** - Track API calls for debugging
- **Measure performance** - Time API calls and track latency
- **Send telemetry** - Report metrics to monitoring services
- **Handle errors globally** - Track errors in Sentry, Datadog, etc.
- **Add correlation IDs** - Track requests across distributed systems
- **Add default headers** - Set client version, request IDs, etc.
- **Transform requests** - Modify config before sending

### HTTP Configuration

Configure lifecycle hooks in your application config:

```elixir
# config/config.exs
config :ash_typescript,
  # Hook functions for RPC actions
  rpc_action_before_request_hook: "RpcHooks.beforeRequest",
  rpc_action_after_request_hook: "RpcHooks.afterRequest",

  # Hook functions for validation actions
  rpc_validation_before_request_hook: "RpcHooks.beforeValidationRequest",
  rpc_validation_after_request_hook: "RpcHooks.afterValidationRequest",

  # TypeScript types for hook context (optional)
  rpc_action_hook_context_type: "RpcHooks.ActionHookContext",
  rpc_validation_hook_context_type: "RpcHooks.ValidationHookContext",

  # Import the module containing your hook functions
  import_into_generated: [
    %{
      import_name: "RpcHooks",
      file: "./rpcHooks"
    }
  ]
```

**Configuration Options:**

| Config | Purpose | Default |
|--------|---------|---------|
| `rpc_action_before_request_hook` | Function called before RPC action requests | `nil` (disabled) |
| `rpc_action_after_request_hook` | Function called after RPC action requests | `nil` (disabled) |
| `rpc_validation_before_request_hook` | Function called before validation requests | `nil` (disabled) |
| `rpc_validation_after_request_hook` | Function called after validation requests | `nil` (disabled) |
| `rpc_action_hook_context_type` | TypeScript type for action hook context | `"Record<string, any>"` |
| `rpc_validation_hook_context_type` | TypeScript type for validation hook context | `"Record<string, any>"` |

### Hook Types: Actions vs Validations

AshTypescript provides **separate hooks for actions and validations** because they serve different purposes:

- **Action Hooks** - Execute when calling RPC actions (create, read, update, delete, custom actions)
- **Validation Hooks** - Execute when calling validation functions (client-side form validation)

This separation allows you to:
- Use different logging levels (validations are typically more frequent)
- Track different metrics (validation performance vs action performance)

**Action hooks are for actual API calls, validation hooks are for form validation.**

### Hook Function Signatures

Both `beforeRequest` and `afterRequest` hooks receive the full config object and can access the optional `hookCtx` from it.

**Important:** AshTypescript exports `ActionConfig` and `ValidationConfig` types from the generated file. These types automatically include your custom `hookCtx` types based on your configuration settings.

#### Configuring Custom Hook Context Types

When you configure context type settings in your Elixir config, the generated TypeScript interfaces will automatically include these types:

```elixir
# config/config.exs
config :ash_typescript,
  # TypeScript types for hook context
  rpc_action_hook_context_type: "RpcHooks.ActionHookContext",
  rpc_validation_hook_context_type: "RpcHooks.ValidationHookContext"
```

With this configuration, the generated `ActionConfig` and `ValidationConfig` types will have properly typed `hookCtx` fields:

```typescript
// Generated types (in your generated file)
export interface ActionConfig {
  // ... other fields ...
  hookCtx?: RpcHooks.ActionHookContext;  // ← Your custom type
}

export interface ValidationConfig {
  // ... other fields ...
  hookCtx?: RpcHooks.ValidationHookContext;  // ← Your custom type
}
```

#### Implementing Hook Functions

Simply import and use the generated config types directly - no generics needed!

```typescript
// rpcHooks.ts - Define your custom hook context interfaces
export interface ActionHookContext {
  enableLogging?: boolean;
  enableTiming?: boolean;
  customHeaders?: Record<string, string>;
  startTime?: number;
}

export interface ValidationHookContext {
  enableLogging?: boolean;
  validationLevel?: "strict" | "normal";
}

// Import the generated config types
import type { ActionConfig, ValidationConfig } from './generated';

// Implement your hook functions - the hookCtx is already properly typed!
export async function beforeActionRequest(
  actionName: string,
  config: ActionConfig
): Promise<ActionConfig> {
  const ctx = config.hookCtx;

  // ctx is automatically typed as ActionHookContext | undefined
  if (ctx?.enableLogging) {
    console.log(`[Action] ${actionName} started`);
  }

  // Modify hookCtx if needed
  const modifiedCtx = ctx ? { ...ctx, startTime: Date.now() } : undefined;

  return {
    ...config,
    ...(modifiedCtx && { hookCtx: modifiedCtx })
  };
}

export async function afterActionRequest(
  actionName: string,
  response: Response,
  result: any | null,
  config: ActionConfig
): Promise<void> {
  const ctx = config.hookCtx;

  // ctx.startTime is properly typed (no type assertion needed!)
  if (ctx?.enableTiming && ctx.startTime) {
    const duration = Date.now() - ctx.startTime;
    console.log(`Request took ${duration}ms`);
  }
}

// Similarly for validation hooks
export async function beforeValidationRequest(
  actionName: string,
  config: ValidationConfig
): Promise<ValidationConfig> {
  const ctx = config.hookCtx;

  if (ctx?.validationLevel === "strict") {
    console.log(`[Validation] Running in strict mode`);
  }

  return config;
}
```

**Key Benefits:**
- **Type safety** - Your custom context fields are properly typed automatically
- **IntelliSense** - IDE autocomplete works for your custom fields
- **No generics needed** - The generated types already include your context types
- **Simpler code** - Direct usage without complex generic constraints

The exported `ActionConfig` interface includes all available configuration fields:

```typescript
// This type is exported from your generated file
export interface ActionConfig {
  // Request data
  input?: Record<string, any>;
  primaryKey?: any;
  fields?: Array<string | Record<string, any>>; // Field selection
  filter?: Record<string, any>; // Filter options (for reads)
  sort?: string; // Sort options
  page?:
    | {
        // Offset-based pagination
        limit?: number;
        offset?: number;
        count?: boolean;
      }
    | {
        // Keyset pagination
        limit?: number;
        after?: string;
        before?: string;
      };

  // Metadata
  metadataFields?: Record<string, any>; // Metadata field selection

  // HTTP customization
  headers?: Record<string, string>; // Custom headers
  fetchOptions?: RequestInit; // Fetch options (signal, cache, etc.)
  customFetch?: (
    input: RequestInfo | URL,
    init?: RequestInit,
  ) => Promise<Response>;

  // Multitenancy
  tenant?: string; // Tenant parameter

  // Hook context
  hookCtx?: Record<string, any>;
}

// This type is also exported from your generated file
export interface ValidationConfig {
  // Request data
  input?: Record<string, any>;

  // HTTP customization
  headers?: Record<string, string>;
  fetchOptions?: RequestInit;
  customFetch?: (
    input: RequestInfo | URL,
    init?: RequestInit,
  ) => Promise<Response>;

  // Hook context
  hookCtx?: Record<string, any>;
}
```

**Key Points:**
- Hooks receive the entire `config` object as a parameter
- Hook context is accessed via `config.hookCtx` (optional)
- `beforeRequest` returns a modified config object
- `afterRequest` returns nothing (void) - it's for side effects only
- Hooks run unconditionally when configured (not gated by `hookCtx` presence)

### beforeRequest Hook

The `beforeRequest` hook runs **before the HTTP request** and can modify the request configuration. Common use cases:

#### Adding Authentication Tokens

```typescript
// rpcHooks.ts
import type { ActionConfig } from './generated';

export function beforeRequest(actionName: string, config: ActionConfig): ActionConfig {
  // Fetch auth token from localStorage (if it exists)
  const authToken = localStorage.getItem('authToken');

  // Add authentication header if token is present
  if (authToken) {
    return {
      ...config,
      headers: {
        ...config.headers,
        'Authorization': `Bearer ${authToken}`
      }
    };
  }

  return config;
}
```

This pattern automatically adds authentication to all RPC requests without needing to pass tokens through every call. The hook centralizes auth header logic in one place.

```typescript
// Usage: Auth headers are added automatically
const todos = await listTodos({
  fields: ["id", "title"]
  // No need to pass auth tokens - hook handles it!
});
```

#### Adding Correlation IDs for Request Tracking

```typescript
// rpcHooks.ts
import type { ActionConfig } from './generated';

export interface ActionHookContext {
  correlationId?: string;
}

export function beforeRequest(actionName: string, config: ActionConfig): ActionConfig {
  const ctx = config.hookCtx;

  // Use provided correlation ID or generate one
  const correlationId = ctx?.correlationId || generateRequestId();

  return {
    ...config,
    headers: {
      'X-Client-Version': '1.0.0',
      'X-Correlation-ID': correlationId,
      'X-Request-ID': correlationId,
      ...config.headers  // Original headers take precedence
    }
  };
}

function generateRequestId(): string {
  return `req_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
}
```

```typescript
// Usage: Pass correlation ID for distributed tracing
const todos = await listTodos({
  fields: ["id", "title"],
  hookCtx: {
    correlationId: 'user-dashboard-load-456'
  }
});
```

#### Request Timing Setup

```typescript
export interface ActionHookContext {
  startTime?: number;
}

export function beforeRequest(actionName: string, config: ActionConfig): ActionConfig {
  const ctx = config.hookCtx;

  // Store request start time in context for afterRequest hook
  if (ctx) {
    ctx.startTime = Date.now();
  }

  return config;
}
```

#### Logging Outgoing Requests

```typescript
export function beforeRequest(actionName: string, config: ActionConfig): ActionConfig {
  const ctx = config.hookCtx;

  console.log('Outgoing RPC request:', {
    action: actionName,
    domain: config.domain,
    hasInput: !!config.input,
    timestamp: new Date().toISOString(),
    correlationId: ctx?.correlationId
  });

  return config;
}
```

### afterRequest Hook

The `afterRequest` hook runs **after the HTTP request completes** (both success and error) and is used for side effects. It receives three parameters:

1. `response: Response` - The raw HTTP response object
2. `result: any | null` - Parsed JSON result (null when `response.ok` is false)
3. `config: ActionConfig` - The config used for the request

#### Important: Null Result Handling

The `afterRequest` hook receives `null` as the result parameter when the response is not OK:

```typescript
export function afterRequest(
  actionName: string,
  response: Response,
  result: any | null,
  config: ActionConfig
): void {
  if (result === null) {
    // Response failed (response.ok === false)
    console.error('Request failed:', {
      status: response.status,
      statusText: response.statusText,
      url: response.url
    });
  } else {
    // Response succeeded (response.ok === true)
    console.log('Request succeeded:', {
      hasData: !!result.data,
      success: result.success
    });
  }
}
```

#### Logging All Responses

```typescript
export function afterRequest(
  actionName: string,
  response: Response,
  result: any | null,
  config: ActionConfig
): void {
  const ctx = config.hookCtx;

  console.log('RPC response received:', {
    action: actionName,
    domain: config.domain,
    status: response.status,
    ok: response.ok,
    hasResult: result !== null,
    correlationId: ctx?.correlationId,
    timestamp: new Date().toISOString()
  });
}
```

#### Performance Timing

```typescript
export interface ActionHookContext {
  startTime?: number;
  trackPerformance?: boolean;
}

export function afterRequest(
  actionName: string,
  response: Response,
  result: any | null,
  config: ActionConfig
): void {
  const ctx = config.hookCtx;

  if (ctx?.trackPerformance && ctx.startTime) {
    const duration = Date.now() - ctx.startTime;

    console.log('Performance metrics:', {
      action: actionName,
      duration: `${duration}ms`,
      status: response.status,
      success: result !== null && result.success
    });

    // Send to analytics service
    trackMetric('rpc.duration', duration, {
      action: actionName,
      status: response.status
    });
  }
}
```

#### Telemetry Tracking

```typescript
export function afterRequest(
  actionName: string,
  response: Response,
  result: any | null,
  config: ActionConfig
): void {
  // Send telemetry to monitoring service
  sendTelemetry({
    event: 'rpc.request.completed',
    action: actionName,
    domain: config.domain,
    status: response.status,
    success: response.ok && result?.success,
    timestamp: Date.now()
  });
}
```

#### Error Monitoring

```typescript
export function afterRequest(
  actionName: string,
  response: Response,
  result: any | null,
  config: ActionConfig
): void {
  // Track errors in error monitoring service
  if (result === null || !result.success) {
    Sentry.captureMessage('RPC request failed', {
      level: 'error',
      extra: {
        action: actionName,
        status: response.status,
        errors: result?.errors,
        url: response.url
      }
    });
  }
}
```

### Config Precedence Rules

When using `beforeRequest` hooks, the **original config passed to the action always takes precedence** over the modified config:

```typescript
export function beforeRequest(actionName: string, config: ActionConfig): ActionConfig {
  return {
    ...config,
    headers: {
      'X-Default-Header': 'value',
      ...config.headers  // ← Original headers override defaults
    },
    customFetch: config.customFetch || myDefaultFetch  // ← Original takes precedence
  };
}
```

**Precedence order:**
1. Original `config` values used in action (highest priority)
2. Modified config from `beforeRequest` hook
3. Default fetch implementation (lowest priority)

This ensures that per-request customizations always override hook defaults.

### Exception Handling

Hooks **do not catch exceptions** - any errors thrown by hooks will propagate to the caller:

```typescript
export function beforeRequest(actionName: string, config: ActionConfig): ActionConfig {
  if (!isValidConfig(config)) {
    // This exception propagates to the caller
    throw new Error('Invalid RPC configuration');
  }
  return config;
}
```

**Use Cases for Exception Propagation:**

1. **Error Boundaries** - Let framework error boundaries catch and display errors
2. **Global Error Handlers** - Centralized error handling in your app
3. **Fail-Fast Validation** - Stop execution on critical errors

```typescript
// React component with error boundary
function MyComponent() {
  const handleSubmit = async () => {
    try {
      const result = await createTodo({
        fields: ["id", "title"],
        input: {
          title: "New Todo",
          userId: "123e4567-e89b-12d3-a456-426614174000"
        },
        hookCtx: {
          correlationId: 'user-submit-action',
          trackPerformance: true
        }
      });
      // Handle success
    } catch (error) {
      // Hook threw an exception
      console.error('RPC call failed:', error);
    }
  };
}
```

### Complete Working Example

Here's a complete example showing all hook features with the simplified pattern:

```typescript
// rpcHooks.ts
import type { ActionConfig, ValidationConfig } from './generated';

// Define your custom hook context interfaces
export interface ActionHookContext {
  trackPerformance?: boolean;
  startTime?: number;
  correlationId?: string;
}

export interface ValidationHookContext {
  formId?: string;
}

// Action hooks - directly use ActionConfig (no generics needed!)
export async function beforeActionRequest(
  actionName: string,
  config: ActionConfig
): Promise<ActionConfig> {
  const ctx = config.hookCtx;

  // Add correlation ID and client version headers
  const headers: Record<string, string> = {
    'X-Client-Version': '1.0.0',
    'X-Correlation-ID': ctx?.correlationId || generateRequestId(),
    ...config.headers
  };

  // Setup timing for performance tracking
  const modifiedCtx = ctx?.trackPerformance
    ? { ...ctx, startTime: Date.now() }
    : ctx;

  console.log(`[RPC] ${actionName} started`, {
    correlationId: ctx?.correlationId
  });

  return {
    ...config,
    headers,
    ...(modifiedCtx && { hookCtx: modifiedCtx })
  };
}

function generateRequestId(): string {
  return `req_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
}

export async function afterActionRequest(
  actionName: string,
  response: Response,
  result: any | null,
  config: ActionConfig
): Promise<void> {
  const ctx = config.hookCtx;

  // Track timing (ctx.startTime is automatically properly typed!)
  const duration = ctx?.startTime ? Date.now() - ctx.startTime : 0;

  // Log result
  if (result === null) {
    console.error(`[RPC] ${actionName} failed:`, {
      status: response.status,
      duration: `${duration}ms`
    });
  } else {
    console.log(`[RPC] ${actionName} completed:`, {
      success: result.success,
      duration: `${duration}ms`
    });
  }
}

// Validation hooks - directly use ValidationConfig (no generics needed!)
export async function beforeValidationRequest(
  actionName: string,
  config: ValidationConfig
): Promise<ValidationConfig> {
  const ctx = config.hookCtx;
  console.log(`[Validation] ${actionName} started`, { formId: ctx?.formId });
  return config;
}

export async function afterValidationRequest(
  actionName: string,
  response: Response,
  result: any | null,
  config: ValidationConfig
): Promise<void> {
  const ctx = config.hookCtx;
  console.log(`[Validation] ${actionName} completed`, {
    formId: ctx?.formId,
    hasErrors: result && !result.success
  });
}
```

```typescript
// Usage in your application
import { createTodo, validateCreateTodo } from './ash_rpc';

// Action with hooks
const result = await createTodo({
  fields: ["id", "title", "createdAt"],
  input: {
    title: "Learn AshTypescript Hooks",
    userId: getCurrentUserId()
  },
  hookCtx: {
    trackPerformance: true,
    correlationId: 'user-create-todo-123'
  }
});

// Validation with hooks
const validationResult = await validateCreateTodo({
  input: {
    title: "Test Todo",
    userId: "123e4567-e89b-12d3-a456-426614174000"
  },
  hookCtx: {
    formId: 'create-todo-form'
  }
});
```

## Channel Lifecycle Hooks

AshTypescript provides lifecycle hooks for Phoenix Channel-based RPC actions, mirroring the HTTP hooks functionality but adapted for real-time channel communication. These hooks enable the same cross-cutting concerns (logging, telemetry, performance tracking, error monitoring) but for WebSocket-based communication instead of HTTP requests.

### Why Use Channel Lifecycle Hooks?

Channel lifecycle hooks provide a centralized way to:
- **Log channel messages** - Track channel communication for debugging
- **Measure performance** - Time channel operations and track latency
- **Send telemetry** - Report metrics to monitoring services
- **Handle errors globally** - Track channel errors in Sentry, Datadog, etc.
- **Add default configuration** - Set default timeouts or other options
- **Transform messages** - Modify config before pushing to channel

### Key Differences from HTTP Hooks

Channel hooks differ from HTTP hooks because they work with Phoenix Channel's message-based communication:

| Aspect | HTTP Hooks | Channel Hooks |
|--------|-----------|---------------|
| **Communication** | Request/Response (HTTP) | Message-based (WebSocket) |
| **API Style** | Promise-based | Callback-based |
| **Response Types** | Success or Error | ok, error, or timeout |
| **Hook Names** | `beforeRequest`, `afterRequest` | `beforeChannelPush`, `afterChannelResponse` |

### Channel Configuration

Configure channel lifecycle hooks in your application config:

```elixir
# config/config.exs
config :ash_typescript,
  # Channel-based hooks for RPC actions
  rpc_action_before_channel_push_hook: "ChannelHooks.beforeChannelPush",
  rpc_action_after_channel_response_hook: "ChannelHooks.afterChannelResponse",

  # Channel-based hooks for validation actions
  rpc_validation_before_channel_push_hook: "ChannelHooks.beforeValidationChannelPush",
  rpc_validation_after_channel_response_hook: "ChannelHooks.afterValidationChannelResponse",

  # TypeScript types for channel hook context (optional)
  rpc_action_channel_hook_context_type: "ChannelHooks.ActionChannelHookContext",
  rpc_validation_channel_hook_context_type: "ChannelHooks.ValidationChannelHookContext",

  # Import the module containing your channel hook functions
  import_into_generated: [
    %{
      import_name: "ChannelHooks",
      file: "./channelHooks"
    }
  ]
```

**Configuration Options:**

| Config | Purpose | Default |
|--------|---------|---------|
| `rpc_action_before_channel_push_hook` | Function called before channel push for RPC actions | `nil` (disabled) |
| `rpc_action_after_channel_response_hook` | Function called after channel response for RPC actions | `nil` (disabled) |
| `rpc_validation_before_channel_push_hook` | Function called before channel push for validations | `nil` (disabled) |
| `rpc_validation_after_channel_response_hook` | Function called after channel response for validations | `nil` (disabled) |
| `rpc_action_channel_hook_context_type` | TypeScript type for action channel hook context | `"Record<string, any>"` |
| `rpc_validation_channel_hook_context_type` | TypeScript type for validation channel hook context | `"Record<string, any>"` |

### Channel Hook Function Signatures

Channel hooks receive the full config object and can access the optional `hookCtx` from it.

**Important:** AshTypescript exports `ActionChannelConfig` and `ValidationChannelConfig` types from the generated file. These types automatically include your custom `hookCtx` types based on your configuration settings.

#### Configuring Custom Channel Hook Context Types

When you configure channel context type settings in your Elixir config, the generated TypeScript interfaces will automatically include these types:

```elixir
# config/config.exs
config :ash_typescript,
  # TypeScript types for channel hook context
  rpc_action_channel_hook_context_type: "ChannelHooks.ActionChannelHookContext",
  rpc_validation_channel_hook_context_type: "ChannelHooks.ValidationChannelHookContext"
```

With this configuration, the generated `ActionChannelConfig` and `ValidationChannelConfig` types will have properly typed `hookCtx` fields:

```typescript
// Generated types (in your generated file)
export interface ActionChannelConfig {
  // ... other fields ...
  hookCtx?: ChannelHooks.ActionChannelHookContext;  // ← Your custom type
}

export interface ValidationChannelConfig {
  // ... other fields ...
  hookCtx?: ChannelHooks.ValidationChannelHookContext;  // ← Your custom type
}
```

#### Implementing Channel Hook Functions

Simply import and use the generated config types directly - no generics needed!

```typescript
// channelHooks.ts - Define your custom hook context interfaces
export interface ActionChannelHookContext {
  correlationId?: string;
  trackPerformance?: boolean;
  startTime?: number;
}

export interface ValidationChannelHookContext {
  formId?: string;
  validationLevel?: "strict" | "normal";
}

// Import the generated config types
import type { ActionChannelConfig, ValidationChannelConfig } from './generated';

// Implement your channel hook functions - the hookCtx is already properly typed!
export async function beforeChannelPush(
  actionName: string,
  config: ActionChannelConfig
): Promise<ActionChannelConfig> {
  const ctx = config.hookCtx;

  // ctx is automatically typed as ActionChannelHookContext | undefined
  if (ctx?.trackPerformance) {
    const modifiedCtx = { ...ctx, startTime: Date.now() };
    return { ...config, hookCtx: modifiedCtx };
  }

  return config;
}

export async function afterChannelResponse(
  actionName: string,
  responseType: "ok" | "error" | "timeout",
  data: any,  // result (for ok), error (for error), or null (for timeout)
  config: ActionChannelConfig
): Promise<void> {
  const ctx = config.hookCtx;

  // ctx.startTime is properly typed (no type assertion needed!)
  if (ctx?.trackPerformance && ctx.startTime) {
    const duration = Date.now() - ctx.startTime;
    console.log(`[Channel] ${actionName} took ${duration}ms`);
  }
}

// Similarly for validation channel hooks
export async function beforeValidationChannelPush(
  actionName: string,
  config: ValidationChannelConfig
): Promise<ValidationChannelConfig> {
  const ctx = config.hookCtx;

  if (ctx?.validationLevel === "strict") {
    console.log(`[Channel Validation] Strict mode enabled`);
  }

  return config;
}
```

**Key Benefits:**
- **Type safety** - Your custom context fields are properly typed automatically
- **IntelliSense** - IDE autocomplete works for your custom fields
- **No generics needed** - The generated types already include your context types
- **Simpler code** - Direct usage without complex generic constraints

#### Channel Config Structure

The generated `ActionChannelConfig` and `ValidationChannelConfig` interfaces include all available configuration fields:

```typescript
// Generated ActionChannelConfig interface (in your generated file)
export interface ActionChannelConfig {
  // Channel connection (required)
  channel: Channel;

  // Request parameters (varies by action)
  input?: Record<string, any>;
  primaryKey?: any;
  fields?: Array<string | Record<string, any>>;
  filter?: Record<string, any>;
  sort?: string;
  page?: { limit?: number; offset?: number; count?: boolean };

  // Metadata
  metadataFields?: Record<string, any>;

  // Channel options
  timeout?: number;

  // Handlers (required for channel operations)
  resultHandler: (result: any) => void;
  errorHandler?: (error: any) => void;
  timeoutHandler?: () => void;

  // Multitenancy
  tenant?: string;

  // Hook context (automatically typed based on your config)
  hookCtx?: YourActionChannelHookContext;
}
```

**Key Points:**
- Channel hooks support async operations (Promise-based)
- `beforeChannelPush` receives action name and config, returns modified config
- `afterChannelResponse` receives action name, response type, data, and config
- Response type distinguishes between three channel outcomes: "ok", "error", "timeout"
- Original config takes precedence over modified config
- Your custom `hookCtx` type is automatically included when you configure context type settings

### beforeChannelPush Hook

The `beforeChannelPush` hook runs **before the channel.push()** call and can modify the channel message configuration. Common use cases:

#### Setting Default Timeout

```typescript
// channelHooks.ts
export interface ActionChannelHookContext {
  useDefaultTimeout?: boolean;
  customTimeout?: number;
}

export async function beforeChannelPush(
  actionName: string,
  config: ChannelActionConfig
): Promise<ChannelActionConfig> {
  const ctx = config.hookCtx;

  // Set default timeout if not specified
  if (ctx?.useDefaultTimeout && !config.timeout) {
    return {
      ...config,
      timeout: ctx.customTimeout || 10000  // 10 second default
    };
  }

  return config;
}
```

```typescript
// Usage: Pass timeout preferences via hook context
listTodosChannel({
  channel: myChannel,
  fields: ["id", "title"],
  hookCtx: {
    useDefaultTimeout: true,
    customTimeout: 15000
  },
  resultHandler: (result) => console.log(result)
});
```

#### Logging Channel Messages

```typescript
export interface ActionChannelHookContext {
  correlationId?: string;
  trackPerformance?: boolean;
  startTime?: number;
}

export async function beforeChannelPush(
  actionName: string,
  config: ChannelActionConfig
): Promise<ChannelActionConfig> {
  const ctx = config.hookCtx;

  // Setup timing
  if (ctx?.trackPerformance && ctx) {
    ctx.startTime = Date.now();
  }

  console.log(`[Channel] Pushing to channel:`, {
    action: actionName,
    correlationId: ctx?.correlationId,
    timestamp: new Date().toISOString()
  });

  return config;
}
```

### afterChannelResponse Hook

The `afterChannelResponse` hook runs **after the channel response is received** (ok, error, or timeout) and is used for side effects. It receives four parameters:

1. `actionName: string` - The name of the action being executed
2. `responseType: "ok" | "error" | "timeout"` - The type of channel response
3. `data: any` - Response data (result for "ok", error for "error", null for "timeout")
4. `config: ChannelActionConfig` - The config used for the request

#### Logging All Channel Responses

```typescript
export async function afterChannelResponse(
  actionName: string,
  responseType: "ok" | "error" | "timeout",
  data: any,
  config: ChannelActionConfig
): Promise<void> {
  const ctx = config.hookCtx;

  console.log(`[Channel] Response received:`, {
    action: actionName,
    responseType,
    hasData: data !== null,
    correlationId: ctx?.correlationId,
    timestamp: new Date().toISOString()
  });

  // Log specific details based on response type
  if (responseType === "error") {
    console.error(`[Channel] Error in ${actionName}:`, data);
  } else if (responseType === "timeout") {
    console.warn(`[Channel] Timeout in ${actionName}`);
  }
}
```

#### Performance Timing

```typescript
export interface ActionChannelHookContext {
  startTime?: number;
  trackPerformance?: boolean;
  correlationId?: string;
}

export async function afterChannelResponse(
  actionName: string,
  responseType: "ok" | "error" | "timeout",
  data: any,
  config: ChannelActionConfig
): Promise<void> {
  const ctx = config.hookCtx;

  if (ctx?.trackPerformance && ctx.startTime) {
    const duration = Date.now() - ctx.startTime;

    console.log(`[Channel] Performance metrics:`, {
      action: actionName,
      duration: `${duration}ms`,
      responseType,
      success: responseType === "ok" && data?.success,
      correlationId: ctx?.correlationId
    });

    // Send to analytics service
    trackMetric('channel.rpc.duration', duration, {
      action: actionName,
      responseType,
      success: responseType === "ok"
    });
  }
}
```

#### Telemetry Tracking

```typescript
export async function afterChannelResponse(
  actionName: string,
  responseType: "ok" | "error" | "timeout",
  data: any,
  config: ChannelActionConfig
): Promise<void> {
  // Send telemetry to monitoring service
  sendTelemetry({
    event: 'channel.rpc.completed',
    action: actionName,
    domain: config.domain,
    responseType,
    success: responseType === "ok" && data?.success,
    timestamp: Date.now()
  });

  // Track specific response types
  if (responseType === "timeout") {
    sendTelemetry({
      event: 'channel.rpc.timeout',
      action: actionName,
      timestamp: Date.now()
    });
  }
}
```

#### Error Monitoring

```typescript
export async function afterChannelResponse(
  actionName: string,
  responseType: "ok" | "error" | "timeout",
  data: any,
  config: ChannelActionConfig
): Promise<void> {
  // Track errors in error monitoring service
  if (responseType === "error" || responseType === "timeout") {
    Sentry.captureMessage('Channel RPC failed', {
      level: 'error',
      extra: {
        action: actionName,
        responseType,
        data: responseType === "error" ? data : null,
        domain: config.domain
      }
    });
  } else if (data && !data.success) {
    // Track validation errors from successful channel responses
    Sentry.captureMessage('Channel RPC validation error', {
      level: 'warning',
      extra: {
        action: actionName,
        errors: data.errors
      }
    });
  }
}
```

### Channel Config Precedence Rules

When using `beforeChannelPush` hooks, the **original config always takes precedence** over the modified config:

```typescript
export async function beforeChannelPush(
  actionName: string,
  config: ChannelActionConfig
): Promise<ChannelActionConfig> {
  return {
    ...config,
    timeout: config.timeout ?? 10000  // ← Original timeout takes precedence
  };
}
```

**Precedence order:**
1. Original `config` values (highest priority)
2. Modified config from `beforeChannelPush` hook
3. No default timeout (lowest priority)

This ensures that per-request customizations always override hook defaults.

### Complete Channel Working Example

Here's a complete example showing all channel hook features with the simplified pattern:

```typescript
// channelHooks.ts
import type { ActionChannelConfig, ValidationChannelConfig } from './generated';

// Define custom hook context interfaces
export interface ActionChannelHookContext {
  trackPerformance?: boolean;
  startTime?: number;
  correlationId?: string;
}

export interface ValidationChannelHookContext {
  formId?: string;
  validationLevel?: "strict" | "normal";
}

// Action hooks - directly use ActionChannelConfig (no generics needed!)
export async function beforeChannelPush(
  actionName: string,
  config: ActionChannelConfig
): Promise<ActionChannelConfig> {
  const ctx = config.hookCtx;

  // Setup timing - properly update context immutably
  const modifiedCtx = ctx?.trackPerformance
    ? { ...ctx, startTime: Date.now() }
    : ctx;

  console.log(`[Channel] ${actionName} starting`, {
    correlationId: ctx?.correlationId
  });

  return {
    ...config,
    ...(modifiedCtx && { hookCtx: modifiedCtx })
  };
}

export async function afterChannelResponse(
  actionName: string,
  responseType: "ok" | "error" | "timeout",
  data: any,
  config: ActionChannelConfig
): Promise<void> {
  const ctx = config.hookCtx;

  // Track timing - ctx.startTime is automatically properly typed!
  const duration = ctx?.startTime ? Date.now() - ctx.startTime : 0;

  // Log result
  console.log(`[Channel] ${actionName} completed:`, {
    responseType,
    duration: `${duration}ms`,
    correlationId: ctx?.correlationId
  });

  // Track errors
  if (responseType !== "ok") {
    console.error(`[Channel] ${actionName} failed:`, { responseType, data });
  }
}

// Validation hooks - directly use ValidationChannelConfig (no generics needed!)
export async function beforeValidationChannelPush(
  actionName: string,
  config: ValidationChannelConfig
): Promise<ValidationChannelConfig> {
  const ctx = config.hookCtx;
  console.log(`[Channel Validation] ${actionName} started`, {
    formId: ctx?.formId,
    validationLevel: ctx?.validationLevel
  });
  return config;
}

export async function afterValidationChannelResponse(
  actionName: string,
  responseType: "ok" | "error" | "timeout",
  data: any,
  config: ValidationChannelConfig
): Promise<void> {
  const ctx = config.hookCtx;
  console.log(`[Channel Validation] ${actionName} completed`, {
    formId: ctx?.formId,
    responseType,
    hasErrors: responseType === "ok" && data && !data.success
  });
}
```

```typescript
// Usage in your application
import { listTodosChannel, createTodoChannel, validateCreateTodoChannel } from './ash_rpc';
import { Channel } from "phoenix";

// Action with channel hooks
listTodosChannel({
  channel: myChannel,
  fields: ["id", "title", { user: ["name"] }],
  hookCtx: {
    trackPerformance: true,
    correlationId: 'list-todos-123'
  },
  resultHandler: (result) => {
    if (result.success) {
      console.log("Todos loaded:", result.data);
    }
  }
});

// Validation with channel hooks
validateCreateTodoChannel({
  channel: myChannel,
  input: {
    title: "Test Todo",
    userId: "123e4567-e89b-12d3-a456-426614174000"
  },
  hookCtx: {
    formId: 'create-todo-form',
    validationLevel: 'strict'
  },
  resultHandler: (result) => {
    if (!result.success) {
      console.log("Validation errors:", result.errors);
    }
  }
});
```

## Troubleshooting

### HTTP Hooks

**Config precedence not working:**
```typescript
// ❌ Wrong: Original config gets overridden
return {
  headers: { ...config.headers, 'X-Custom': 'value' },
  ...config
};

// ✅ Correct: Original config takes precedence
return {
  ...config,
  headers: { 'X-Custom': 'value', ...config.headers }
};
```

**Performance timing not working:**
```typescript
// ❌ Wrong: Context is read-only, modifications lost
export function beforeRequest(actionName: string, config: ActionConfig): ActionConfig {
  const ctx = config.hookCtx;
  ctx.startTime = Date.now();  // Lost!
  return config;
}

// ✅ Correct: Return modified context
export function beforeRequest(actionName: string, config: ActionConfig): ActionConfig {
  const ctx = config.hookCtx || {};
  return {
    ...config,
    hookCtx: { ...ctx, startTime: Date.now() }
  };
}
```

**Hook not executing:**
- Verify hook functions are exported from the configured module
- Check that `import_into_generated` includes the hooks module
- Regenerate types with `mix ash.codegen --dev`
- Ensure hook function names match the configuration exactly

**TypeScript errors with hook context:**
```typescript
// ❌ Wrong: Type assertion on config
const ctx = config.hookCtx as ActionHookContext;
ctx.trackPerformance;  // Error if hookCtx is undefined

// ✅ Correct: Optional chaining or type guard
const ctx = config.hookCtx as ActionHookContext | undefined;
if (ctx?.trackPerformance) {
  // Safe to use
}
```

### Channel Hooks

**Config precedence not working:**
```typescript
// ❌ Wrong: Original config gets overridden
return {
  timeout: 10000,
  ...config
};

// ✅ Correct: Original config takes precedence
return {
  ...config,
  timeout: config.timeout ?? 10000
};
```

**Hook not executing:**
- Verify channel hook functions are exported from the configured module
- Check that `import_into_generated` includes the channel hooks module
- Regenerate types with `mix ash.codegen --dev`
- Ensure hook function names match the configuration exactly
- Verify that `generate_phx_channel_rpc_actions: true` is set in config

**TypeScript errors with channel hook context:**
```typescript
// ❌ Wrong: Type assertion without null check
const ctx = config.hookCtx as ActionChannelHookContext;
ctx.trackPerformance;  // Error if hookCtx is undefined

// ✅ Correct: Optional chaining or type guard
const ctx = config.hookCtx as ActionChannelHookContext | undefined;
if (ctx?.trackPerformance) {
  // Safe to use
}
```

**Response type not being handled:**
```typescript
// ✅ Handle all three response types
export async function afterChannelResponse(
  actionName: string,
  responseType: "ok" | "error" | "timeout",
  data: any,
  config: any
): Promise<void> {
  switch (responseType) {
    case "ok":
      // Handle successful response
      break;
    case "error":
      // Handle error response
      break;
    case "timeout":
      // Handle timeout response
      break;
  }
}
```
