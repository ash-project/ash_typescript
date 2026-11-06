// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
//
// SPDX-License-Identifier: MIT

// Channel lifecycle hooks of the pascal_rpc variant: the config keys they
// read and set are the PascalCase ones its generated file uses.

import type { ActionChannelConfig, ValidationChannelConfig } from "./generated";

export interface ActionChannelHookContext {
  correlationId?: string;
}

export interface ValidationChannelHookContext {
  formId?: string;
}

export async function beforeChannelPush(
  _actionName: string,
  config: ActionChannelConfig,
): Promise<ActionChannelConfig> {
  return {
    ...config,
    Timeout: config.Timeout ?? 10000,
    ResultHandler: (result: any) => config.ResultHandler(result),
  };
}

export async function afterChannelResponse(
  _actionName: string,
  _responseType: "ok" | "error" | "timeout",
  _data: any,
  _config: ActionChannelConfig,
): Promise<void> {}

export async function beforeValidationChannelPush(
  _actionName: string,
  config: ValidationChannelConfig,
): Promise<ValidationChannelConfig> {
  return { ...config, Timeout: config.Timeout ?? 5000 };
}

export async function afterValidationChannelResponse(
  _actionName: string,
  _responseType: "ok" | "error" | "timeout",
  _data: any,
  _config: ValidationChannelConfig,
): Promise<void> {}
