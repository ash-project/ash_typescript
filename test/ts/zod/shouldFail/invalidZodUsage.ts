// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

import { z } from "zod";
import {
  createTodoZodSchema,
  listTodosZodSchema,
  getTodoZodSchema,
} from "../../ash_zod";

export function testInvalidTypeUsage() {
  const invalidData1: z.infer<typeof createTodoZodSchema> = {
    // @ts-expect-error - number should not be assignable to string
    title: 123,
    userId: "user-123",
  };

  const invalidData2: z.infer<typeof createTodoZodSchema> = {
    // @ts-expect-error - object should not be assignable to string
    title: { nested: "object" },
    userId: "user-123",
  };

  const invalidData3: z.infer<typeof createTodoZodSchema> = {
    title: "Valid title",
    // @ts-expect-error - array should not be assignable to string
    userId: ["array", "instead", "of", "string"],
  };

  return { invalidData1, invalidData2, invalidData3 };
}

export function testMissingRequiredFields() {
  // @ts-expect-error - missing required title field
  const missingTitle: z.infer<typeof createTodoZodSchema> = {
    userId: "user-123",
    description: "Missing title field",
  };

  // @ts-expect-error - missing required userId field
  const missingUserId: z.infer<typeof createTodoZodSchema> = {
    title: "Valid title",
    description: "Missing userId field",
  };

  // @ts-expect-error - completely empty object when required fields exist
  const emptyObject: z.infer<typeof createTodoZodSchema> = {};

  return { missingTitle, missingUserId, emptyObject };
}

export function testInvalidEnumValues() {
  const invalidPriority: z.infer<typeof createTodoZodSchema> = {
    title: "Valid title",
    userId: "user-123",
    // @ts-expect-error - "invalid_priority" is not a valid enum value
    priority: "invalid_priority",
  };

  const invalidStatus: z.infer<typeof createTodoZodSchema> = {
    title: "Valid title",
    userId: "user-123",
    // @ts-expect-error - "invalid_status" is not a valid enum value
    status: "invalid_status",
  };

  const numericPriority: z.infer<typeof createTodoZodSchema> = {
    title: "Valid title",
    userId: "user-123",
    // @ts-expect-error - number is not a valid enum value
    priority: 1,
  };

  return { invalidPriority, invalidStatus, numericPriority };
}

export function testInvalidSchemaMethodUsage() {
  // @ts-expect-error - parseSync doesn't exist on Zod schemas
  const invalidMethod1 = createTodoZodSchema.parseSync({
    title: "Valid title",
    userId: "user-123",
  });

  // @ts-expect-error - validate doesn't exist on Zod schemas
  const invalidMethod2 = createTodoZodSchema.validate({
    title: "Valid title",
    userId: "user-123",
  });

  const invalidMethod3 = (listTodosZodSchema as any).check({
    filterCompleted: true,
  });

  return { invalidMethod1, invalidMethod2, invalidMethod3 };
}

export function testInvalidSchemaComposition() {
  // Zod allows overriding field types with extend/merge
  const incompatibleExtend = createTodoZodSchema.extend({
    title: z.number(),
  });

  const invalidMerge = createTodoZodSchema.merge(
    z.object({
      title: z.boolean(),
    }),
  );

  const invalidPick = createTodoZodSchema.pick({
    // @ts-expect-error - pick with non-existent key
    nonExistentField: true,
  });

  return { incompatibleExtend, invalidMerge, invalidPick };
}

export function testWrongReturnTypes() {
  const validData = {
    title: "Valid title",
    userId: "user-123",
  };

  // @ts-expect-error - parse returns inferred type, not string
  const wrongParseType: string = createTodoZodSchema.parse(validData);

  // @ts-expect-error - safeParse returns SafeParseReturnType, not boolean
  const wrongSafeParseType: boolean = createTodoZodSchema.safeParse(validData);

  // @ts-expect-error - schema itself is not callable as function
  const schemaAsFunction = createTodoZodSchema(validData);

  return { wrongParseType, wrongSafeParseType, schemaAsFunction };
}

export function testInvalidOptionalUsage() {
  const undefinedRequired: z.infer<typeof createTodoZodSchema> = {
    // @ts-expect-error - can't assign undefined to required field
    title: undefined,
    userId: "user-123",
  };

  const nullRequired: z.infer<typeof createTodoZodSchema> = {
    title: "Valid title",
    // @ts-expect-error - can't assign null to required field
    userId: null,
  };

  return { undefinedRequired, nullRequired };
}

export function testInvalidTransformUsage() {
  // Transform can return any type, so this is actually valid
  const invalidTransform = createTodoZodSchema.transform((data) => {
    return "string";
  });

  // TypeScript can't detect non-boolean refine return at compile time
  const invalidRefine = createTodoZodSchema.refine((data) => {
    return "not a boolean" as any;
  });

  return { invalidTransform, invalidRefine };
}

console.log("Invalid Zod usage tests should FAIL compilation!");
