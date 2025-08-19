// Type Mismatches Tests - shouldFail
// Tests for type assignment errors and invalid field access

import {
  getTodo,
  listTodos,
  createTodo,
} from "../generated";

// Test 1: Wrong type assignment from result
export const wrongTypeAssignment = await getTodo({
  input: {},
  fields: [
    "id", "title",
    {
      self: {
        args: { prefix: "test_" },
        fields: [
          "id", "status",
          {
            self: {
              args: { prefix: "nested_" },
              fields: ["completed"]
            }
          }
        ]
      }
    }
  ]
});

if (wrongTypeAssignment.success && wrongTypeAssignment.data?.self?.self) {
  // @ts-expect-error - completed is boolean | null | undefined, not string
  const wrongType: string = wrongTypeAssignment.data.self.self.completed;
  
  // @ts-expect-error - id is string, not number
  const anotherWrongType: number = wrongTypeAssignment.data.self.id;
}

// Test 2: Invalid field access on calculated results
if (wrongTypeAssignment.success && wrongTypeAssignment.data?.self) {
  // @ts-expect-error - "nonExistentProperty" should not exist on self calculation result
  const invalidAccess = wrongTypeAssignment.data.self.nonExistentProperty;
  
  // @ts-expect-error - title was not selected in self calculation, should not be available
  const unavailableField = wrongTypeAssignment.data.self.title;
}

// Test 3: Invalid function configuration - wrong input types
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
        args: { prefix: "test_" },
        fields: [
          "id", 
          // @ts-expect-error - "invalidField" should not be valid
          "invalidField"
        ]
      }
    }
  ]
});

// Test 4: Type mismatch in list operations
export const listWithWrongTypes = await listTodos({
  input: {},
  fields: [
    "id", "title",
    {
      self: {
        args: { prefix: "list_" },
        fields: ["id", "completed"]
      }
    }
  ]
});

if (listWithWrongTypes.success) {
  // @ts-expect-error - result is paginated object, not single object
  const wrongListType: { id: string } = listWithWrongTypes.data;

  if (listWithWrongTypes.data && Array.isArray(listWithWrongTypes.data)) {
    for (const todo of listWithWrongTypes.data) {
      if (todo.self) {
        const wrongItemType: string = todo.self.completed;
      }
    }
  }
}

// Test 5: Invalid field access with wrong assumptions
export const testResultAccess = await getTodo({
  input: {},
  fields: ["id", "title"]
});

if (testResultAccess.success && testResultAccess.data) {
  // @ts-expect-error - description was not selected, should not be available
  const notSelected: string = testResultAccess.data.description;
  
  // @ts-expect-error - id is string, not number
  const wrongIdType: number = testResultAccess.data.id;
}

// Test 6: Invalid input parameter types for read actions
export const invalidReadInputTypes = await listTodos({
  input: {
    // @ts-expect-error - filterCompleted should be boolean, not string
    filterCompleted: "true",
    // @ts-expect-error - priorityFilter should be enum value, not arbitrary string
    priorityFilter: "invalid_priority"
  },
  fields: ["id", "title"]
});

// Test 7: Invalid input parameter names for read actions  
export const invalidReadInputNames = await listTodos({
  input: {
    filterCompleted: true,
    // @ts-expect-error - nonExistentParam should not exist
    nonExistentParam: "value"
  },
  fields: ["id", "title"]
});

// Test 8: Wrong enum values for priorityFilter
export const wrongEnumInReadInput = await listTodos({
  input: {
    filterCompleted: false,
    // @ts-expect-error - "super_high" is not a valid priority value
    priorityFilter: "super_high"
  },
  fields: ["id", "title"]
});

// Test 9: Type mismatch in createTodo input
export const createTodoTypeMismatch = await createTodo({
  input: {
    // @ts-expect-error - title should be string, not number
    title: 42,
    userId: "123e4567-e89b-12d3-a456-426614174000",
    completed: "false"
  },
  fields: ["id", "title"]
});

// Test 10: Wrong type for primaryKey in updates
export const wrongPrimaryKeyType = await getTodo({
  // @ts-expect-error - primaryKey is not a valid parameter for getTodo
  primaryKey: 42,
  fields: ["id", "title"]
});

console.log("Type mismatches tests should FAIL compilation!");