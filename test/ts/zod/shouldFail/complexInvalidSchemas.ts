// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

import { z } from "zod";
import {
  createTodoZodSchema,
  TodoMetadataZodSchema,
} from "../../ash_zod";

export function testInvalidEmbeddedFields() {
  if (TodoMetadataZodSchema) {
    const invalidMetadata: z.infer<typeof TodoMetadataZodSchema> = {
      category: "work",
      // @ts-expect-error - priorityScore should be number, not string
      priorityScore: "high",
      tags: ["urgent"],
      createdBy: "user-123",
    };

    const invalidTags: z.infer<typeof TodoMetadataZodSchema> = {
      category: "work",
      priorityScore: 8,
      // @ts-expect-error - tags should be array of strings, not single string
      tags: "urgent",
      createdBy: "user-123",
    };

    return { invalidMetadata, invalidTags };
  }

  return {};
}

export function testInvalidNestedStructures() {
  const invalidMetadataType: z.infer<typeof createTodoZodSchema> = {
    title: "Invalid nested structure",
    userId: "user-123",
    // @ts-expect-error - metadata should be object, not array
    metadata: ["should", "be", "object"],
  };

  const invalidContentStructure: z.infer<typeof createTodoZodSchema> = {
    title: "Invalid content",
    userId: "user-123",
    content: {
      // @ts-expect-error - content should match union schema
      invalidField: "not part of any union member",
    },
  };

  return { invalidMetadataType, invalidContentStructure };
}

export function testInvalidArrayTypes() {
  const invalidTagTypes: z.infer<typeof createTodoZodSchema> = {
    title: "Invalid tags",
    userId: "user-123",
    // @ts-expect-error - tags should be array of strings, not numbers
    tags: [1, 2, 3],
  };

  const singleStringTag: z.infer<typeof createTodoZodSchema> = {
    title: "Single tag",
    userId: "user-123",
    // @ts-expect-error - tags should be array, not single string
    tags: "single-tag",
  };

  const mixedArrayTypes: z.infer<typeof createTodoZodSchema> = {
    title: "Mixed array",
    userId: "user-123",
    // @ts-expect-error - mixed array types not allowed
    tags: ["string", 123, true],
  };

  return { invalidTagTypes, singleStringTag, mixedArrayTypes };
}

export function testInvalidDateFormats() {
  const dateObjectInsteadOfString: z.infer<typeof createTodoZodSchema> = {
    title: "Invalid date format",
    userId: "user-123",
    // @ts-expect-error - dueDate should be ISO string, not Date object
    dueDate: new Date(),
  };

  const invalidDateString: z.infer<typeof createTodoZodSchema> = {
    title: "Invalid date string",
    userId: "user-123",
    // Zod validates date format at runtime, not compile time
    dueDate: "not-a-date",
  };

  const timestampNumber: z.infer<typeof createTodoZodSchema> = {
    title: "Timestamp number",
    userId: "user-123",
    // @ts-expect-error - timestamp number not allowed
    dueDate: 1640995200000,
  };

  return { dateObjectInsteadOfString, invalidDateString, timestampNumber };
}

export function testInvalidSchemaChaining() {
  const invalidChain = createTodoZodSchema
    .transform((data) => data.title)
    // @ts-expect-error - transform returns string, can't extend a non-object schema
    .extend({
      newField: z.string(),
    });

  const wrongTypeRefine = createTodoZodSchema
    .transform((data) => "string")
    // 'as any' bypasses type checking; data is string after transform, not object
    .refine((data) => (data as any).title.length > 0);

  return { invalidChain, wrongTypeRefine };
}

export function testInvalidConditionalRefinements() {
  // TypeScript can't detect non-boolean refine return at compile time
  const invalidRefineReturn = createTodoZodSchema.refine((data) => {
    return "not a boolean" as any;
  });

  const invalidErrorFormat = createTodoZodSchema.refine(
    (data) => true,
    "should be object with message property" as any
  );

  return { invalidRefineReturn, invalidErrorFormat };
}

export function testInvalidSchemaComposition() {
  // Zod allows overriding field types with extend/merge
  const conflictingExtend = createTodoZodSchema.extend({
    title: z.number(),
    userId: z.boolean(),
  });

  const incompatibleMerge = createTodoZodSchema.merge(
    z.object({
      title: z.array(z.string()),
    })
  );

  return { conflictingExtend, incompatibleMerge };
}

export function testInvalidOptionalRequiredMismatches() {
  // Partial makes all fields optional, so this is valid TypeScript
  const incorrectOptional: Partial<z.infer<typeof createTodoZodSchema>> = {};

  // @ts-expect-error - Required makes all fields mandatory but we're not providing them all
  const incorrectRequired: Required<z.infer<typeof createTodoZodSchema>> = {
    title: "Required title",
    userId: "user-123",
  };

  return { incorrectOptional, incorrectRequired };
}

console.log("Complex invalid schema tests should FAIL compilation!");
