// TypeScript test file for validating correct usage of generated types
// This file should compile without errors and demonstrates valid usage patterns

import {
  getTodo,
  listTodos,
  createTodo,
  createUser,
  updateTodo,
  validateUpdateTodo,
} from "./generated";

// Test 1: Basic nested self calculation with field selection
const basicNestedSelf = await getTodo({
  fields: ["id", "title"],
  calculations: {
    self: {
      calcArgs: { prefix: "outer_" },
      fields: ["id", "title", "completed", "dueDate"],
      calculations: {
        self: {
          calcArgs: { prefix: "inner_" },
          fields: ["id", "status", "metadata"],
        },
      },
    },
  },
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
const deepNestedSelf = await getTodo({
  fields: ["id", "description", "status"],
  calculations: {
    self: {
      calcArgs: { prefix: "level1_" },
      fields: ["title", "priority", "tags", "createdAt"],
      calculations: {
        self: {
          calcArgs: { prefix: "level2_" },
          fields: ["id", "completed", "userId"],
          calculations: {
            self: {
              calcArgs: { prefix: "level3_" },
              fields: ["description", "metadata", "dueDate"],
            },
          },
        },
      },
    },
  },
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

// Test 3: Self calculation with relationships in field selection
const selfWithRelationships = await getTodo({
  fields: ["id", "title", { user: ["id", "email"] }],
  calculations: {
    self: {
      calcArgs: { prefix: null }, // Test null prefix
      fields: [
        "id",
        "title",
        "status",
        {
          comments: ["id", "content", "rating"],
          user: ["id", "name", "email"],
        },
      ],
      calculations: {
        self: {
          calcArgs: { prefix: "nested_" },
          fields: [
            "priority",
            "tags",
            {
              user: ["id", "name"],
              comments: ["id", "authorName"],
            },
          ],
        },
      },
    },
  },
});

// Type validation for relationships in calculations
if (selfWithRelationships?.self) {
  // Outer self should have the specified relationships
  const selfUser = selfWithRelationships.self.user;
  const selfUserId: string = selfUser.id;
  const selfUserName: string = selfUser.name;
  const selfUserEmail: string = selfUser.email;

  const selfComments = selfWithRelationships.self.comments;
  if (selfComments.length > 0) {
    const firstComment = selfComments[0];
    const commentId: string = firstComment.id;
    const commentContent: string = firstComment.content;
    const commentRating: number | null | undefined = firstComment.rating;
  }

  // Nested self should have its specified relationships
  if (selfWithRelationships.self.self) {
    const nestedSelfUser = selfWithRelationships.self.self.user;
    const nestedUserId: string = nestedSelfUser.id;
    const nestedUserName: string = nestedSelfUser.name;

    const nestedComments = selfWithRelationships.self.self.comments;
    if (nestedComments.length > 0) {
      const nestedComment = nestedComments[0];
      const nestedCommentId: string = nestedComment.id;
      const nestedAuthorName: string = nestedComment.authorName;
    }
  }
}

// Test 4: List operation with nested self calculations
const listWithNestedSelf = await listTodos({
  fields: ["id", "title", "completed"],
  calculations: {
    self: {
      calcArgs: { prefix: "list_" },
      fields: ["id", "title", "status", "priority"],
      calculations: {
        self: {
          calcArgs: { prefix: "list_nested_" },
          fields: ["description", "tags", "metadata"],
        },
      },
    },
  },
});

// Type validation for list results with nested calculations
for (const todo of listWithNestedSelf) {
  // Each todo should have the basic fields
  const todoId: string = todo.id;
  const todoTitle: string = todo.title;
  const todoCompleted: boolean | null | undefined = todo.completed;

  // Each todo should have the self calculation
  if (todo.self) {
    const selfStatus: string | null | undefined = todo.self.status;
    const selfPriority: string | null | undefined = todo.self.priority;

    // Each self should have the nested self calculation
    if (todo.self.self) {
      const nestedDescription: string | null | undefined =
        todo.self.self.description;
      const nestedTags: string[] | null | undefined = todo.self.self.tags;
      const nestedMetadata: Record<string, any> | null | undefined =
        todo.self.self.metadata;
    }
  }
}

// Test 5: Create operation with nested self calculations in response
const createWithNestedSelf = await createTodo({
  input: {
    title: "Test Todo",
    status: "pending",
    userId: "user-id-123",
  },
  fields: ["id", "title", "createdAt"],
  calculations: {
    self: {
      calcArgs: { prefix: "created_" },
      fields: ["id", "title", "status", "userId"],
      calculations: {
        self: {
          calcArgs: { prefix: "created_nested_" },
          fields: ["completed", "priority", "dueDate"],
        },
      },
    },
  },
});

// Type validation for created result
const createdId: string = createWithNestedSelf.id;
const createdTitle: string = createWithNestedSelf.title;

if (createWithNestedSelf.self?.self) {
  const nestedCompleted: boolean | null | undefined =
    createWithNestedSelf.self.self.completed;
  const nestedPriority: string | null | undefined =
    createWithNestedSelf.self.self.priority;
  const nestedDueDate: string | null | undefined =
    createWithNestedSelf.self.self.dueDate;
}

// Test 6: Edge case - self calculation with minimal fields
const minimalSelf = await getTodo({
  fields: ["id"],
  calculations: {
    self: {
      calcArgs: {}, // Empty calcArgs should be valid
      fields: ["id"],
      calculations: {
        self: {
          calcArgs: { prefix: undefined }, // Undefined prefix should be valid
          fields: ["title"],
        },
      },
    },
  },
});

// Should compile successfully with minimal fields
if (minimalSelf?.self?.self) {
  const minimalTitle: string = minimalSelf.self.self.title;
}

// Test 7: Complex scenario combining multiple patterns
const complexScenario = await getTodo({
  fields: [
    "id",
    "title",
    "status",
    "isOverdue", // calculation via fields
    "commentCount", // aggregate via fields
    "helpfulCommentCount",
    {
      user: ["id", "email"],
      comments: ["id", "content", { user: ["id", "name"] }],
    },
  ],
  calculations: {
    self: {
      calcArgs: { prefix: "complex_" },
      fields: [
        "id",
        "description",
        "priority",
        "daysUntilDue", // calculation in nested self
        "helpfulCommentCount", // aggregate in nested self
        {
          user: ["id", "name", "email"],
          comments: ["id", "authorName", "rating"],
        },
      ],
      calculations: {
        self: {
          calcArgs: { prefix: "complex_nested_" },
          fields: [
            "metadata",
            "tags",
            "createdAt",
            "averageRating", // aggregate in deeply nested self
            {
              comments: ["id", "isHelpful", { user: ["id"] }],
            },
          ],
        },
      },
    },
  },
});

// Validate complex type inference
if (complexScenario) {
  // Top level
  const topIsOverdue: boolean | null | undefined = complexScenario.isOverdue;
  const topCommentCount: number = complexScenario.commentCount;

  // First level self
  if (complexScenario.self) {
    const selfDaysUntilDue: number | null | undefined =
      complexScenario.self.daysUntilDue;
    const selfHelpfulCount: number = complexScenario.self.helpfulCommentCount;

    // Second level self
    if (complexScenario.self.self) {
      const nestedAvgRating: number | null | undefined =
        complexScenario.self.self.averageRating;
      const nestedTags: string[] | null | undefined =
        complexScenario.self.self.tags;

      // Nested relationships should be properly typed
      const nestedComments = complexScenario.self.self.comments;
      if (nestedComments.length > 0) {
        const nestedComment = nestedComments[0];
        const isHelpful: boolean | null | undefined = nestedComment.isHelpful;
        const commentUser = nestedComment.user;
        const commentUserId: string = commentUser.id;
      }
    }
  }
}

// Test 8: Verify that different calcArgs types work correctly
const varyingCalcArgs = await getTodo({
  fields: ["id"],
  calculations: {
    self: {
      calcArgs: { prefix: "string_prefix" },
      fields: ["title"],
      calculations: {
        self: {
          calcArgs: { prefix: null },
          fields: ["description"],
          calculations: {
            self: {
              calcArgs: { prefix: undefined },
              fields: ["status"],
            },
          },
        },
      },
    },
  },
});

// Should handle all calcArgs variants correctly
if (varyingCalcArgs?.self?.self?.self) {
  const finalStatus: string | null | undefined =
    varyingCalcArgs.self.self.self.status;
}

console.log("All nested self calculation tests should compile successfully!");
