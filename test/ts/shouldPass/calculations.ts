// Calculations Tests - shouldPass
// Tests for self calculations, nested calculations, and calcArgs variations

import {
  getTodo,
} from "../generated";

// Test 1: Basic nested self calculation with field selection
export const basicNestedSelf = await getTodo({
  fields: [
    "id",
    "title",
    {
      self: {
        calcArgs: { prefix: "outer_" },
        fields: [
          "id",
          "title",
          "completed",
          "dueDate",
          {
            self: {
              calcArgs: { prefix: "inner_" },
              fields: [
                "id",
                "status",
                {
                  metadata: ["category", "priorityScore"],
                },
              ],
            },
          },
        ],
      },
    },
  ],
});

// Type assertion: basicNestedSelf should have properly typed nested structure
if (basicNestedSelf?.self) {
  // Outer self calculation should have the specified fields
  const outerId: string = basicNestedSelf.self.id;
  const outerTitle: string = basicNestedSelf.self.title;
  const outerCompleted: boolean | null | undefined =
    basicNestedSelf.self.completed;
  const outerDueDate: string | null | undefined = basicNestedSelf.self.dueDate;

  // Inner nested self calculation should have its specified fields
  if (basicNestedSelf.self.self) {
    const innerId: string = basicNestedSelf.self.self.id;
    const innerStatus: string | null | undefined =
      basicNestedSelf.self.self.status;
    const innerMetadata: Record<string, any> | null | undefined =
      basicNestedSelf.self.self.metadata;
  }
}

// Test 2: Deep nesting with different field combinations at each level
export const deepNestedSelf = await getTodo({
  fields: [
    "id",
    "description",
    "status",
    {
      self: {
        calcArgs: { prefix: "level1_" },
        fields: [
          "title",
          "priority",
          "tags",
          "createdAt",
          {
            self: {
              calcArgs: { prefix: "level2_" },
              fields: [
                "id",
                "completed",
                "userId",
                {
                  self: {
                    calcArgs: { prefix: "level3_" },
                    fields: [
                      "description",
                      "dueDate",
                      {
                        metadata: ["category", "tags"],
                      },
                    ],
                  },
                },
              ],
            },
          },
        ],
      },
    },
  ],
});

// Type validation for deep nested structure
if (deepNestedSelf?.self?.self?.self) {
  // Level 3 (deepest) should only have the fields specified in level 3
  const level3Description: string | null | undefined =
    deepNestedSelf.self.self.self.description;
  const level3Metadata: Record<string, any> | null | undefined =
    deepNestedSelf.self.self.self.metadata;
  const level3DueDate: string | null | undefined =
    deepNestedSelf.self.self.self.dueDate;
}

// Test 6: Edge case - self calculation with minimal fields
export const minimalSelf = await getTodo({
  fields: [
    "id",
    {
      self: {
        calcArgs: {}, // Empty calcArgs should be valid
        fields: [
          "id",
          {
            self: {
              calcArgs: { prefix: undefined }, // Undefined prefix should be valid
              fields: ["title"],
            },
          },
        ],
      },
    },
  ],
});

// Should compile successfully with minimal fields
if (minimalSelf?.self?.self) {
  const minimalTitle: string = minimalSelf.self.self.title;
}

// Test 8: Verify that different calcArgs types work correctly
export const varyingCalcArgs = await getTodo({
  fields: [
    "id",
    {
      self: {
        calcArgs: { prefix: "string_prefix" },
        fields: [
          "title",
          {
            self: {
              calcArgs: { prefix: null },
              fields: [
                "description",
                {
                  self: {
                    calcArgs: { prefix: undefined },
                    fields: ["status"],
                  },
                },
              ],
            },
          },
        ],
      },
    },
  ],
});

// Should handle all calcArgs variants correctly
if (varyingCalcArgs?.self?.self?.self) {
  const finalStatus: string | null | undefined =
    varyingCalcArgs.self.self.self.status;
}

console.log("Calculations tests should compile successfully!");