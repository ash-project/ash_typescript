// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
//
// SPDX-License-Identifier: MIT

// GetBy Tests - shouldFail
// Every getBy key is required, including keys named by a field_names mapping

import { getSubscriptionByUserAndActive } from "../generated";

// isActive (is_active? -> isActive) is a required getBy key
export const missingMappedGetByKey = await getSubscriptionByUserAndActive({
  // @ts-expect-error - isActive is missing from getBy
  getBy: {
    userId: "00000000-0000-0000-0000-000000000001",
  },
  fields: ["id"],
});
