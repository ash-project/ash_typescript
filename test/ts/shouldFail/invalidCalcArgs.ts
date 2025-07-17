// Invalid CalcArgs Tests - shouldFail
// Tests for invalid calcArgs types, structure, and missing calcArgs

import {
  getTodo,
} from "../generated";

// Test 2: Wrong type for calcArgs prefix
export const wrongCalcArgsType = await getTodo({
  fields: [
    "id",
    {
      self: {
        // @ts-expect-error - prefix should be string | null | undefined, not number
        calcArgs: { prefix: 42 },
        fields: [
          "title",
          {
            self: {
              // @ts-expect-error - prefix should not accept boolean
              calcArgs: { prefix: true },
              fields: ["status"]
            }
          }
        ]
      }
    }
  ]
});

// Test 3: Invalid calcArgs structure
export const invalidCalcArgs = await getTodo({
  fields: [
    "id",
    {
      self: {
        // @ts-expect-error - "unknownArg" is not a valid calcArgs property
        calcArgs: { prefix: "test_", unknownArg: "invalid" },
        fields: ["title"]
      }
    }
  ]
});

// Test 9: Invalid calcArgs type entirely
export const completelyWrongCalcArgs = await getTodo({
  fields: [
    "id",
    {
      self: {
        // @ts-expect-error - calcArgs should be an object, not a string
        calcArgs: "invalid",
        fields: ["title"]
      }
    }
  ]
});

// Test 11: Missing calcArgs entirely
export const missingCalcArgs = await getTodo({
  fields: [
    "id",
    {
      self: {
        // @ts-expect-error - calcArgs is required
        fields: ["title"]
      }
    }
  ]
});

console.log("Invalid calcArgs tests should FAIL compilation!");