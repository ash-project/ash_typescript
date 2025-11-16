// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
//
// SPDX-License-Identifier: MIT

// Test file to verify struct field selection works for calculations with Ash.Type.Struct
import { getTodo } from './generated';

// This test verifies that struct-typed calculations with instance_of constraint
// support field selection similar to relationships

async function test() {
  // The 'self' calculation returns a struct with instance_of: TodoResourceSchema
  // We should be able to select specific fields from it
  const result = await getTodo({
    input: {},  // Empty input for read action
    fields: [
      'id',
      'title',
      {
        self: {
          args: { prefix: 'TEST' },
          fields: ['id', 'title', 'completed']
        }
      }
    ]
  });

  if (result.success && result.data) {
    // TypeScript should know that self has the selected fields
    const todo = result.data;

    // These should work - selected fields
    console.log(todo.id);
    console.log(todo.title);

    if (todo.self) {
      console.log(todo.self.id);
      console.log(todo.self.title);
      console.log(todo.self.completed);

      // @ts-expect-error - description was not selected for self
      console.log(todo.self.description);
    }
  }
}

// Test 2: Using field selection without args (when args are optional)
async function testWithoutArgs() {
  const result = await getTodo({
    input: {},  // Empty input for read action
    fields: [
      'id',
      {
        // When using field selection, we need to specify the structure
        self: {
          args: {},  // Empty args
          fields: ['id', 'title']
        }
      }
    ]
  });

  if (result.success && result.data) {
    const todo = result.data;

    if (todo.self) {
      console.log(todo.self.id);
      console.log(todo.self.title);

      // @ts-expect-error - completed was not selected
      console.log(todo.self.completed);
    }
  }
}

export { test, testWithoutArgs };
