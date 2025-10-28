// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Type Inference Tests for Optional Fields
// Validates that TypeScript correctly infers empty object type when fields are omitted

import { createUser, updateUser } from "../generated";

// Test 1: When fields is omitted, data should be typed as {}
export const createUserNoFieldsInferred = await createUser({
  input: {
    name: "Test User",
    email: "test@example.com",
  },
});

if (createUserNoFieldsInferred.success) {
  // TypeScript should infer data as InferResult<UserResourceSchema, []> which is {}
  const data: {} = createUserNoFieldsInferred.data;
  // This should compile - empty object type
  const isEmpty = Object.keys(data).length === 0;

  // @ts-expect-error - Should NOT have id property when no fields requested
  const shouldNotExist = createUserNoFieldsInferred.data.id;
}

// Test 2: When fields is explicitly [], data should also be typed as {}
export const createUserEmptyFieldsInferred = await createUser({
  input: {
    name: "Test User 2",
    email: "test2@example.com",
  },
  fields: [],
});

if (createUserEmptyFieldsInferred.success) {
  const data: {} = createUserEmptyFieldsInferred.data;

  // @ts-expect-error - Should NOT have name property when fields is empty
  const shouldNotExist = createUserEmptyFieldsInferred.data.name;
}

// Test 3: When fields are provided, data should have those specific fields
export const createUserWithFieldsInferred = await createUser({
  input: {
    name: "Test User 3",
    email: "test3@example.com",
  },
  fields: ["id", "name"],
});

if (createUserWithFieldsInferred.success) {
  // These properties SHOULD exist
  const id: string = createUserWithFieldsInferred.data.id;
  const name: string = createUserWithFieldsInferred.data.name;

  // @ts-expect-error - email was not requested so should not exist on type
  const shouldNotExist = createUserWithFieldsInferred.data.email;
}

// Test 4: Update actions should have the same behavior
export const updateUserNoFieldsInferred = await updateUser({
  primaryKey: "user-id",
  input: {
    name: "Updated Name",
  },
});

if (updateUserNoFieldsInferred.success) {
  const data: {} = updateUserNoFieldsInferred.data;

  // @ts-expect-error - Should NOT have properties when no fields
  const shouldNotExist = updateUserNoFieldsInferred.data.id;
}

console.log("Type inference tests for optional fields compiled successfully!");
