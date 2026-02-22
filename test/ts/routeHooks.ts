// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
//
// SPDX-License-Identifier: MIT

// Lifecycle hooks for typed controller requests.
// Imported into generated_routes.ts via typed_controller_import_into_generated config.

import type { TypedControllerConfig } from "./generated_routes";

// Custom hook context — passed via config.hookCtx for per-request metadata
export interface RouteHookContext {
  enableLogging?: boolean;
  enableTiming?: boolean;
  customHeaders?: Record<string, string>;
  startTime?: number;
}

/**
 * Called before every typed controller request.
 * Can modify config (add headers, set fetch options, etc.)
 */
export async function beforeRequest(
  actionName: string,
  config: TypedControllerConfig,
): Promise<TypedControllerConfig> {
  const ctx = config.hookCtx;

  if (ctx?.enableLogging) {
    console.log(`[Route beforeRequest] ${actionName}`, config);
  }

  // Stamp timing start into the context so afterRequest can measure duration
  const modifiedCtx: RouteHookContext | undefined = ctx
    ? { ...ctx, startTime: Date.now() }
    : undefined;

  const modifiedConfig: TypedControllerConfig = {
    ...config,
    ...(modifiedCtx && { hookCtx: modifiedCtx }),
  };

  // Merge in any custom headers from the hook context
  if (ctx?.customHeaders) {
    modifiedConfig.headers = {
      ...modifiedConfig.headers,
      ...ctx.customHeaders,
    };
  }

  // Always include credentials
  modifiedConfig.fetchOptions = {
    ...modifiedConfig.fetchOptions,
    credentials: "include" as RequestCredentials,
  };

  return modifiedConfig;
}

/**
 * Called after every typed controller request completes.
 * Useful for logging, timing, error reporting, etc.
 */
export async function afterRequest(
  actionName: string,
  response: Response,
  config: TypedControllerConfig,
): Promise<void> {
  const ctx = config.hookCtx;

  if (ctx?.enableLogging) {
    console.log(`[Route afterRequest] ${actionName}`, {
      status: response.status,
      ok: response.ok,
    });
  }

  if (ctx?.enableTiming && ctx.startTime) {
    const duration = Date.now() - ctx.startTime;
    console.log(`[Route Timing] ${actionName} took ${duration}ms`);
  }
}
