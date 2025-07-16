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
const deepNestedSelf = await getTodo({
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

// Test 3: Self calculation with relationships in field selection
const selfWithRelationships = await getTodo({
  fields: [
    "id",
    "title",
    { user: ["id", "email"] },
    {
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
          {
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
        ],
      },
    },
  ],
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
  fields: [
    "id",
    "title",
    "completed",
    {
      self: {
        calcArgs: { prefix: "list_" },
        fields: [
          "id",
          "title",
          "status",
          "priority",
          {
            self: {
              calcArgs: { prefix: "list_nested_" },
              fields: [
                "description",
                "tags",
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

// Test: Union field selection with primitive members
const todoWithPrimitiveUnion = await getTodo({
  fields: [
    "id",
    "title",
    {
      content: ["note", "priorityValue"], // Only primitive union members
    },
  ],
});

// Type validation for primitive union selection
if (todoWithPrimitiveUnion?.content) {
  // Should have only the requested primitive union members
  if ("note" in todoWithPrimitiveUnion.content) {
    const noteValue: string = todoWithPrimitiveUnion.content.note;
  }
  if ("priorityValue" in todoWithPrimitiveUnion.content) {
    const priorityValue: number = todoWithPrimitiveUnion.content.priorityValue;
  }
}

// Test: Union field selection with complex members
const todoWithComplexUnion = await getTodo({
  fields: [
    "id",
    "title",
    {
      content: [
        {
          text: ["id", "text", "wordCount"], // Complex union member with field selection
        },
      ],
    },
  ],
});

// Type validation for complex union selection
if (todoWithComplexUnion?.content) {
  if ("text" in todoWithComplexUnion.content) {
    const textContent = todoWithComplexUnion.content.text;
    const textId: string = textContent.id;
    const textValue: string = textContent.text;
    const wordCount: number = textContent.wordCount;
    // Should NOT have formatting field since it wasn't requested
  }
}

// Test: Mixed union field selection
const todoWithMixedUnion = await getTodo({
  fields: [
    "id",
    "title",
    {
      content: [
        "note", // Primitive member
        {
          text: ["text", "formatting"], // Complex member with field selection
        },
        "priorityValue", // Another primitive member
      ],
    },
  ],
});

// Type validation for mixed union selection
if (todoWithMixedUnion?.content) {
  if ("note" in todoWithMixedUnion.content) {
    const noteValue: string = todoWithMixedUnion.content.note;
  }
  if ("text" in todoWithMixedUnion.content) {
    const textContent = todoWithMixedUnion.content.text;
    const textValue: string = textContent.text;
    const formatting: string = textContent.formatting;
    // Should NOT have other fields like wordCount
  }
  if ("priorityValue" in todoWithMixedUnion.content) {
    const priorityValue: number = todoWithMixedUnion.content.priorityValue;
  }
}

// Test 5: Create operation with nested self calculations in response
const createWithNestedSelf = await createTodo({
  input: {
    title: "Test Todo",
    status: "pending",
    userId: "user-id-123",
  },
  fields: [
    "id",
    "title",
    "createdAt",
    {
      self: {
        calcArgs: { prefix: "created_" },
        fields: [
          "id",
          "title",
          "status",
          "userId",
          {
            self: {
              calcArgs: { prefix: "created_nested_" },
              fields: ["completed", "priority", "dueDate"],
            },
          },
        ],
      },
    },
  ],
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
    {
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
          {
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
        ],
      },
    },
  ],
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
    autoArchive: false,
    reminderFrequency: 24,
  },
};

const minimalMetadata: TodoMetadataInputSchema = {
  category: "Personal", // Only required field
};

const createWithEmbedded = await createTodo({
  input: {
    title: "Important Project Task",
    description: "Complete the quarterly report",
    status: "pending",
    priority: "high",
    userId: "123e4567-e89b-12d3-a456-426614174000",
    metadata: validMetadata,
  },
  fields: [
    "id",
    "title",
    "status",
    {
      metadata: ["category", "priorityScore", "tags"],
    },
  ],
});

// Validate created todo has proper embedded resource structure
if (createWithEmbedded) {
  const todoId: string = createWithEmbedded.id;
  const todoTitle: string = createWithEmbedded.title;
  const todoStatus: string | null | undefined = createWithEmbedded.status;

  // Embedded resource should be properly typed
  if (createWithEmbedded.metadata) {
    const metadataCategory: string = createWithEmbedded.metadata.category;
    const metadataPriority: number | null | undefined =
      createWithEmbedded.metadata.priorityScore;
    const metadataTags: string[] | null | undefined =
      createWithEmbedded.metadata.tags;
  }
}

// Test 10: Update Todo with embedded resource input
const updateWithEmbedded = await updateTodo({
  primaryKey: "123e4567-e89b-12d3-a456-426614174000",
  input: {
    title: "Updated Project Task",
    metadata: minimalMetadata,
  },
  fields: [
    "id",
    "title",
    "completed",
    {
      metadata: ["category", "priorityScore"],
    },
  ],
});

// Validate updated todo structure
if (updateWithEmbedded) {
  const updatedId: string = updateWithEmbedded.id;
  const updatedTitle: string = updateWithEmbedded.title;
  const updatedCompleted: boolean | null | undefined =
    updateWithEmbedded.completed;

  if (updateWithEmbedded.metadata) {
    const updatedCategory: string = updateWithEmbedded.metadata.category;
    // priorityScore should be optional and possibly undefined since we used minimal metadata
    const updatedPriority: number | null | undefined =
      updateWithEmbedded.metadata.priorityScore;
  }
}

// Test 11: Field selection with embedded resources (NEW ARCHITECTURE)
const todoWithSelectedMetadata = await getTodo({
  fields: [
    "id",
    "title",
    {
      metadata: ["category", "priorityScore", "isUrgent"],
    },
    {
      self: {
        calcArgs: { prefix: "test_" },
        fields: [
          "id",
          "status",
          {
            metadata: ["category", "tags"],
          },
        ],
      },
    },
  ],
});

// Validate field selection worked correctly
if (todoWithSelectedMetadata) {
  const selectedId: string = todoWithSelectedMetadata.id;
  const selectedTitle: string = todoWithSelectedMetadata.title;

  // metadata should be available since it was selected in embedded section
  if (todoWithSelectedMetadata.metadata) {
    // Only the selected embedded fields should be available
    const metadataCategory: string = todoWithSelectedMetadata.metadata.category;
    const metadataPriority: number | null | undefined =
      todoWithSelectedMetadata.metadata.priorityScore;
    const metadataIsUrgent: boolean | null | undefined =
      todoWithSelectedMetadata.metadata.isUrgent;
  }

  // Self calculation should also have metadata with selected fields
  if (todoWithSelectedMetadata.self?.metadata) {
    const selfMetadataCategory: string =
      todoWithSelectedMetadata.self.metadata.category;
    const selfMetadataTags: string[] | null | undefined =
      todoWithSelectedMetadata.self.metadata.tags;
  }
}

// Test 12: Complex scenario combining embedded resources with nested calculations (NEW ARCHITECTURE)
const complexEmbeddedScenario = await getTodo({
  fields: [
    "id",
    "title",
    {
      metadata: ["category", "settings"],
      metadataHistory: ["category", "priorityScore"],
    },
    {
      self: {
        calcArgs: { prefix: "outer_" },
        fields: [
          "id",
          "daysUntilDue",
          {
            metadata: ["category"],
          },
          {
            self: {
              calcArgs: { prefix: "inner_" },
              fields: [
                "status",
                "priority",
                {
                  metadata: ["category", "isUrgent"],
                },
              ],
            },
          },
        ],
      },
    },
  ],
});

// Validate complex embedded resource scenario
if (complexEmbeddedScenario) {
  // Top level embedded resources
  if (complexEmbeddedScenario.metadata) {
    const topCategory: string = complexEmbeddedScenario.metadata.category;
    const topSettings: Record<string, any> | null | undefined =
      complexEmbeddedScenario.metadata.settings;
  }

  // Array embedded resources (metadataHistory)
  if (complexEmbeddedScenario.metadataHistory) {
    const historyArray = complexEmbeddedScenario.metadataHistory;
    if (historyArray.length > 0) {
      const firstHistoryItem = historyArray[0];
      const historyCategory: string = firstHistoryItem.category;
      const historyPriority: number | null | undefined =
        firstHistoryItem.priorityScore;
    }
  }

  // Nested calculations with embedded resources
  if (complexEmbeddedScenario.self) {
    const outerDays: number | null | undefined =
      complexEmbeddedScenario.self.daysUntilDue;

    if (complexEmbeddedScenario.self.metadata) {
      const outerMetadataCategory: string =
        complexEmbeddedScenario.self.metadata.category;
    }

    // Inner nested calculation
    if (complexEmbeddedScenario.self.self) {
      const innerStatus: string | null | undefined =
        complexEmbeddedScenario.self.self.status;
      const innerPriority: string | null | undefined =
        complexEmbeddedScenario.self.self.priority;

      if (complexEmbeddedScenario.self.self.metadata) {
        const innerMetadataCategory: string =
          complexEmbeddedScenario.self.self.metadata.category;
        const innerMetadataIsUrgent: boolean | null | undefined =
          complexEmbeddedScenario.self.self.metadata.isUrgent;
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
  customFields: {
    // Optional map field
    complexity: "high",
    requester: "product-team",
  },
};

const createWithStrictInput = await createTodo({
  input: {
    title: "Strict Input Test",
    userId: "789e0123-e89b-12d3-a456-426614174000",
    metadata: strictMetadataInput,
  },
  fields: [
    "id",
    {
      metadata: [
        "category",
        "subcategory",
        "priorityScore",
        "tags",
        "customFields",
      ],
    },
  ],
});

// Validate that all input fields were properly handled
if (createWithStrictInput?.metadata) {
  const strictCategory: string = createWithStrictInput.metadata.category;
  const strictSubcategory: string | null | undefined =
    createWithStrictInput.metadata.subcategory;
  const strictPriority: number | null | undefined =
    createWithStrictInput.metadata.priorityScore;
  const strictTags: string[] | null | undefined =
    createWithStrictInput.metadata.tags;
  const strictCustom: Record<string, any> | null | undefined =
    createWithStrictInput.metadata.customFields;
}

console.log("All embedded resource tests should compile successfully!");

// ===== UNION TYPES TESTS =====
// These tests validate that union type generation and usage work correctly

// Test 14: Union type with embedded resources - text content
const todoWithTextContent = await createTodo({
  input: {
    title: "Text Content Todo",
    userId: "123e4567-e89b-12d3-a456-426614174000",
    content: {
      text: {
        id: "text-content-1",
        text: "This is text content with formatting",
        wordCount: 7,
        formatting: "markdown",
      },
    },
  },
  fields: [
    "id",
    "title",
    { content: ["note", { text: ["id", "text", "wordCount", "formatting"] }] },
  ],
});

const todoWithFail = await createTodo({
  input: {
    title: "Text Content Todo",
    userId: "123e4567-e89b-12d3-a456-426614174000",
    content: {
      text: {
        id: "text-content-1",
        text: "This is text content with formatting",
        wordCount: 7,
        formatting: "markdown",
      },
    },
  },
  fields: [
    "id", 
    "title", 
    { content: [{ text: ["id", "text", "wordCount", "formatting"] }] }
  ],
});

// Validate text content union type - now using FieldsSchema
if (todoWithTextContent?.content) {
  // Content should be a union type with optional members
  if (todoWithTextContent.content.text) {
    const textData = todoWithTextContent.content.text;
    
    // Type casting checks - these should compile without errors
    const textContent: string = textData.text;
    const textId: string = textData.id;
    const wordCount: number | null | undefined = textData.wordCount;
    const formatting: string | null | undefined = textData.formatting;
    
    // Verify union field selection worked - should only have requested fields
    const hasOnlyRequestedFields = Object.keys(textData).every(key => 
      ["id", "text", "wordCount", "formatting"].includes(key)
    );
  }
}

// Test 15: Union type with embedded resources - checklist content
const todoWithChecklistContent = await createTodo({
  input: {
    title: "Checklist Todo",
    userId: "123e4567-e89b-12d3-a456-426614174000",
    content: {
      checklist: {
        id: "checklist-content-1",
        title: "Project Checklist",
        items: [
          {
            text: "Design mockups",
            completed: true,
            createdAt: "2024-01-01T00:00:00Z",
          },
          {
            text: "Implement backend",
            completed: false,
            createdAt: "2024-01-02T00:00:00Z",
          },
          {
            text: "Write tests",
            completed: false,
            createdAt: "2024-01-03T00:00:00Z",
          },
        ],
        completedCount: 1,
      },
    },
  },
  fields: [
    "id", 
    "title", 
    { content: [{ checklist: ["title", "items", "completedCount"] }] }
  ],
});

// Validate checklist content union type
if (todoWithChecklistContent?.content?.checklist) {
  const checklistData = todoWithChecklistContent.content.checklist;
  
  // Type casting checks - validate field selection worked
  const checklistTitle: string = checklistData.title;
  const items:
    | Array<{ text: string; completed?: boolean; createdAt?: string }>
    | null
    | undefined = checklistData.items;
  const completedCount: number | null | undefined = checklistData.completedCount;

  // Verify union field selection worked - should only have requested fields  
  const hasOnlyRequestedFields = Object.keys(checklistData).every(key => 
    ["title", "items", "completedCount"].includes(key)
  );

  if (items && items.length > 0) {
    const firstItem = items[0];
    const itemText: string = firstItem.text;
    const itemCompleted: boolean | undefined = firstItem.completed;
  }
}

// Test 16: Union type with primitive values - string note
const todoWithStringNote = await createTodo({
  input: {
    title: "Simple Note Todo",
    userId: "123e4567-e89b-12d3-a456-426614174000",
    content: {
      note: "Just a simple text note",
    },
  },
  fields: [
    "id", 
    "title", 
    { content: ["note"] }
  ],
});

// Validate string note union type
if (todoWithStringNote?.content) {
  // Type casting check - validate primitive union member selection
  if (todoWithStringNote.content.note !== undefined) {
    const noteContent: string = todoWithStringNote.content.note;
    
    // Verify union field selection worked - should only have note field
    const hasOnlyNoteField = Object.keys(todoWithStringNote.content).every(key => 
      ["note"].includes(key)
    );
  }
}

// Test 17: Union type with primitive values - integer priority
const todoWithPriorityValue = await createTodo({
  input: {
    title: "Priority Value Todo",
    userId: "123e4567-e89b-12d3-a456-426614174000",
    content: {
      priorityValue: 8,
    },
  },
  fields: [
    "id", 
    "title", 
    { content: ["priorityValue"] }
  ],
});

// Validate integer priority union type
if (todoWithPriorityValue?.content) {
  // Type casting check - validate primitive union member selection
  if (todoWithPriorityValue.content.priorityValue !== undefined) {
    const priorityValue: number = todoWithPriorityValue.content.priorityValue;
    
    // Verify union field selection worked - should only have priorityValue field
    const hasOnlyPriorityField = Object.keys(todoWithPriorityValue.content).every(key => 
      ["priorityValue"].includes(key)
    );
  }
}

// Test 18: Array union types - mixed attachments
const todoWithAttachments = await createTodo({
  input: {
    title: "Todo with Attachments",
    userId: "123e4567-e89b-12d3-a456-426614174000",
    attachments: [
      {
        filename: "document.pdf",
        size: 1024,
        mimeType: "application/pdf",
      },
      {
        filename: "screenshot.png",
        width: 1920,
        height: 1080,
        altText: "Project screenshot",
      },
      "https://example.com/reference",
    ],
  },
  fields: [
    "id", 
    "title", 
    { attachments: [{ file: ["filename", "size", "mimeType"] }, "url"] }
  ],
});

// Validate array union types
if (todoWithAttachments?.attachments) {
  const attachments = todoWithAttachments.attachments;

  for (const attachment of attachments as any[]) {
    // Type casting check - validate array union member selection
    if (attachment.file) {
      const fileData = attachment.file;
      
      // Validate field selection worked for complex union member
      const filename: string = fileData.filename;
      const size: number | null | undefined = fileData.size;
      const mimeType: string | null | undefined = fileData.mimeType;
      
      // Verify union field selection worked - should only have requested fields
      const hasOnlyRequestedFields = Object.keys(fileData).every(key => 
        ["filename", "size", "mimeType"].includes(key)
      );
    } else if (attachment.url !== undefined) {
      // Type casting check - validate primitive union member  
      const urlValue: string = attachment.url;
      
      // Verify union field selection worked - should only have url field
      const hasOnlyUrlField = Object.keys(attachment).every(key => 
        ["url"].includes(key)
      );
    }
  }
}

// Test 19: Complex union type scenario with field selection
const complexUnionScenario = await getTodo({
  fields: [
    "id",
    "title",
    { content: ["note", { text: ["text"] }, "priorityValue"] }, // Union type field
    { attachments: [{ file: ["filename"] }, "url"] }, // Array union type field
    {
      self: {
        calcArgs: { prefix: "union_test_" },
        fields: [
          "id",
          { content: [{ text: ["text", "wordCount"] }] }, // Union type in calculation
          { attachments: [{ file: ["filename", "size"] }] }, // Array union in calculation
          {
            self: {
              calcArgs: { prefix: "nested_union_" },
              fields: [
                "title",
                { content: [{ text: ["text"] }] }, // Nested union type
              ],
            },
          },
        ],
      },
    },
  ],
});

// Validate complex union type scenario
if (complexUnionScenario) {
  // Top level union types
  if (complexUnionScenario.content) {
    // Handle all possible union type members
    if (complexUnionScenario.content.text) {
      const textContent: string = complexUnionScenario.content.text.text;
    } else if (complexUnionScenario.content.checklist) {
      const checklistTitle: string =
        complexUnionScenario.content.checklist.title;
    } else if (complexUnionScenario.content.link) {
      const linkUrl: string = complexUnionScenario.content.link.url;
    } else if (complexUnionScenario.content.note) {
      const noteText: string = complexUnionScenario.content.note;
    } else if (complexUnionScenario.content.priorityValue) {
      const priority: number = complexUnionScenario.content.priorityValue;
    }
  }

  // Nested calculation union types
  if (complexUnionScenario.self?.content) {
    if (complexUnionScenario.self.content.text) {
      const nestedTextContent: string =
        complexUnionScenario.self.content.text.text;
      const nestedWordCount: number | null | undefined =
        complexUnionScenario.self.content.text.wordCount;
    }

    // Double nested calculation union types
    if (complexUnionScenario.self.self?.content) {
      if (complexUnionScenario.self.self.content.link) {
        const deepNestedUrl: string =
          complexUnionScenario.self.self.content.link.url;
        const deepNestedTitle: string | null | undefined =
          complexUnionScenario.self.self.content.link.title;
      }
    }
  }

  // Array union types in calculations
  if (complexUnionScenario.self?.attachments) {
    for (const attachment of complexUnionScenario.self.attachments as any[]) {
      if (attachment.file) {
        const calcFileSize: number | null | undefined = attachment.file.size;
      } else if (attachment.url) {
        const calcUrlValue: string = attachment.url;
      }
    }
  }
}

// Test 20: Union type with null/undefined handling
const todoWithNullContent = await getTodo({
  fields: [
    "id",
    "title",
    { content: [{ checklist: ["title"] }] }, // Might be null
    { attachments: [{ file: ["filename"] }] }, // Might be empty array or null
  ],
});

// Validate null handling for union types
if (todoWithNullContent) {
  const id: string = todoWithNullContent.id;
  const title: string = todoWithNullContent.title;

  // Content might be null - should handle gracefully
  const content: typeof todoWithNullContent.content =
    todoWithNullContent.content;
  if (content === null || content === undefined) {
    // This should be valid - union types are nullable
  } else {
    // Content exists, so we can check union members
    if (content.text) {
      const textData: string = content.text.text;
    }
  }

  // Attachments might be null or empty array
  const attachments: typeof todoWithNullContent.attachments =
    todoWithNullContent.attachments;
  if (attachments === null || attachments === undefined) {
    // This should be valid - array union types are nullable
  } else if (Array.isArray(attachments) && attachments.length === 0) {
    // Empty array should be valid
  } else {
    // Non-empty array - process union members
    for (const attachment of attachments as any[]) {
      if (attachment.file?.filename) {
        const filename: string = attachment.file.filename;
      }
    }
  }
}

// Test 21: Union type with create and update operations
const createUnionTypeConfig: CreateTodoConfig = {
  input: {
    title: "Union Type Create Test",
    userId: "123e4567-e89b-12d3-a456-426614174000",
    content: {
      link: {
        id: "link-content-1",
        url: "https://project-specs.example.com",
        title: "Project Specifications",
        description: "Detailed project requirements and specifications",
      },
    },
    attachments: [
      {
        url: "https://docs.example.com/api",
      },
      {
        file: {
          filename: "requirements.docx",
          size: 2048,
          mimeType:
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        },
      },
    ],
  },
  fields: [
    "id", 
    "title", 
    { content: [{ link: ["url", "title", "description"] }] },
    { attachments: [{ file: ["filename", "size", "mimeType"] }, "url"] },
    "createdAt"
  ],
};

const createdUnionTodo = await createTodo(createUnionTypeConfig);

// Validate created union type todo
if (createdUnionTodo) {
  const createdId: string = createdUnionTodo.id;
  const createdAt: string = createdUnionTodo.createdAt;

  if (createdUnionTodo.content?.link) {
    const linkUrl: string = createdUnionTodo.content.link.url;
    const linkTitle: string | null | undefined =
      createdUnionTodo.content.link.title;
    const linkDescription: string | null | undefined =
      createdUnionTodo.content.link.description;
  }

  if (createdUnionTodo.attachments) {
    for (const attachment of createdUnionTodo.attachments as any[]) {
      if (attachment.url) {
        const urlString: string = attachment.url;
      } else if (attachment.file) {
        const fileName: string = attachment.file.filename;
        const fileSize: number | null | undefined = attachment.file.size;
        const mimeType: string | null | undefined = attachment.file.mimeType;
      }
    }
  }
}

// Test 22: Union type with update operations
const updateUnionTypeConfig: UpdateTodoConfig = {
  primaryKey: createdUnionTodo.id,
  input: {
    title: "Updated Union Type Todo",
    content: {
      checklist: {
        id: "checklist-content-2",
        title: "Updated Checklist",
        items: [
          {
            text: "Review requirements",
            completed: true,
            createdAt: "2024-01-04T00:00:00Z",
          },
          {
            text: "Update documentation",
            completed: false,
            createdAt: "2024-01-05T00:00:00Z",
          },
        ],
        completedCount: 1,
      },
    },
  },
  fields: [
    "id", 
    "title", 
    { content: [{ checklist: ["title", "items", "completedCount"] }] }
  ],
};

const updatedUnionTodo = await updateTodo(updateUnionTypeConfig);

// Validate updated union type
if (updatedUnionTodo?.content?.checklist) {
  const updatedTitle: string = updatedUnionTodo.content.checklist.title;
  const updatedItems = updatedUnionTodo.content.checklist.items;
  const completedCount: number | null | undefined =
    updatedUnionTodo.content.checklist.completedCount;

  if (updatedItems) {
    for (const item of updatedItems) {
      const itemText: string = item.text;
      const itemCompleted: boolean = item.completed;
    }
  }
}

// Test 23: Validate union type field formatting (camelCase conversion)
const unionFormattingTest = await getTodo({
  fields: [
    "id",
    { content: [{ text: ["text"] }] }, // Should have camelCase field names in response
    { attachments: [{ file: ["filename"] }] }, // Array union should also have camelCase formatting
  ],
});

if (unionFormattingTest) {
  // Test that embedded resource fields are properly camelCased
  if (unionFormattingTest.content?.text) {
    const wordCount: number | null | undefined =
      unionFormattingTest.content.text.wordCount; // snake_case -> camelCase
    const displayText: string | null | undefined =
      unionFormattingTest.content.text.displayText; // calculation field
    const isFormatted: boolean | null | undefined =
      unionFormattingTest.content.text.isFormatted; // calculation field
  }

  if (unionFormattingTest.content?.checklist) {
    const completedCount: number | null | undefined =
      unionFormattingTest.content.checklist.completedCount; // snake_case -> camelCase
  }

  // Test that map union member fields are properly camelCased
  if (unionFormattingTest.attachments) {
    for (const attachment of unionFormattingTest.attachments as any[]) {
      if (attachment.file) {
        const mimeType: string | null | undefined = attachment.file.mimeType; // mime_type -> mimeType
      }
      if (attachment.image) {
        const altText: string | null | undefined = attachment.image.altText; // alt_text -> altText
      }
    }
  }
}

console.log("All union type tests should compile successfully!");
