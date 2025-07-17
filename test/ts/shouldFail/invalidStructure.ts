// Invalid Structure Tests - shouldFail
// Tests for invalid nesting, missing required properties, and wrong structures

import {
  getTodo,
} from "../generated";

// Test 4: Missing required fields property in calculations
export const missingFields = await getTodo({
  fields: [
    "id",
    {
      self: {
        args: { prefix: "test_" },
        calculations: {
          self: {
            args: { prefix: "nested_" },
            fields: ["title"]
          }
        }
      }
    }
  ]
});

// Test 6: Invalid nested calculation structure
export const invalidNestedStructure = await getTodo({
  fields: [
    "id",
    {
      self: {
        args: { prefix: "test_" },
        fields: [
          "title",
          {
            // @ts-expect-error - "invalidCalculation" should not be a valid calculation
            invalidCalculation: {
              args: { prefix: "bad_" },
              fields: ["id"]
            }
          }
        ]
      }
    }
  ]
});

// Test 10: Array instead of object for calculations
export const arrayInsteadOfObject = await getTodo({
  fields: [
    "id",
    // @ts-expect-error - calculation objects should be properly structured, not arrays
    [
      {
        self: {
          args: { prefix: "test_" },
          fields: ["title"]
        }
      }
    ]
  ]
});

// Test 13: Wrong relationship structure in nested calculations
export const wrongRelationshipStructure = await getTodo({
  fields: [
    "id",
    {
      self: {
        args: { prefix: "test_" },
        fields: [
          "title",
          {
            user: ["id", "name"],
            comments: [
              "id",
              {
                invalidNesting: ["invalidField"]
              }
            ]
          }
        ]
      }
    }
  ]
});

// Test 17: Wrong calculation nesting level
export const wrongNestingLevel = await getTodo({
  fields: [
    "id",
    {
      self: {
        args: { prefix: "level1_" },
        fields: [
          "title",
          {
            self: {
              args: { prefix: "level2_" },
              fields: [
                "status",
                {
                  self: {
                    args: { prefix: "level3_" },
                    fields: [
                      "id",
                      {
                        // @ts-expect-error - "invalidDeepNesting" should not be a valid calculation
                        invalidDeepNesting: {
                          args: { prefix: "invalid_" },
                          fields: ["title"]
                        }
                      }
                    ]
                  }
                }
              ]
            }
          }
        ]
      }
    }
  ]
});

console.log("Invalid structure tests should FAIL compilation!");