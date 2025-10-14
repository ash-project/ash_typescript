// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Invalid Structure Tests - shouldFail
// Tests for invalid nesting, missing required properties, and wrong structures

import {
  getTodo,
} from "../generated";

// Test 1: Invalid property name instead of fields
export const invalidPropertyInsteadOfFields = await getTodo({
  input: {},
  fields: [
    "id",
    {
      self: {
        args: { prefix: "test_" },
        // @ts-expect-error - "calculations" is not valid, should be "fields"
        calculations: ["title", "status"]
      }
    }
  ]
});

// Test 2: Missing required fields property in calculations
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

// Test 3: Invalid nested calculation structure
export const invalidNestedStructure = await getTodo({
  input: {},
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

// Test 4: Array instead of object for calculation structure
export const arrayInsteadOfObject = await getTodo({
  input: {},
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

// Test 5: Wrong property name for calculation args
export const wrongArgsProperty = await getTodo({
  input: {},
  fields: [
    "id",
    {
      self: {
        // @ts-expect-error - "arguments" is not valid, should be "args"
        arguments: { prefix: "test_" },
        fields: ["title"]
      }
    }
  ]
});

// Test 6: Wrong structure for relationship in calculation
export const wrongRelationshipStructure = await getTodo({
  input: {},
  fields: [
    "id",
    {
      self: {
        args: { prefix: "test_" },
        fields: [
          "title",
          {
            comments: [
              "id",
              {
                // @ts-expect-error - invalidNesting is not a valid field in comments
                invalidNesting: ["invalidField"]
              }
            ]
          }
        ]
      }
    }
  ]
});

// Test 7: Invalid calculation nesting
export const invalidCalculationNesting = await getTodo({
  input: {},
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

// Test 8: Fields as object instead of array
export const fieldsAsObject = await getTodo({
  input: {},
  fields: [
    "id",
    {
      self: {
        args: { prefix: "test_" },
        fields: {
          // @ts-expect-error - fields should be an array, not an object
          title: true,
          status: true
        }
      }
    }
  ]
});

// Test 9: Empty calculation object
export const emptyCalculationObject = await getTodo({
  input: {},
  fields: [
    "id",
    {
      // @ts-expect-error - calculation object cannot be empty
      self: {}
    }
  ]
});

console.log("Invalid structure tests should FAIL compilation!");
