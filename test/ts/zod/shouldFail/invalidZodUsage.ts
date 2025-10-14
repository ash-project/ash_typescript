// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Invalid Zod Schema Usage Tests - shouldFail
// Tests for invalid schema usage patterns that should fail TypeScript compilation

import { z } from "zod";
import {
  createTodoZodschema,
  listTodosZodschema,
  getTodoZodschema,
} from "../../generated";

// Test 1: Using schema with wrong property types (should fail compilation)
export function testInvalidTypeUsage() {
  const invalidData1: z.infer<typeof createTodoZodschema> = {
    // @ts-expect-error - number should not be assignable to string  
    title: 123, // Wrong type
    userId: "user-123",
  };

  const invalidData2: z.infer<typeof createTodoZodschema> = {
    // @ts-expect-error - object should not be assignable to string
    title: { nested: "object" }, // Wrong type
    userId: "user-123",
  };

  const invalidData3: z.infer<typeof createTodoZodschema> = {
    title: "Valid title",
    // @ts-expect-error - array should not be assignable to string
    userId: ["array", "instead", "of", "string"], // Wrong type
  };

  return { invalidData1, invalidData2, invalidData3 };
}

// Test 2: Missing required fields (should fail compilation)
export function testMissingRequiredFields() {
  // @ts-expect-error - missing required title field
  const missingTitle: z.infer<typeof createTodoZodschema> = {
    userId: "user-123",
    description: "Missing title field",
  };

  // @ts-expect-error - missing required userId field
  const missingUserId: z.infer<typeof createTodoZodschema> = {
    title: "Valid title",
    description: "Missing userId field",
  };

  // @ts-expect-error - completely empty object when required fields exist
  const emptyObject: z.infer<typeof createTodoZodschema> = {};

  return { missingTitle, missingUserId, emptyObject };
}

// Test 3: Invalid enum values (should fail compilation)
export function testInvalidEnumValues() {
  const invalidPriority: z.infer<typeof createTodoZodschema> = {
    title: "Valid title",
    userId: "user-123",
    // @ts-expect-error - "invalid_priority" is not a valid enum value
    priority: "invalid_priority",
  };

  const invalidStatus: z.infer<typeof createTodoZodschema> = {
    title: "Valid title",
    userId: "user-123",
    // @ts-expect-error - "invalid_status" is not a valid enum value
    status: "invalid_status",
  };

  const numericPriority: z.infer<typeof createTodoZodschema> = {
    title: "Valid title",
    userId: "user-123",
    // @ts-expect-error - number is not a valid enum value
    priority: 1,
  };

  return { invalidPriority, invalidStatus, numericPriority };
}

// Test 4: Incorrect schema method usage (should fail compilation)
export function testInvalidSchemaMethodUsage() {
  // @ts-expect-error - parseSync doesn't exist on Zod schemas
  const invalidMethod1 = createTodoZodschema.parseSync({
    title: "Valid title",
    userId: "user-123",
  });

  // @ts-expect-error - validate doesn't exist on Zod schemas
  const invalidMethod2 = createTodoZodschema.validate({
    title: "Valid title",
    userId: "user-123",
  });

  // Note: Using 'as any' to demonstrate invalid method usage
  const invalidMethod3 = (listTodosZodschema as any).check({
    filterCompleted: true,
  });

  return { invalidMethod1, invalidMethod2, invalidMethod3 };
}

// Test 5: Invalid schema composition (should fail compilation)
export function testInvalidSchemaComposition() {
  // Note: These operations are actually valid in Zod (it will override the field types)
  const incompatibleExtend = createTodoZodschema.extend({
    title: z.number(), // Overrides existing string type
  });

  const invalidMerge = createTodoZodschema.merge(
    z.object({
      title: z.boolean(), // Overrides existing string type
    }),
  );

  const invalidPick = createTodoZodschema.pick({
    // @ts-expect-error - pick with non-existent key
    nonExistentField: true,
  });

  return { incompatibleExtend, invalidMerge, invalidPick };
}

// Test 6: Wrong return types from schema methods (should fail compilation)
export function testWrongReturnTypes() {
  const validData = {
    title: "Valid title",
    userId: "user-123",
  };

  // @ts-expect-error - parse returns inferred type, not string
  const wrongParseType: string = createTodoZodschema.parse(validData);

  // @ts-expect-error - safeParse returns SafeParseReturnType, not boolean
  const wrongSafeParseType: boolean = createTodoZodschema.safeParse(validData);

  // @ts-expect-error - schema itself is not callable as function
  const schemaAsFunction = createTodoZodschema(validData);

  return { wrongParseType, wrongSafeParseType, schemaAsFunction };
}

// Test 7: Invalid optional field usage (should fail compilation)
export function testInvalidOptionalUsage() {
  const undefinedRequired: z.infer<typeof createTodoZodschema> = {
    // @ts-expect-error - can't assign undefined to required field
    title: undefined, // title is required
    userId: "user-123",
  };

  const nullRequired: z.infer<typeof createTodoZodschema> = {
    title: "Valid title",
    // @ts-expect-error - can't assign null to required field
    userId: null, // userId is required
  };

  return { undefinedRequired, nullRequired };
}

// Test 8: Invalid schema transformation usage (should fail compilation)
export function testInvalidTransformUsage() {
  // Note: Transform can return any type, so this is actually valid
  const invalidTransform = createTodoZodschema.transform((data) => {
    return "string"; // Valid - transform can change the type
  });

  // Note: TypeScript can't detect this return type error at compile time
  const invalidRefine = createTodoZodschema.refine((data) => {
    return "not a boolean" as any; // Runtime error, not compile time
  });

  return { invalidTransform, invalidRefine };
}

console.log("Invalid Zod usage tests should FAIL compilation!");
