// Invalid Fields Tests - shouldFail
// Tests for invalid field names and relationship fields

import {
  getTodo,
} from "../generated";

// Test 1: Invalid field names in calculations
export const invalidFieldNames = await getTodo({
  fields: [
    "id", "title",
    {
      self: {
        args: { prefix: "test_" },
        fields: [
          "id", "title", "nonExistentField", "anotherBadField",
          {
            self: {
              args: { prefix: "nested_" },
              // @ts-expect-error - "invalidNestedField" should not be valid
              fields: ["id", "invalidNestedField"]
            }
          }
        ]
      }
    }
  ]
});

// Test 5: Invalid relationship field names
export const invalidRelationshipFields = await getTodo({
  fields: [
    "id",
    {
      self: {
        args: { prefix: "test_" },
        fields: [
          "id",
          {
            // @ts-expect-error - "nonExistentRelation" should not be valid
            nonExistentRelation: ["id", "title"],
            user: [
              "id",
              "invalidUserField"
            ]
          }
        ]
      }
    }
  ]
});

// Test 12: Invalid deeply nested field access
export const deepInvalidFields = await getTodo({
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
                    // @ts-expect-error - "deepInvalidField" should not be valid
                    fields: ["id", "deepInvalidField"]
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

console.log("Invalid fields tests should FAIL compilation!");