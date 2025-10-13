// SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
//
// SPDX-License-Identifier: MIT

// Union Validation Tests - shouldFail
// Tests for invalid union field syntax

import {
  getTodo,
  createTodo,
} from "../generated";

// Test 1: Invalid union field syntax - using string instead of object notation
export const invalidUnionString = await createTodo({
  input: {
    title: "Invalid Union Syntax",
    userId: "123e4567-e89b-12d3-a456-426614174000",
    content: { note: "test" },
  },
  fields: [
    "id", 
    "title", 
    // @ts-expect-error - "content" should require object notation for union fields
    "content"
  ]
});

// Test 2: Invalid union field in getTodo
export const getWithInvalidUnionString = await getTodo({
  input: {},
  fields: [
    "id", 
    "title", 
    // @ts-expect-error - "content" should require object notation for union fields
    "content"
  ]
});

// Test 3: Invalid array union field syntax
export const invalidArrayUnionString = await createTodo({
  input: {
    title: "Invalid Array Union Syntax", 
    userId: "123e4567-e89b-12d3-a456-426614174000",
    attachments: [{ url: "https://example.com" }],
  },
  fields: [
    "id", 
    "title", 
    // @ts-expect-error - "attachments" should require object notation for union fields
    "attachments"
  ]
});

// Test 4: Invalid multiple union fields as strings
export const invalidBothUnionStrings = await createTodo({
  input: {
    title: "Invalid Both Union Syntax",
    userId: "123e4567-e89b-12d3-a456-426614174000", 
    content: { note: "test" },
    attachments: [{ url: "https://example.com" }],
  },
  fields: [
    "id", 
    "title", 
    // @ts-expect-error - "content" should require object notation
    "content", 
    // @ts-expect-error - "attachments" should require object notation
    "attachments"
  ]
});

// Test 5: Invalid union in calculation
export const invalidUnionInCalculation = await getTodo({
  input: {},
  fields: [
    "id",
    {
      self: {
        args: { prefix: "test_" },
        fields: [
          "id",
          "title",
          // @ts-expect-error - "content" should require object notation even in calculations
          "content"
        ]
      }
    }
  ]
});

// Test 6: Invalid union field with empty object
export const invalidUnionEmptyObject = await getTodo({
  input: {},
  fields: [
    "id",
    "title",
    {
      // @ts-expect-error - content object cannot be empty, must specify fields
      content: {}
    }
  ]
});

// Test 7: Invalid union field with wrong object structure
export const invalidUnionWrongStructure = await getTodo({
  input: {},
  fields: [
    "id",
    "title",
    {
      content: [
        // @ts-expect-error - "invalidMember" is not a valid union member
        "invalidMember"
      ]
    }
  ]
});

// Test 8: Invalid nested union field syntax in complex structure
export const invalidNestedUnionSyntax = await getTodo({
  input: {},
  fields: [
    "id",
    {
      self: {
        args: { prefix: "test_" },
        fields: [
          "title",
          // @ts-expect-error - "content" should require object notation
          "content",
          {
            user: ["id", "name"]
          }
        ]
      }
    }
  ]
});

// Test 9: Invalid union member field selection
export const invalidUnionMemberFields = await getTodo({
  input: {},
  fields: [
    "id",
    "title",
    {
      content: [
        {
          text: [
            "text",
            // @ts-expect-error - "nonExistentField" should not be valid for text member
            "nonExistentField"
          ]
        }
      ]
    }
  ]
});

// Test 10: Invalid array union with wrong member
export const invalidArrayUnionMember = await getTodo({
  input: {},
  fields: [
    "id",
    "title",
    {
      attachments: [
        // @ts-expect-error - "invalidAttachmentType" is not a valid union member
        "invalidAttachmentType"
      ]
    }
  ]
});

console.log("Union validation tests should FAIL compilation!");