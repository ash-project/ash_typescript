// Union Types Tests - shouldPass
// Tests for union field selection and array unions

import {
  getTodo,
  createTodo,
  updateTodo,
  CreateTodoConfig,
  UpdateTodoConfig,
} from "../generated";

// Test: Union field selection with primitive members
export const todoWithPrimitiveUnion = await getTodo({
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
export const todoWithComplexUnion = await getTodo({
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
export const todoWithMixedUnion = await getTodo({
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

// Test 14: Union type with embedded resources - text content
export const todoWithTextContent = await createTodo({
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

export const todoWithFail = await createTodo({
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
export const todoWithChecklistContent = await createTodo({
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
export const todoWithStringNote = await createTodo({
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
export const todoWithPriorityValue = await createTodo({
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
export const todoWithAttachments = await createTodo({
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
export const complexUnionScenario = await getTodo({
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
export const todoWithNullContent = await getTodo({
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

export const createdUnionTodo = await createTodo(createUnionTypeConfig);

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

export const updatedUnionTodo = await updateTodo(updateUnionTypeConfig);

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
export const unionFormattingTest = await getTodo({
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

console.log("Union types tests should compile successfully!");