// TypeScript test file for validating INCORRECT usage patterns
// This file should FAIL to compile and demonstrates invalid usage that should be caught by TypeScript

import {
  getTodo,
  listTodos,
  createTodo,
  createUser,
  updateTodo,
} from "./generated";

// Test 1: Invalid field names in calculations
const invalidFieldNames = await getTodo({
  fields: [
    "id", "title",
    {
      self: {
        calcArgs: { prefix: "test_" },
        // @ts-expect-error - "nonExistentField" should not be valid
        fields: [
          "id", "title", "nonExistentField", "anotherBadField",
          {
            self: {
              calcArgs: { prefix: "nested_" },
              // @ts-expect-error - "invalidNestedField" should not be valid
              fields: ["id", "invalidNestedField"]
            }
          }
        ]
      }
    }
  ]
});

// Test 2: Wrong type for calcArgs prefix
const wrongCalcArgsType = await getTodo({
  fields: [
    "id",
    {
      self: {
        // @ts-expect-error - prefix should be string | null | undefined, not number
        calcArgs: { prefix: 42 },
        fields: [
          "title",
          {
            self: {
              // @ts-expect-error - prefix should not accept boolean
              calcArgs: { prefix: true },
              fields: ["status"]
            }
          }
        ]
      }
    }
  ]
});

// Test 3: Invalid calcArgs structure
const invalidCalcArgs = await getTodo({
  fields: [
    "id",
    {
      self: {
        // @ts-expect-error - "unknownArg" is not a valid calcArgs property
        calcArgs: { prefix: "test_", unknownArg: "invalid" },
        fields: ["title"]
      }
    }
  ]
});

// Test 4: Missing required fields property in calculations
const missingFields = await getTodo({
  fields: [
    "id",
    {
      self: {
        calcArgs: { prefix: "test_" },
        // @ts-expect-error - "fields" property is required
        calculations: {
          self: {
            calcArgs: { prefix: "nested_" },
            fields: ["title"]
          }
        }
      }
    }
  ]
});

// Test 5: Invalid relationship field names
const invalidRelationshipFields = await getTodo({
  fields: [
    "id",
    {
      self: {
        calcArgs: { prefix: "test_" },
        fields: [
          "id",
          {
            // @ts-expect-error - "nonExistentRelation" should not be valid
            nonExistentRelation: ["id", "title"],
            user: [
              "id",
              // @ts-expect-error - "invalidUserField" should not be valid on user
              "invalidUserField"
            ]
          }
        ]
      }
    }
  ]
});

// Test 6: Invalid nested calculation structure
const invalidNestedStructure = await getTodo({
  fields: [
    "id",
    {
      self: {
        calcArgs: { prefix: "test_" },
        fields: [
          "title",
          {
            // @ts-expect-error - "invalidCalculation" should not be a valid calculation
            invalidCalculation: {
              calcArgs: { prefix: "bad_" },
              fields: ["id"]
            }
          }
        ]
      }
    }
  ]
});

// Test 7: Wrong type assignment from result
const wrongTypeAssignment = await getTodo({
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

// Test 9: Invalid calcArgs type entirely
const completelyWrongCalcArgs = await getTodo({
  fields: [
    "id",
    {
      self: {
        // @ts-expect-error - calcArgs should be an object, not a string
        calcArgs: "invalid",
        fields: ["title"]
      }
    }
  ]
});

// Test 10: Array instead of object for calculations
const arrayInsteadOfObject = await getTodo({
  fields: [
    "id",
    // @ts-expect-error - calculation objects should be properly structured, not arrays
    [
      {
        self: {
          calcArgs: { prefix: "test_" },
          fields: ["title"]
        }
      }
    ]
  ]
});

// Test 11: Missing calcArgs entirely
const missingCalcArgs = await getTodo({
  fields: [
    "id",
    {
      self: {
        // @ts-expect-error - calcArgs is required
        fields: ["title"]
      }
    }
  ]
});

// Test 12: Invalid deeply nested field access
const deepInvalidFields = await getTodo({
  fields: [
    "id",
    {
      self: {
        calcArgs: { prefix: "level1_" },
        fields: [
          "title",
          {
            self: {
              calcArgs: { prefix: "level2_" },
              fields: [
                "status",
                {
                  self: {
                    calcArgs: { prefix: "level3_" },
                    // @ts-expect-error - "deepInvalidField" should not be valid
                    fields: ["id", "deepInvalidField"]
                  }
                }
              ]
            }
          }
        ]
      }
    }
  ]
});

// Test 13: Wrong relationship structure in nested calculations
const wrongRelationshipStructure = await getTodo({
  fields: [
    "id",
    {
      self: {
        calcArgs: { prefix: "test_" },
        fields: [
          "title",
          {
            user: ["id", "name"],
            comments: [
              "id",
              {
                // @ts-expect-error - nested relationships should follow proper structure
                invalidNesting: ["invalidField"]
              }
            ]
          }
        ]
      }
    }
  ]
});

// Test 14: Invalid function configuration - wrong input types
const invalidFunctionConfig = await createTodo({
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
const listWithWrongTypes = await listTodos({
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
const invalidEnumInCalculation = await getTodo({
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

// Test 17: Wrong calculation nesting level
const wrongNestingLevel = await getTodo({
  fields: [
    "id",
    {
      self: {
        calcArgs: { prefix: "level1_" },
        fields: [
          "title",
          {
            self: {
              calcArgs: { prefix: "level2_" },
              fields: [
                "status",
                {
                  self: {
                    calcArgs: { prefix: "level3_" },
                    fields: [
                      "id",
                      {
                        // @ts-expect-error - "invalidDeepNesting" should not be a valid calculation
                        invalidDeepNesting: {
                          calcArgs: { prefix: "invalid_" },
                          fields: ["title"]
                        }
                      }
                    ]
                  }
                }
              ]
            }
          }
        ]
      }
    }
  ]
});

console.log("This file should NOT compile due to TypeScript errors!");