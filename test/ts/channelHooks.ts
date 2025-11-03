// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

import type { ActionChannelConfig, ValidationChannelConfig } from "./generated";

// Custom hook context interfaces for type safety
export interface ActionChannelHookContext {
  enableAuth?: boolean;
  authToken?: string;
  trackPerformance?: boolean;
  startTime?: number;
  correlationId?: string;
}

export interface ValidationChannelHookContext {
  formId?: string;
  validationLevel?: "strict" | "normal";
}

export async function beforeChannelPush(
  actionName: string,
  config: ActionChannelConfig,
): Promise<ActionChannelConfig> {
  const ctx = config.hookCtx;

  if (ctx?.trackPerformance) {
    ctx.startTime = Date.now();
  }

  console.log(`[Channel beforeChannelPush] ${actionName}`, {
    correlationId: ctx?.correlationId,
  });

  // Can modify config (e.g., set default timeout)
  const modifiedConfig: ActionChannelConfig = {
    ...config,
    timeout: config.timeout ?? 10000, // Default 10s timeout
  };

  return modifiedConfig;
}

export async function afterChannelResponse(
  actionName: string,
  responseType: "ok" | "error" | "timeout",
  data: any,
  config: ActionChannelConfig,
): Promise<void> {
  const ctx = config.hookCtx;

  // Track timing
  if (ctx?.trackPerformance && ctx.startTime) {
    const duration = Date.now() - ctx.startTime;
    console.log(`[Channel afterChannelResponse] ${actionName}`, {
      responseType,
      duration: `${duration}ms`,
      correlationId: ctx?.correlationId,
    });
  }

  // Log errors
  if (responseType === "error") {
    console.error(`[Channel] Error in ${actionName}:`, data);
  }

  // Log timeouts
  if (responseType === "timeout") {
    console.warn(`[Channel] Timeout in ${actionName}`);
  }
}

export async function beforeValidationChannelPush(
  actionName: string,
  config: ValidationChannelConfig,
): Promise<ValidationChannelConfig> {
  const ctx = config.hookCtx;

  console.log(`[Validation Channel beforePush] ${actionName}`, {
    formId: ctx?.formId,
    validationLevel: ctx?.validationLevel,
  });

  return {
    ...config,
    timeout: config.timeout ?? 5000, // Shorter timeout for validations
  };
}

export async function afterValidationChannelResponse(
  actionName: string,
  responseType: "ok" | "error" | "timeout",
  data: any,
  config: ValidationChannelConfig,
): Promise<void> {
  const ctx = config.hookCtx;

  console.log(`[Validation Channel afterResponse] ${actionName}`, {
    responseType,
    formId: ctx?.formId,
    hasErrors: responseType === "ok" && data && !data.success,
  });
}
