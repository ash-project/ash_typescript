// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

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

// Channel config interface showing all available fields
export interface ChannelConfig {
  // Request data
  input?: any;
  primaryKey?: any;
  fields?: any;
  filter?: Record<string, any>;
  sort?: string;
  page?: {
    limit?: number;
    offset?: number;
    count?: boolean;
  };

  // Metadata
  metadataFields?: any;

  // Channel-specific
  channel: any; // Phoenix Channel
  resultHandler: (result: any) => void;
  errorHandler?: (error: any) => void;
  timeoutHandler?: () => void;
  timeout?: number;

  // Multitenancy
  tenant?: string;

  // Hook context
  hookCtx?: ActionChannelHookContext;

  // Internal fields
  action?: string;
  domain?: string;
}

export async function beforeChannelPush<T extends ChannelConfig>(
  actionName: string,
  config: T,
): Promise<T> {
  const ctx = config.hookCtx;

  if (ctx?.trackPerformance) {
    ctx.startTime = Date.now();
  }

  console.log(`[Channel beforeChannelPush] ${actionName}`, {
    correlationId: ctx?.correlationId,
  });

  // Can modify config (e.g., set default timeout)
  const modifiedConfig: T = {
    ...config,
    timeout: config.timeout ?? 10000, // Default 10s timeout
  } as T;

  return modifiedConfig;
}

export async function afterChannelResponse<T extends ChannelConfig>(
  actionName: string,
  responseType: "ok" | "error" | "timeout",
  data: any,
  config: T,
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

export async function beforeValidationChannelPush<
  T extends {
    hookCtx?: ValidationChannelHookContext;
    timeout?: number;
    action?: string;
  },
>(actionName: string, config: T): Promise<T> {
  const ctx = config.hookCtx;

  console.log(`[Validation Channel beforePush] ${actionName}`, {
    formId: ctx?.formId,
    validationLevel: ctx?.validationLevel,
  });

  return {
    ...config,
    timeout: config.timeout ?? 5000, // Shorter timeout for validations
  } as T;
}

export async function afterValidationChannelResponse<
  T extends {
    hookCtx?: ValidationChannelHookContext;
    action?: string;
  },
>(
  actionName: string,
  responseType: "ok" | "error" | "timeout",
  data: any,
  config: T,
): Promise<void> {
  const ctx = config.hookCtx;

  console.log(`[Validation Channel afterResponse] ${actionName}`, {
    responseType,
    formId: ctx?.formId,
    hasErrors: responseType === "ok" && data && !data.success,
  });
}
