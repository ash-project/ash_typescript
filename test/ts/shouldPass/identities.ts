// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

/**
 * Tests for identity-based record lookups in update/destroy actions.
 *
 * This file tests the `identities` option which allows configuring
 * which identities can be used to look up records:
 * - Primary key (direct value for non-composite, object for composite)
 * - Named identities (wrapped in object like { email: "..." })
 */

import {
  updateUser,
  updateUserByIdentity,
  updateUserByEmail,
  updateSubscriptionByUserStatus,
  destroySubscriptionByUserStatus,
  UUID,
} from "../generated";

// Test 1: Update by primary key - direct UUID value (default identities: [:_primary_key])
export const updateByPrimaryKey = await updateUser({
  identity: "user-uuid-here",
  input: {
    name: "Updated Name",
  },
  fields: ["id", "name", "email"],
});

// Test 2: Update by identity with email - uses email identity (identities: [:_primary_key, :email])
export const updateByIdentityWithEmail = await updateUserByIdentity({
  identity: { email: "user@example.com" },
  input: {
    name: "Updated via Email",
  },
  fields: ["id", "name", "email"],
});

// Test 3: Update by email only - must use email object (identities: [:email])
export const updateByEmailOnly = await updateUserByEmail({
  identity: { email: "user@example.com" },
  input: {
    name: "Updated by Email Only",
  },
  fields: ["id", "name", "email"],
});

// Type-level tests to ensure correct typing

// This should compile: primary key identity with UUID
const _pkIdentity: Parameters<typeof updateUser>[0]["identity"] =
  "some-uuid" as UUID;

// This should compile: multiple identities with UUID
const _multiIdentityPk: Parameters<typeof updateUserByIdentity>[0]["identity"] =
  "some-uuid" as UUID;

// This should compile: multiple identities with email object
const _multiIdentityEmail: Parameters<
  typeof updateUserByIdentity
>[0]["identity"] = { email: "test@example.com" };

// This should compile: email-only identity
const _emailOnlyIdentity: Parameters<typeof updateUserByEmail>[0]["identity"] =
  { email: "test@example.com" };

// =============================================================================
// Tests for identity with field_names mapped fields (Subscription resource)
// =============================================================================
// The Subscription resource has an identity :by_user_and_status on [:user_id, :is_active?]
// where is_active? is mapped via field_names: is_active?: :is_active
// After output formatting (camelCase), the identity type should be: { userId: UUID; isActive: boolean }

// Test 4: Update subscription by user status - identity uses mapped field names
export const updateSubscriptionByIdentity =
  await updateSubscriptionByUserStatus({
    identity: {
      userId: "user-uuid-here",
      isActive: true,
    },
    input: {
      plan: "enterprise",
    },
    fields: ["id", "plan", "isActive"],
  });

// Test 5: Destroy subscription by user status - identity uses mapped field names
export const destroySubscriptionByIdentity =
  await destroySubscriptionByUserStatus({
    identity: {
      userId: "user-uuid-here",
      isActive: false,
    },
  });

// Type-level tests for mapped identity field names

// This should compile: identity type with userId (UUID) and isActive (boolean)
const _subscriptionIdentity: Parameters<
  typeof updateSubscriptionByUserStatus
>[0]["identity"] = {
  userId: "some-uuid",
  isActive: true,
};

// This should compile: destroy uses same identity type
const _subscriptionDestroyIdentity: Parameters<
  typeof destroySubscriptionByUserStatus
>[0]["identity"] = {
  userId: "some-uuid",
  isActive: false,
};
