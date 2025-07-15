// TypeScript test file for validating correct usage of generated types
// This file should compile without errors and demonstrates valid usage patterns

import {
  getTodo,
  listTodos,
  createTodo,
  createUser,
  updateTodo,
  validateUpdateTodo,
  TodoMetadataInputSchema,
  CreateTodoConfig,
  UpdateTodoConfig,
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
          fields: [
            "id", 
            "status",
            {
              metadata: ["category", "priorityScore"]
            }
          ],
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
              fields: [
                "description", 
                "dueDate",
                {
                  metadata: ["category", "tags"]
                }
              ],
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
          fields: [
            "description", 
            "tags",
            {
              metadata: ["category", "priorityScore"]
            }
          ],
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
            "tags",
            "createdAt",
            {
              metadata: ["category", "isUrgent"],
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

// ===== EMBEDDED RESOURCES TESTS =====
// These tests validate that embedded resource input types and field selection work correctly

// Test 9: Create Todo with embedded resource input
const validMetadata: TodoMetadataInputSchema = {
  category: "Work",
  priorityScore: 85,
  isUrgent: true,
  tags: ["important", "deadline"],
  deadline: "2024-12-31",
  settings: {
    notifications: true,
    auto_archive: false,
    reminder_frequency: 24
  }
};

const minimalMetadata: TodoMetadataInputSchema = {
  category: "Personal" // Only required field
};

const createWithEmbedded = await createTodo({
  input: {
    title: "Important Project Task",
    description: "Complete the quarterly report",
    status: "pending",
    priority: "high",
    userId: "123e4567-e89b-12d3-a456-426614174000",
    metadata: validMetadata
  },
  fields: [
    "id", 
    "title", 
    "status",
    {
      metadata: ["category", "priorityScore", "tags"]
    }
  ]
});

// Validate created todo has proper embedded resource structure
if (createWithEmbedded) {
  const todoId: string = createWithEmbedded.id;
  const todoTitle: string = createWithEmbedded.title;
  const todoStatus: string | null | undefined = createWithEmbedded.status;
  
  // Embedded resource should be properly typed
  if (createWithEmbedded.metadata) {
    const metadataCategory: string = createWithEmbedded.metadata.category;
    const metadataPriority: number | null | undefined = createWithEmbedded.metadata.priorityScore;
    const metadataTags: string[] | null | undefined = createWithEmbedded.metadata.tags;
  }
}

// Test 10: Update Todo with embedded resource input
const updateWithEmbedded = await updateTodo({
  primaryKey: "123e4567-e89b-12d3-a456-426614174000",
  input: {
    title: "Updated Project Task",
    metadata: minimalMetadata
  },
  fields: [
    "id", 
    "title", 
    "completed",
    {
      metadata: ["category", "priorityScore"]
    }
  ]
});

// Validate updated todo structure
if (updateWithEmbedded) {
  const updatedId: string = updateWithEmbedded.id;
  const updatedTitle: string = updateWithEmbedded.title;
  const updatedCompleted: boolean | null | undefined = updateWithEmbedded.completed;
  
  if (updateWithEmbedded.metadata) {
    const updatedCategory: string = updateWithEmbedded.metadata.category;
    // priorityScore should be optional and possibly undefined since we used minimal metadata
    const updatedPriority: number | null | undefined = updateWithEmbedded.metadata.priorityScore;
  }
}

// Test 11: Field selection with embedded resources (NEW ARCHITECTURE)
const todoWithSelectedMetadata = await getTodo({
  fields: [
    "id", 
    "title",
    {
      metadata: ["category", "priorityScore", "isUrgent"]
    }
  ],
  calculations: {
    self: {
      calcArgs: { prefix: "test_" },
      fields: [
        "id", 
        "status",
        {
          metadata: ["category", "tags"]
        }
      ]
    }
  }
});

// Validate field selection worked correctly
if (todoWithSelectedMetadata) {
  const selectedId: string = todoWithSelectedMetadata.id;
  const selectedTitle: string = todoWithSelectedMetadata.title;
  
  // metadata should be available since it was selected in embedded section
  if (todoWithSelectedMetadata.metadata) {
    // Only the selected embedded fields should be available
    const metadataCategory: string = todoWithSelectedMetadata.metadata.category;
    const metadataPriority: number | null | undefined = todoWithSelectedMetadata.metadata.priorityScore;
    const metadataIsUrgent: boolean | null | undefined = todoWithSelectedMetadata.metadata.isUrgent;
  }
  
  // Self calculation should also have metadata with selected fields
  if (todoWithSelectedMetadata.self?.metadata) {
    const selfMetadataCategory: string = todoWithSelectedMetadata.self.metadata.category;
    const selfMetadataTags: string[] | null | undefined = todoWithSelectedMetadata.self.metadata.tags;
  }
}

// Test 12: Complex scenario combining embedded resources with nested calculations (NEW ARCHITECTURE)
const complexEmbeddedScenario = await getTodo({
  fields: [
    "id", 
    "title",
    {
      metadata: ["category", "settings"],
      metadataHistory: ["category", "priorityScore"]
    }
  ],
  calculations: {
    self: {
      calcArgs: { prefix: "outer_" },
      fields: [
        "id", 
        "daysUntilDue",
        {
          metadata: ["category"]
        }
      ],
      calculations: {
        self: {
          calcArgs: { prefix: "inner_" },
          fields: [
            "status", 
            "priority",
            {
              metadata: ["category", "isUrgent"]
            }
          ]
        }
      }
    }
  }
});

// Validate complex embedded resource scenario
if (complexEmbeddedScenario) {
  // Top level embedded resources
  if (complexEmbeddedScenario.metadata) {
    const topCategory: string = complexEmbeddedScenario.metadata.category;
    const topSettings: Record<string, any> | null | undefined = complexEmbeddedScenario.metadata.settings;
  }
  
  // Array embedded resources (metadataHistory)
  if (complexEmbeddedScenario.metadataHistory) {
    const historyArray = complexEmbeddedScenario.metadataHistory;
    if (historyArray.length > 0) {
      const firstHistoryItem = historyArray[0];
      const historyCategory: string = firstHistoryItem.category;
      const historyPriority: number | null | undefined = firstHistoryItem.priorityScore;
    }
  }
  
  // Nested calculations with embedded resources
  if (complexEmbeddedScenario.self) {
    const outerDays: number | null | undefined = complexEmbeddedScenario.self.daysUntilDue;
    
    if (complexEmbeddedScenario.self.metadata) {
      const outerMetadataCategory: string = complexEmbeddedScenario.self.metadata.category;
    }
    
    // Inner nested calculation
    if (complexEmbeddedScenario.self.self) {
      const innerStatus: string | null | undefined = complexEmbeddedScenario.self.self.status;
      const innerPriority: string | null | undefined = complexEmbeddedScenario.self.self.priority;
      
      if (complexEmbeddedScenario.self.self.metadata) {
        const innerMetadataCategory: string = complexEmbeddedScenario.self.self.metadata.category;
        const innerMetadataIsUrgent: boolean | null | undefined = complexEmbeddedScenario.self.self.metadata.isUrgent;
      }
    }
  }
}

// Test 13: Validate input type constraints work correctly
const strictMetadataInput: TodoMetadataInputSchema = {
  id: "456e7890-e89b-12d3-a456-426614174000", // Optional field with default
  category: "Development", // Required field
  subcategory: "Frontend", // Optional field that allows null
  priorityScore: 92, // Optional field with default
  estimatedHours: 8.5, // Optional numeric field
  isUrgent: false, // Optional boolean with default
  status: "active", // Optional enum field
  deadline: "2024-06-30", // Optional date field
  tags: ["react", "typescript", "urgent"], // Optional array field
  customFields: { // Optional map field
    complexity: "high",
    requester: "product-team"
  }
};

const createWithStrictInput = await createTodo({
  input: {
    title: "Strict Input Test",
    userId: "789e0123-e89b-12d3-a456-426614174000",
    metadata: strictMetadataInput
  },
  fields: [
    "id",
    {
      metadata: ["category", "subcategory", "priorityScore", "tags", "customFields"]
    }
  ]
});

// Validate that all input fields were properly handled
if (createWithStrictInput?.metadata) {
  const strictCategory: string = createWithStrictInput.metadata.category;
  const strictSubcategory: string | null | undefined = createWithStrictInput.metadata.subcategory;
  const strictPriority: number | null | undefined = createWithStrictInput.metadata.priorityScore;
  const strictTags: string[] | null | undefined = createWithStrictInput.metadata.tags;
  const strictCustom: Record<string, any> | null | undefined = createWithStrictInput.metadata.customFields;
}

console.log("All embedded resource tests should compile successfully!");
