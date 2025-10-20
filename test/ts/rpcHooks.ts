// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Test lifecycle hooks for RPC actions and validations

export interface ActionHookContext {
  enableLogging?: boolean;
  enableTiming?: boolean;
  customHeaders?: Record<string, string>;
  startTime?: number;
}

// Config interface showing all available fields that can be in a config object
export interface ActionConfig {
  // Request data
  input?: any;
  primaryKey?: any;
  fields?: any; // Field selection
  filter?: Record<string, any>; // Filter options (for reads)
  sort?: string; // Sort options
  page?: {
    // Pagination options
    limit?: number;
    offset?: number;
    count?: boolean;
  };

  // Metadata
  metadataFields?: any; // Metadata field selection

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
  hookCtx?: ActionHookContext;

  // Internal fields (available but typically not modified)
  action?: string; // Action name
  domain?: string; // Domain name
}

export interface ValidationHookContext {
  enableLogging?: boolean;
  validationLevel?: "strict" | "normal";
}

// Validation config is similar to ActionConfig but with ValidationHookContext
export interface ValidationConfig {
  // Request data
  input?: any;

  // HTTP customization
  headers?: Record<string, string>;
  fetchOptions?: RequestInit;
  customFetch?: (
    input: RequestInfo | URL,
    init?: RequestInit,
  ) => Promise<Response>;

  // Hook context
  hookCtx?: ValidationHookContext;

  // Internal fields
  action?: string;
  domain?: string;
}

// Hook functions use generic types to support all action-specific config structures
// The ActionConfig interface above documents the common fields available

export async function beforeActionRequest<T extends ActionConfig>(
  actionName: string,
  config: T,
): Promise<T> {
  const ctx = config.hookCtx;

  if (ctx?.enableLogging) {
    console.log(`[Action beforeRequest] ${actionName}`, config);
  }

  const modifiedCtx = ctx ? { ...ctx, startTime: Date.now() } : undefined;

  const modifiedConfig: T = {
    ...config,
    ...(modifiedCtx && { hookCtx: modifiedCtx }),
  } as T;

  if (ctx?.customHeaders) {
    modifiedConfig.headers = {
      ...modifiedConfig.headers,
      ...ctx.customHeaders,
    };
  }

  modifiedConfig.fetchOptions = {
    ...modifiedConfig.fetchOptions,
    credentials: "include" as RequestCredentials,
  };

  return modifiedConfig;
}

export async function afterActionRequest<T extends ActionConfig>(
  actionName: string,
  response: Response,
  result: any,
  config: T,
): Promise<void> {
  const ctx = config.hookCtx;

  if (ctx?.enableLogging) {
    console.log(`[Action afterRequest] ${actionName}`, {
      status: response.status,
      ok: response.ok,
      result: result,
    });
  }

  if (ctx?.enableTiming && ctx.startTime) {
    const duration = Date.now() - ctx.startTime;
    console.log(`[Action Timing] Request took ${duration}ms`);
  }

  // Could throw here if desired, error boundaries will catch
  if (result && !result.success && result.errors?.length > 0) {
    // throw new Error(`Action failed: ${result.errors[0].message}`);
  }
}

export async function beforeValidationRequest<T extends ValidationConfig>(
  actionName: string,
  config: T,
): Promise<T> {
  const ctx = config.hookCtx;

  if (ctx?.enableLogging) {
    console.log(`[Validation beforeRequest] ${actionName}`, config);
  }

  return {
    ...config,
    headers: {
      ...config.headers,
      ...(ctx?.validationLevel && {
        "X-Validation-Level": ctx.validationLevel,
      }),
    },
  } as T;
}

export async function afterValidationRequest<T extends ValidationConfig>(
  actionName: string,
  response: Response,
  result: any,
  config: T,
): Promise<void> {
  const ctx = config.hookCtx;

  if (ctx?.enableLogging) {
    console.log(`[Validation afterRequest] ${actionName}`, {
      status: response.status,
      ok: response.ok,
      result: result,
    });
  }

  if (ctx?.validationLevel === "strict" && result && !result.success) {
    console.warn("[Validation] Strict mode validation failed", result.errors);
  }
}
