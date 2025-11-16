// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
//
// SPDX-License-Identifier: MIT

// Test file to verify struct field selection works properly
import { getTodo, getById } from './generated';

// Test 1: Selecting fields from a struct calculation without arguments
async function testSimpleStructFieldSelection() {
  // Should be able to select specific fields from the 'self' struct calculation
  const result = await getTodo({
    fields: [
      'id',
      'title',
      {
        self: ['id', 'title', 'completed'] // Selecting specific fields from the struct
      }
    ]
  });

  if (result.success) {
    result.data.forEach(todo => {
      // TypeScript should know that self has only the selected fields
      console.log(todo.self?.id);
      console.log(todo.self?.title);
      console.log(todo.self?.completed);

      // @ts-expect-error - description was not selected, should be an error
      console.log(todo.self?.description);
    });
  }
}

// Test 2: Selecting fields from a struct calculation with arguments
async function testStructFieldSelectionWithArgs() {
  const result = await getTodo({
    fields: [
      'id',
      'title',
      {
        self: {
          args: { prefix: 'TEST' },
          fields: ['id', 'title'] // Selecting fields with arguments
        }
      }
    ]
  });

  if (result.success) {
    result.data.forEach(todo => {
      // Should have access to selected fields
      console.log(todo.self?.id);
      console.log(todo.self?.title);

      // @ts-expect-error - completed was not selected
      console.log(todo.self?.completed);
    });
  }
}

// Test 3: Nested field selection within struct
async function testNestedStructFieldSelection() {
  const result = await getById({
    fields: [
      'id',
      'name',
      {
        self: [
          'id',
          'name',
          {
            todos: ['id', 'title'] // Nested relationship within struct
          }
        ]
      }
    ]
  });

  if (result.success) {
    result.data.forEach(user => {
      // Should have access to selected fields
      console.log(user.self?.id);
      console.log(user.self?.name);

      // Nested todos should only have selected fields
      user.self?.todos?.forEach(todo => {
        console.log(todo.id);
        console.log(todo.title);

        // @ts-expect-error - description was not selected
        console.log(todo.description);
      });
    });
  }
}

// Test 4: Mixed field selection with regular relationships and struct calculations
async function testMixedFieldSelection() {
  const result = await getTodo({
    fields: [
      'id',
      'title',
      {
        user: ['id', 'name'], // Regular relationship
        self: ['id', 'completed'] // Struct calculation
      }
    ]
  });

  if (result.success) {
    result.data.forEach(todo => {
      // Regular relationship fields
      console.log(todo.user?.id);
      console.log(todo.user?.name);

      // Struct calculation fields
      console.log(todo.self?.id);
      console.log(todo.self?.completed);

      // @ts-expect-error - title not selected on self
      console.log(todo.self?.title);
    });
  }
}

export {
  testSimpleStructFieldSelection,
  testStructFieldSelectionWithArgs,
  testNestedStructFieldSelection,
  testMixedFieldSelection
};