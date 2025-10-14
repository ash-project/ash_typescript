// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Complex Invalid Schema Tests - shouldFail
// Tests for complex invalid schema usage patterns that should fail TypeScript compilation

import { z } from "zod";
import {
  createTodoZodschema,
  TodoMetadataZodSchema,
} from "../../generated";

// Test 1: Invalid embedded resource field types
export function testInvalidEmbeddedFields() {
  if (TodoMetadataZodSchema) {
    const invalidMetadata: z.infer<typeof TodoMetadataZodSchema> = {
      category: "work",
      // @ts-expect-error - priorityScore should be number, not string
      priorityScore: "high", // Should be number
      tags: ["urgent"],
      createdBy: "user-123",
    };

    const invalidTags: z.infer<typeof TodoMetadataZodSchema> = {
      category: "work",
      priorityScore: 8,
      // @ts-expect-error - tags should be array of strings, not single string
      tags: "urgent", // Should be array
      createdBy: "user-123",
    };

    return { invalidMetadata, invalidTags };
  }

  return {};
}

// Test 2: Invalid union type discriminator (disabled - schema not available)
// export function testInvalidUnionTypes() {
//   // Union type schema errors would be tested here when available
//   console.log("Union type error testing skipped - schemas not available");
//   return {};
// }

// Test 3: Invalid complex nested object structures
export function testInvalidNestedStructures() {
  const invalidMetadataType: z.infer<typeof createTodoZodschema> = {
    title: "Invalid nested structure",
    userId: "user-123",
    // @ts-expect-error - metadata should be object, not array
    metadata: ["should", "be", "object"], // Wrong type
  };

  const invalidContentStructure: z.infer<typeof createTodoZodschema> = {
    title: "Invalid content",
    userId: "user-123",
    content: {
      // @ts-expect-error - content should match union schema
      invalidField: "not part of any union member",
    },
  };

  return { invalidMetadataType, invalidContentStructure };
}

// Test 4: Invalid array field types and structures
export function testInvalidArrayTypes() {
  const invalidTagTypes: z.infer<typeof createTodoZodschema> = {
    title: "Invalid tags",
    userId: "user-123",
    // @ts-expect-error - tags should be array of strings, not numbers
    tags: [1, 2, 3], // Should be strings
  };

  const singleStringTag: z.infer<typeof createTodoZodschema> = {
    title: "Single tag",
    userId: "user-123",
    // @ts-expect-error - tags should be array, not single string
    tags: "single-tag", // Should be array
  };

  const mixedArrayTypes: z.infer<typeof createTodoZodschema> = {
    title: "Mixed array",
    userId: "user-123",
    // @ts-expect-error - mixed array types not allowed
    tags: ["string", 123, true], // Should all be strings
  };

  return { invalidTagTypes, singleStringTag, mixedArrayTypes };
}

// Test 5: Invalid date and time formats
export function testInvalidDateFormats() {
  const dateObjectInsteadOfString: z.infer<typeof createTodoZodschema> = {
    title: "Invalid date format",
    userId: "user-123",
    // @ts-expect-error - dueDate should be ISO string, not Date object
    dueDate: new Date(), // Should be string
  };

  const invalidDateString: z.infer<typeof createTodoZodschema> = {
    title: "Invalid date string",
    userId: "user-123",
    // Note: This won't produce a compile error - Zod validates at runtime
    dueDate: "not-a-date", // Should be valid ISO string (runtime validation)
  };

  const timestampNumber: z.infer<typeof createTodoZodschema> = {
    title: "Timestamp number",
    userId: "user-123",
    // @ts-expect-error - timestamp number not allowed
    dueDate: 1640995200000, // Should be string
  };

  return { dateObjectInsteadOfString, invalidDateString, timestampNumber };
}

// Test 6: Invalid schema method chaining
export function testInvalidSchemaChaining() {
  const invalidChain = createTodoZodschema
    .transform((data) => data.title) // Returns string
    // @ts-expect-error - can't chain incompatible transformations
    .extend({ // Can't extend string
      newField: z.string(),
    });

  const wrongTypeRefine = createTodoZodschema
    .transform((data) => "string")
    // Note: Using 'as any' to bypass type checking - would error at runtime
    .refine((data) => (data as any).title.length > 0); // data is string, not object

  return { invalidChain, wrongTypeRefine };
}

// Test 7: Invalid partial schema usage with updates (disabled - schema not available)
// export function testInvalidPartialUsage() {
//   // Update schema errors would be tested here when available
//   console.log("Update schema error testing skipped - schema not available");
//   return {};
// }

// Test 8: Invalid conditional schema refinements
export function testInvalidConditionalRefinements() {
  // Note: TypeScript can't detect this return type error at compile time
  const invalidRefineReturn = createTodoZodschema.refine((data) => {
    return "not a boolean" as any; // Runtime error, not compile time
  });

  // Note: Using 'as any' bypasses type checking
  const invalidErrorFormat = createTodoZodschema.refine(
    (data) => true,
    "should be object with message property" as any // Valid with 'as any'
  );

  return { invalidRefineReturn, invalidErrorFormat };
}

// Test 9: Invalid schema composition conflicts
export function testInvalidSchemaComposition() {
  // Note: Zod allows overriding field types with extend/merge
  const conflictingExtend = createTodoZodschema.extend({
    title: z.number(), // Overrides existing string type
    userId: z.boolean(), // Overrides existing string type
  });

  const incompatibleMerge = createTodoZodschema.merge(
    z.object({
      title: z.array(z.string()), // Overrides existing string type
    })
  );

  return { conflictingExtend, incompatibleMerge };
}

// Test 10: Invalid optional vs required field mismatches
export function testInvalidOptionalRequiredMismatches() {
  // Note: These tests won't produce compile errors as Partial/Required are valid TypeScript operations
  // They're kept here for documentation purposes
  const incorrectOptional: Partial<z.infer<typeof createTodoZodschema>> = {
    // title is required but Partial makes it optional - this is actually valid TypeScript
  };

  // @ts-expect-error - Required makes all fields mandatory but we're not providing them all
  const incorrectRequired: Required<z.infer<typeof createTodoZodschema>> = {
    title: "Required title",
    userId: "user-123",
    // This will fail because not all optional fields are provided
  };

  return { incorrectOptional, incorrectRequired };
}

console.log("Complex invalid schema tests should FAIL compilation!");
