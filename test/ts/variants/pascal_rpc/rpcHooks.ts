// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
//
// SPDX-License-Identifier: MIT

// RPC lifecycle hooks of the pascal_rpc variant: the config keys they read
// and set are the PascalCase ones its generated file uses.

import type { ActionConfig, ValidationConfig } from "./generated";

export interface ActionHookContext {
  customHeaders?: Record<string, string>;
}

export interface ValidationHookContext {
  validationLevel?: "strict" | "normal";
}

export async function beforeActionRequest(
  _actionName: string,
  config: ActionConfig,
): Promise<ActionConfig> {
  return {
    ...config,
    Headers: { ...config.Headers, ...config.HookCtx?.customHeaders },
    FetchOptions: { ...config.FetchOptions, credentials: "include" },
  };
}

export async function afterActionRequest(
  _actionName: string,
  _response: Response,
  _result: any,
  _config: ActionConfig,
): Promise<void> {}

export async function beforeValidationRequest(
  _actionName: string,
  config: ValidationConfig,
): Promise<ValidationConfig> {
  const level = config.HookCtx?.validationLevel;
  return {
    ...config,
    Headers: { ...config.Headers, ...(level && { "X-Validation-Level": level }) },
  };
}

export async function afterValidationRequest(
  _actionName: string,
  _response: Response,
  _result: any,
  _config: ValidationConfig,
): Promise<void> {}
