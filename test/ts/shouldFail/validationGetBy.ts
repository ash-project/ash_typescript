// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
//
// SPDX-License-Identifier: MIT

// Validation functions of get_by rpc_actions require `getBy` and its
// fields.

import { Channel } from "phoenix";
import { validateGetUserByEmail, validateGetUserByEmailChannel } from "../generated";

// @ts-expect-error - getBy is required
export const withoutGetBy = await validateGetUserByEmail({});

export const wrongField = await validateGetUserByEmail({
  // @ts-expect-error - name is not a getBy field
  getBy: { name: "Alice" },
});

export function overChannel(channel: Channel) {
  // @ts-expect-error - getBy is required over channels too
  validateGetUserByEmailChannel({
    channel,
    resultHandler: () => {},
  });
}
