// Type Mismatches Tests - shouldFail
// Tests for type assignment errors and invalid field access

import {
  getTodo,
  listTodos,
  createTodo,
} from "../generated";

// Test 7: Wrong type assignment from result
export const wrongTypeAssignment = await getTodo({
  fields: [
    "id", "title",
    {
      self: {
        calcArgs: { prefix: "test_" },
        fields: [
          "id", "status",
          {
            self: {
              calcArgs: { prefix: "nested_" },
              fields: ["completed"]
            }
          }
        ]
      }
    }
  ]
});

if (wrongTypeAssignment?.self?.self) {
  // @ts-expect-error - completed is boolean | null | undefined, not string
  const wrongType: string = wrongTypeAssignment.self.self.completed;
  
  // @ts-expect-error - id is string, not number
  const anotherWrongType: number = wrongTypeAssignment.self.id;
}

// Test 8: Invalid field access on calculated results
if (wrongTypeAssignment?.self) {
  // @ts-expect-error - "nonExistentProperty" should not exist on self calculation result
  const invalidAccess = wrongTypeAssignment.self.nonExistentProperty;
  
  // @ts-expect-error - "title" was not included in the fields for this calculation
  const unavailableField = wrongTypeAssignment.self.title;
}

// Test 14: Invalid function configuration - wrong input types
export const invalidFunctionConfig = await createTodo({
  input: {
    title: "Test Todo",
    // @ts-expect-error - status should be enum value, not arbitrary string
    status: "invalidStatus",
    // @ts-expect-error - userId should be string (UUID), not number
    userId: 123
  },
  fields: [
    "id", "title",
    {
      self: {
        calcArgs: { prefix: "test_" },
        // @ts-expect-error - "invalidField" should not be valid
        fields: ["id", "invalidField"]
      }
    }
  ]
});

// Test 15: Type mismatch in list operations
export const listWithWrongTypes = await listTodos({
  fields: [
    "id", "title",
    {
      self: {
        calcArgs: { prefix: "list_" },
        fields: ["id", "completed"]
      }
    }
  ]
});

// @ts-expect-error - result is array, not single object
const wrongListType: { id: string } = listWithWrongTypes;

for (const todo of listWithWrongTypes) {
  if (todo.self) {
    // @ts-expect-error - completed is boolean | null | undefined, not string
    const wrongItemType: string = todo.self.completed;
  }
}

// Test 16: Invalid enum values in field selection
export const invalidEnumInCalculation = await getTodo({
  fields: [
    "id",
    {
      self: {
        calcArgs: { prefix: "test_" },
        fields: [
          "id",
          "status", // This is valid
          // @ts-expect-error - "invalidEnumValue" should not be a valid field
          "invalidEnumValue"
        ]
      }
    }
  ]
});

console.log("Type mismatches tests should FAIL compilation!");