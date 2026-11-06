// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
//
// SPDX-License-Identifier: MIT

// Validation functions of get_by rpc_actions take the lookup fields as a
// required `getBy`, over HTTP and channels.

import { Channel } from "phoenix";
import {
  validateGetTodoByUserAndStatus,
  validateGetUserByEmail,
  validateGetUserByEmailChannel,
  ValidationResult,
} from "../generated";

export const byEmail: ValidationResult = await validateGetUserByEmail({
  getBy: { email: "alice@example.com" },
});

export const byUserAndStatus: ValidationResult = await validateGetTodoByUserAndStatus({
  getBy: { userId: "123e4567-e89b-12d3-a456-426614174000", status: "pending" },
});

if (!byEmail.success) {
  const messages: string[] = byEmail.errors.map((error) => error.message);
  console.log(messages);
}

export function overChannel(channel: Channel) {
  validateGetUserByEmailChannel({
    channel,
    getBy: { email: "alice@example.com" },
    resultHandler: (result: ValidationResult) => console.log(result.success),
  });
}
