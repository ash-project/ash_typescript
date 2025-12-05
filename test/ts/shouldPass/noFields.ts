// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Optional Fields Tests - shouldPass
// Tests for optional fields parameter in non-read actions (create, update)

import {
  createUser,
  updateUser,
  createTodo,
  updateTodo,
  listUsers,
} from "../generated";

// ============================
// CREATE ACTIONS - Optional Fields
// ============================

// Test 1: Create user without fields parameter
// This should compile successfully since fields is optional for create actions
export const createUserNoFields = await createUser({
  input: {
    name: "John Doe",
    email: "john@example.com",
  },
});

// Type validation: result should have success and data (empty object when no fields)
if (createUserNoFields.success) {
  const data: {} = createUserNoFields.data;
}

// Test 2: Create user with empty object for data (alternative way to not fetch fields)
export const createUserWithData = await createUser({
  input: {
    name: "Jane Doe",
    email: "jane@example.com",
  },
});

// Type validation
if (createUserWithData.success) {
  // Data is empty object when no fields requested
  const emptyData: {} = createUserWithData.data;
}

// Test 3: Create user with fields parameter (existing behavior)
export const createUserWithFields = await createUser({
  input: {
    name: "Bob Smith",
    email: "bob@example.com",
  },
  fields: ["id", "name", "email"],
});

// Type validation: when fields are provided, data has those fields
if (createUserWithFields.success) {
  const userId: string = createUserWithFields.data.id;
  const userName: string = createUserWithFields.data.name;
  const userEmail: string = createUserWithFields.data.email;
}

// Test 4: Create todo without fields
export const createTodoNoFields = await createTodo({
  input: {
    title: "New Todo",
    status: "pending",
    userId: "user-123",
  },
});

if (createTodoNoFields.success) {
  const data: {} = createTodoNoFields.data;
}

// Test 5: Create todo with selected fields
export const createTodoWithFields = await createTodo({
  input: {
    title: "New Todo",
    status: "pending",
    userId: "user-123",
  },
  fields: ["id", "title", "completed"],
});

if (createTodoWithFields.success) {
  const todoId: string = createTodoWithFields.data.id;
  const todoTitle: string = createTodoWithFields.data.title;
  const todoCompleted: boolean | null | undefined =
    createTodoWithFields.data.completed;
}

// ============================
// UPDATE ACTIONS - Optional Fields
// ============================

// Test 6: Update user without fields parameter
export const updateUserNoFields = await updateUser({
  identity: "user-id-123",
  input: {
    name: "Updated Name",
  },
});

// Type validation
if (updateUserNoFields.success) {
  const data: {} = updateUserNoFields.data;
}

// Test 7: Update user with fields parameter
export const updateUserWithFields = await updateUser({
  identity: "17b3279e-d1f1-11f0-993d-4ea1aae63366",
  input: {
    name: "Another Updated Name",
  },
  fields: ["id", "name", "email", "isActive"],
});

if (updateUserWithFields.success) {
  const userId: string = updateUserWithFields.data.id;
  const userName: string = updateUserWithFields.data.name;
  const userEmail: string = updateUserWithFields.data.email;
  const isActive: boolean | null | undefined =
    updateUserWithFields.data.isActive;
}

// Test 8: Update todo without fields
export const updateTodoNoFields = await updateTodo({
  identity: "todo-id-789",
  input: {
    title: "Updated Todo Title",
  },
});

if (updateTodoNoFields.success) {
  const data: {} = updateTodoNoFields.data;
}

// Test 9: Update todo with fields
export const updateTodoWithFields = await updateTodo({
  identity: "todo-id-101",
  input: {
    title: "Updated Todo",
    completed: true,
  },
  fields: ["id", "title", "completed", "status"],
});

if (updateTodoWithFields.success) {
  const todoId: string = updateTodoWithFields.data.id;
  const todoTitle: string = updateTodoWithFields.data.title;
  const todoCompleted: boolean | null | undefined =
    updateTodoWithFields.data.completed;
  const todoStatus: string | null | undefined =
    updateTodoWithFields.data.status;
}

// ============================
// READ ACTIONS - Fields Still Required
// ============================

// Test 10: List users MUST have fields (this should compile)
export const listUsersWithFields = await listUsers({
  fields: ["id", "name", "email"],
});

if (listUsersWithFields.success) {
  for (const user of listUsersWithFields.data) {
    const userId: string = user.id;
    const userName: string = user.name;
    const userEmail: string = user.email;
  }
}
