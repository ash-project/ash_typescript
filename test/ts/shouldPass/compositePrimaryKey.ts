// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Composite Primary Key Tests - shouldPass
// Tests that composite primary key identity types are correctly generated

import {
  updateTenantSetting,
  destroyTenantSetting,
  validateUpdateTenantSetting,
  validateDestroyTenantSetting,
} from "../generated";

// Test 1: Update with composite primary key - uses typed identity
await updateTenantSetting({
  identity: {
    tenantId: "550e8400-e29b-41d4-a716-446655440000",
    settingKey: "theme",
  },
  input: { value: "dark" },
  fields: ["tenantId", "settingKey", "value"],
});

// Test 2: Destroy with composite primary key - uses typed identity
await destroyTenantSetting({
  identity: {
    tenantId: "550e8400-e29b-41d4-a716-446655440000",
    settingKey: "language",
  },
});

// Test 3: Validation functions use string types for all identity fields
// These are client-side only and not tested via RPC runtime validation
function testValidationTypes() {
  // Validation with composite primary key - uses string types (not UUID)
  validateUpdateTenantSetting({
    identity: {
      tenantId: "any-string-value",
      settingKey: "theme",
    },
    input: { value: "light" },
  });

  validateDestroyTenantSetting({
    identity: {
      tenantId: "any-string-value",
      settingKey: "language",
    },
  });
}

// Verify type inference works correctly
async function testTypeInference() {
  const result = await updateTenantSetting({
    identity: {
      tenantId: "550e8400-e29b-41d4-a716-446655440000",
      settingKey: "theme",
    },
    input: { value: "updated" },
    fields: ["tenantId", "settingKey", "value"],
  });

  if (result.success) {
    const tenantId: string = result.data.tenantId;
    const settingKey: string = result.data.settingKey;
    const value: string = result.data.value;
    console.log(tenantId, settingKey, value);
  }
}

export { testValidationTypes, testTypeInference };
