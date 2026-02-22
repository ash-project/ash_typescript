// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

import { z } from "zod";
import {
  createTodoZodSchema,
  listTodosZodSchema,
  getTodoZodSchema,
} from "../../ash_zod";

export function testCreateTodoValidation() {
  const validCreateData = {
    title: "Complete project",
    description: "Finish the TypeScript generation feature",
    status: "pending",
    userId: "user-id-123",
  };

  const validatedData = createTodoZodSchema.parse(validCreateData);
  console.log("Create todo validation passed:", validatedData);

  return validatedData;
}

export function testListTodosValidation() {
  const validListData = {
    filterCompleted: true,
    priorityFilter: "high",
  };

  const validatedListData = listTodosZodSchema.parse(validListData);
  console.log("List todos validation passed:", validatedListData);

  return validatedListData;
}

export function testMinimalValidation() {
  const minimalCreateData = {
    title: "Minimal todo",
    userId: "user-id-123",
  };

  const validated = createTodoZodSchema.parse(minimalCreateData);
  return validated;
}

export function testGetTodoValidation() {
  const emptyInput = {};
  const validatedInput = getTodoZodSchema.parse(emptyInput);

  return validatedInput;
}

export function testFullValidation() {
  const fullCreateData = {
    title: "Complete todo",
    description: "A fully specified todo item",
    status: "pending",
    priority: "high",
    completed: false,
    autoComplete: true,
    userId: "user-id-123",
    dueDate: "2024-12-31",
  };

  const validated = createTodoZodSchema.parse(fullCreateData);
  return validated;
}

export type CreateTodoInput = z.infer<typeof createTodoZodSchema>;
export type ListTodosInput = z.infer<typeof listTodosZodSchema>;
export type GetTodoInput = z.infer<typeof getTodoZodSchema>;

export function validateCreateInput(input: unknown): CreateTodoInput {
  return createTodoZodSchema.parse(input);
}

export function validateListInput(input: unknown): ListTodosInput {
  return listTodosZodSchema.parse(input);
}

export function testSafeParsing() {
  const validData = {
    title: "Test todo",
    userId: "user-123",
  };

  const result = createTodoZodSchema.safeParse(validData);

  if (result.success) {
    const data: CreateTodoInput = result.data;
    return data;
  } else {
    throw new Error("Unexpected validation failure");
  }
}

export function testSchemaRefinement() {
  const schema = createTodoZodSchema.refine(
    (data: any) => data.title.length > 0,
    { message: "Title cannot be empty" },
  );

  const validData = {
    title: "Valid title",
    userId: "user-123",
  };

  return schema.parse(validData);
}

export function testSchemaTransformation() {
  const transformedSchema = createTodoZodSchema.transform((data: any) => ({
    ...data,
    title: data.title.trim(),
    priority: data.priority || "medium",
  }));

  const inputData = {
    title: "  Trimmed title  ",
    userId: "user-123",
  };

  return transformedSchema.parse(inputData);
}

console.log("Basic Zod usage tests should compile successfully!");
