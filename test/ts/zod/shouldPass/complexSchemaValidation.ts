// SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
//
// SPDX-License-Identifier: MIT

// Complex Schema Validation Tests - shouldPass
// Tests for advanced schema features like embedded resources, unions, and calculations

import { z } from "zod";
import {
  createTodo,
  createTodoZodschema,
  TodoMetadataZodSchema,
} from "../../generated";

// Test 1: Embedded resource schema validation
export function testEmbeddedResourceValidation() {
  const validMetadata = {
    category: "work",
    priorityScore: 8,
    tags: ["urgent", "project"],
    createdBy: "user-123",
  };

  if (TodoMetadataZodSchema) {
    const validatedMetadata = TodoMetadataZodSchema.parse(validMetadata);
    console.log("Metadata validation passed:", validatedMetadata);
    return validatedMetadata;
  }

  return validMetadata;
}

// Test 2: Union type schema validation (disabled - schema not available)
// export function testUnionTypeValidation() {
//   // Union type schemas would be tested here when available
//   console.log("Union type validation skipped - schemas not available");
//   return {};
// }

// Test 3: Complex todo creation with all fields
export function testComplexTodoCreation() {
  const complexTodoData = {
    title: "Complex Todo Item",
    description: "A todo with all possible fields filled",
    status: "in_progress",
    priority: "high",
    completed: false,
    autoComplete: true,
    userId: "user-id-123",
    dueDate: "2024-12-31T23:59:59Z",
    estimatedHours: 4.5,
    actualHours: 3.2,
    tags: ["important", "deadline", "project-x"],
    metadata: {
      category: "work",
      priorityScore: 9,
      tags: ["critical"],
      createdBy: "user-123",
    },
    content: {
      type: "text",
      content: "Detailed description of the todo item",
    },
  };

  const validated = createTodoZodschema.parse(complexTodoData);
  return validated;
}

// Test 4: Update operations with partial data (disabled - schema not available)
// export function testPartialUpdateValidation() {
//   // Update schema would be tested here when available
//   console.log("Update validation skipped - schema not available");
//   return {};
// }

// Test 5: Schema validation with transforms and defaults
export function testSchemaWithTransforms() {
  const transformedSchema = createTodoZodschema
    .omit({ userId: true })
    .extend({
      userId: z.string().default("default-user"),
    })
    .transform((data: any) => ({
      ...data,
      title: data.title.trim(),
      priority: data.priority || "medium",
      tags: data.tags || [],
    }));

  const inputData = {
    title: "  Todo with transforms  ",
    description: "Testing schema transforms",
  };

  const validated = transformedSchema.parse(inputData);
  return validated;
}

// Test 6: Nested object validation within schemas
export function testNestedObjectValidation() {
  const nestedData = {
    title: "Todo with nested metadata",
    userId: "user-123",
    metadata: {
      category: "personal",
      priorityScore: 5,
      tags: ["leisure", "optional"],
      createdBy: "user-123",
      customFields: {
        difficulty: "easy",
        estimatedTime: "2 hours",
        dependencies: ["task-1", "task-2"],
      },
    },
  };

  const validated = createTodoZodschema.parse(nestedData);
  return validated;
}

// Test 7: Array field validation
export function testArrayFieldValidation() {
  const dataWithArrays = {
    title: "Todo with arrays",
    userId: "user-123",
    tags: ["tag1", "tag2", "tag3"],
    attachments: [
      { filename: "document.pdf", size: 1024 },
      { filename: "image.png", size: 2048 },
    ],
  };

  const validated = createTodoZodschema.parse(dataWithArrays);
  return validated;
}

// Test 8: Date and time validation
export function testDateTimeValidation() {
  const dateTimeData = {
    title: "Todo with dates",
    userId: "user-123",
    dueDate: "2024-12-31T23:59:59.999Z",
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
    reminderTime: "2024-12-30T10:00:00Z",
  };

  const validated = createTodoZodschema.parse(dateTimeData);
  return validated;
}

// Test 9: Conditional validation with refinements
export function testConditionalValidation() {
  const refinedSchema = createTodoZodschema.refine(
    (data: any) => {
      if (data.priority === "urgent") {
        return data.dueDate !== undefined;
      }
      return true;
    },
    {
      message: "Urgent todos must have a due date",
      path: ["dueDate"],
    }
  );

  const urgentTodoData = {
    title: "Urgent todo",
    userId: "user-123",
    priority: "urgent",
    dueDate: "2024-12-31T23:59:59Z",
  };

  const validated = refinedSchema.parse(urgentTodoData);
  return validated;
}

// Test 10: Schema composition and merging
export function testSchemaComposition() {
  const baseSchema = z.object({
    title: z.string(),
    description: z.string().optional(),
  });

  const extendedSchema = baseSchema.extend({
    userId: z.string(),
    priority: z.enum(["low", "medium", "high", "urgent"]).optional(),
  });

  const mergedSchema = extendedSchema.merge(
    z.object({
      tags: z.array(z.string()).optional(),
      completed: z.boolean().optional(),
    })
  );

  const composedData = {
    title: "Composed schema test",
    description: "Testing schema composition",
    userId: "user-123",
    priority: "high",
    tags: ["composed", "test"],
    completed: false,
  };

  const validated = mergedSchema.parse(composedData);
  return validated;
}

console.log("Complex schema validation tests should compile successfully!");