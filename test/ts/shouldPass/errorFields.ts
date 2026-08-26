// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Error Field Tests - shouldPass
// Every key the RPC runtime can emit must be reachable from AshRpcError under
// --strict. An undeclared key compiles only via `as any`, which defeats the
// point of generating the type.

import { AshRpcError, listTodos } from "../generated";

// Interpolating vars into the message resolves every placeholder, because
// placeholder names track the formatted vars keys.
function interpolate(error: AshRpcError): string {
  let message = error.message;

  for (const [key, value] of Object.entries(error.vars)) {
    message = message.replace(`%{${key}}`, String(value));
  }

  return message;
}

// Test 1: every declared field is readable without a cast
export function readAllFields(error: AshRpcError) {
  const type: string = error.type;
  const message: string = error.message;
  const shortMessage: string = error.shortMessage;
  const vars: Record<string, any> = error.vars;
  const fields: string[] = error.fields;
  const path: string[] = error.path;
  const details: Record<string, any> | undefined = error.details;
  const errorId: string | undefined = error.errorId;

  return { type, message, shortMessage, vars, fields, path, details, errorId };
}

// Test 2: errorId is optional, so it narrows to string after a guard
export function correlationId(error: AshRpcError): string | null {
  if (error.errorId) {
    const id: string = error.errorId;
    return id;
  }

  return null;
}

// Test 3: the internal_error shape is assignable, with no details
export const internalError: AshRpcError = {
  type: "internal_error",
  message: "Something went wrong. Unique error id: 4f3c",
  shortMessage: "Internal error",
  vars: {},
  fields: [],
  path: [],
  errorId: "4f3c",
};

// Test 4: a validation error is assignable, with no errorId
export const validationError: AshRpcError = {
  type: "required",
  message: "is required",
  shortMessage: "Required field",
  vars: { field: "title" },
  fields: ["title"],
  path: [],
};

// Test 5: errors off a real action response carry the same type
const result = await listTodos({ fields: ["id"] });

export const errorSummary =
  result.success === false
    ? result.errors.map((error) => ({
        id: error.errorId,
        text: interpolate(error),
      }))
    : [];
