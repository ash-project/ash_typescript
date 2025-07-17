// Union Validation Tests - shouldFail
// Tests for invalid union field syntax

import {
  createTodo,
} from "../generated";

// Test 18: Invalid union field syntax - using string instead of object notation
export const invalidUnionString = await createTodo({
  input: {
    title: "Invalid Union Syntax",
    userId: "123e4567-e89b-12d3-a456-426614174000",
    content: { note: "test" },
  },
  // @ts-expect-error - "content" should require object notation for union fields
  fields: ["id", "title", "content"],
});

// Test 18b: Direct union field validation test
export const directUnionTest = await createTodo({
  input: {
    title: "Direct Union Test",
    userId: "123e4567-e89b-12d3-a456-426614174000",
    content: { note: "test" },
  },
  fields: [
    "id", 
    "title", 
    // @ts-expect-error - Type '"content"' is not assignable to type 'UnifiedFieldSelection<TodoResourceSchema>'
    "content"
  ],
});

// Test 19: Invalid array union field syntax
export const invalidArrayUnionString = await createTodo({
  input: {
    title: "Invalid Array Union Syntax", 
    userId: "123e4567-e89b-12d3-a456-426614174000",
    attachments: [{ url: "https://example.com" }],
  },
  // @ts-expect-error - "attachments" should require object notation for union fields
  fields: ["id", "title", "attachments"],
});

// Test 20: Invalid multiple union fields as strings
export const invalidBothUnionStrings = await createTodo({
  input: {
    title: "Invalid Both Union Syntax",
    userId: "123e4567-e89b-12d3-a456-426614174000", 
    content: { note: "test" },
    attachments: [{ url: "https://example.com" }],
  },
  // @ts-expect-error - Both "content" and "attachments" should require object notation
  fields: ["id", "title", "content", "attachments"],
});

console.log("Union validation tests should FAIL compilation!");