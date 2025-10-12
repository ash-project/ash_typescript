// SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
//
// SPDX-License-Identifier: MIT

// Invalid CalcArgs Tests - shouldFail
// Tests for invalid args types, structure, and missing args

import {
  getTodo,
} from "../generated";

// Test 1: Wrong type for args prefix
export const wrongCalcArgsType = await getTodo({
  input: {},
  fields: [
    "id",
    {
      self: {
        // @ts-expect-error - prefix should be string | null | undefined, not number
        args: { prefix: 42 },
        fields: [
          "title",
          {
            self: {
              // @ts-expect-error - prefix should not accept boolean
              args: { prefix: true },
              fields: ["status"]
            }
          }
        ]
      }
    }
  ]
});

// Test 2: Invalid args structure
export const invalidCalcArgs = await getTodo({
  input: {},
  fields: [
    "id",
    {
      self: {
        args: { prefix: "test_", unknownArg: "invalid" },
        fields: ["title"]
      }
    }
  ]
});

// Test 3: Invalid args type entirely
export const completelyWrongCalcArgs = await getTodo({
  input: {},
  fields: [
    "id",
    {
      self: {
        // @ts-expect-error - args should be an object, not a string
        args: "invalid",
        fields: ["title"]
      }
    }
  ]
});

// Test 4: args as array instead of object
export const argsAsArray = await getTodo({
  input: {},
  fields: [
    "id",
    {
      self: {
        // @ts-expect-error - args should be an object, not an array
        args: ["prefix", "test_"],
        fields: ["title"]
      }
    }
  ]
});

// Test 5: args as null (should be valid or omitted entirely)
export const argsAsNull = await getTodo({
  input: {},
  fields: [
    "id",
    {
      self: {
        // @ts-expect-error - args should not be null, should be omitted or valid object
        args: null,
        fields: ["title"]
      }
    }
  ]
});

// Test 6: Missing fields property entirely (this should fail)
export const missingFieldsProperty = await getTodo({
  input: {},
  fields: [
    "id",
    {
      // @ts-expect-error - fields property is required
      self: {
        args: { prefix: "test_" }
      }
    }
  ]
});

console.log("Invalid args tests should FAIL compilation!");