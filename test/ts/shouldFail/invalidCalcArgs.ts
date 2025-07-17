// Invalid CalcArgs Tests - shouldFail
// Tests for invalid args types, structure, and missing args

import {
  getTodo,
} from "../generated";

// Test 2: Wrong type for args prefix
export const wrongCalcArgsType = await getTodo({
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

// Test 3: Invalid args structure
export const invalidCalcArgs = await getTodo({
  fields: [
    "id",
    {
      self: {
        // @ts-expect-error - "unknownArg" is not a valid args property
        args: { prefix: "test_", unknownArg: "invalid" },
        fields: ["title"]
      }
    }
  ]
});

// Test 9: Invalid args type entirely
export const completelyWrongCalcArgs = await getTodo({
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

// Test 11: Missing args entirely
export const missingCalcArgs = await getTodo({
  fields: [
    "id",
    {
      self: {
        fields: ["title"]
      }
    }
  ]
});

console.log("Invalid args tests should FAIL compilation!");