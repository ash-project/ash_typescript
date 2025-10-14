// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Invalid Fields Tests - shouldFail
// Tests for invalid field names and relationship fields

import {
  getTodo,
} from "../generated";

// Test 1: Invalid field names in calculations
export const invalidFieldNames = await getTodo({
  input: {},
  fields: [
    "id", "title",
    {
      self: {
        args: { prefix: "test_" },
        fields: [
          "id", "title", 
          // @ts-expect-error - "nonExistentField" should not be valid
          "nonExistentField", 
          // @ts-expect-error - "anotherBadField" should not be valid
          "anotherBadField",
          {
            self: {
              args: { prefix: "nested_" },
              fields: [
                "id", 
                // @ts-expect-error - "invalidNestedField" should not be valid
                "invalidNestedField"
              ]
            }
          }
        ]
      }
    }
  ]
});

// Test 2: Invalid top-level field names
export const invalidTopLevelFields = await getTodo({
  input: {},
  fields: [
    "id", 
    "title",
    // @ts-expect-error - "nonExistentTopLevelField" should not be valid
    "nonExistentTopLevelField",
    // @ts-expect-error - "fakeField" should not be valid
    "fakeField"
  ]
});

// Test 3: Invalid relationship field names
export const invalidRelationshipFields = await getTodo({
  input: {},
  fields: [
    "id",
    {
      self: {
        args: { prefix: "test_" },
        fields: [
          "id",
          {
            nonExistentRelation: ["id", "title"],
            user: [
              "id",
              // @ts-expect-error - "invalidUserField" should not be valid
              "invalidUserField"
            ]
          }
        ]
      }
    }
  ]
});

// Test 4: Invalid nested relationship fields
export const invalidNestedRelationshipFields = await getTodo({
  input: {},
  fields: [
    "id",
    {
      fakeRelation: ["id", "name"],
      comments: [
        "id", 
        "content",
        // @ts-expect-error - "nonExistentCommentField" should not be valid
        "nonExistentCommentField"
      ]
    }
  ]
});

// Test 5: Invalid deeply nested field access
export const deepInvalidFields = await getTodo({
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
                      // @ts-expect-error - "deepInvalidField" should not be valid
                      "deepInvalidField"
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

// Test 6: Invalid fields in relationship within calculation
export const invalidFieldsInRelationshipWithinCalc = await getTodo({
  input: {},
  fields: [
    "id",
    {
      self: {
        args: { prefix: "test_" },
        fields: [
          "id",
          "title",
          {
            comments: [
              "id",
              "content",
              // @ts-expect-error - "invalidCommentField" should not be valid
              "invalidCommentField"
            ],
            user: [
              "id",
              // @ts-expect-error - "nonExistentUserProperty" should not be valid
              "nonExistentUserProperty"
            ]
          }
        ]
      }
    }
  ]
});

console.log("Invalid fields tests should FAIL compilation!");
