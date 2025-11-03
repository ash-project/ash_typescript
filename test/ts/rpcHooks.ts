// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Test lifecycle hooks for RPC actions and validations

import type { ActionConfig, ValidationConfig } from "./generated";

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

// Hook functions use generic types to combine ActionConfig/ValidationConfig (imported from generated)
// with custom hookCtx types for full type safety

export async function beforeActionRequest(
  actionName: string,
  config: ActionConfig,
): Promise<ActionConfig> {
  const ctx = config.hookCtx;

  if (ctx?.enableLogging) {
    console.log(`[Action beforeRequest] ${actionName}`, config);
  }

  const modifiedCtx = ctx ? { ...ctx, startTime: Date.now() } : undefined;

  const modifiedConfig: ActionConfig = {
    ...config,
    ...(modifiedCtx && { hookCtx: modifiedCtx }),
  };

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

export async function afterActionRequest(
  actionName: string,
  response: Response,
  result: any,
  config: ActionConfig,
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

export async function beforeValidationRequest(
  actionName: string,
  config: ValidationConfig,
): Promise<ValidationConfig> {
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
  };
}

export async function afterValidationRequest(
  actionName: string,
  response: Response,
  result: any,
  config: ValidationConfig,
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
