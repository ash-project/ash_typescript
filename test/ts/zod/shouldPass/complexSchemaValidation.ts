// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

import { z } from "zod";
import { createTodo } from "../../generated";
import {
  createTodoZodSchema,
  TodoMetadataZodSchema,
} from "../../ash_zod";

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

  const validated = createTodoZodSchema.parse(complexTodoData);
  return validated;
}

export function testSchemaWithTransforms() {
  const transformedSchema = createTodoZodSchema
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

  const validated = createTodoZodSchema.parse(nestedData);
  return validated;
}

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

  const validated = createTodoZodSchema.parse(dataWithArrays);
  return validated;
}

export function testDateTimeValidation() {
  const dateTimeData = {
    title: "Todo with dates",
    userId: "user-123",
    dueDate: "2024-12-31T23:59:59.999Z",
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
    reminderTime: "2024-12-30T10:00:00Z",
  };

  const validated = createTodoZodSchema.parse(dateTimeData);
  return validated;
}

export function testConditionalValidation() {
  const refinedSchema = createTodoZodSchema.refine(
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
