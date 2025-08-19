// Union Types Tests - shouldPass
// Tests for union field selection and validation using current field syntax

import {
  getTodo,
  createTodo,
  updateTodo,
  CreateTodoConfig,
  UpdateTodoConfig,
} from "../generated";

// Test 1: Basic union field selection - primitive members only
export const todoWithPrimitiveUnion = await getTodo({
  fields: [
    "id",
    "title",
    {
      content: ["note", "priorityValue"],
    },
  ],
});

// Validate primitive union selection through typed assignments
if (todoWithPrimitiveUnion.success && todoWithPrimitiveUnion.data) {
  const todoId: string = todoWithPrimitiveUnion.data.id;
  const todoTitle: string = todoWithPrimitiveUnion.data.title;

  if (todoWithPrimitiveUnion.data.content) {
    // Test note field (string primitive)
    if ("note" in todoWithPrimitiveUnion.data.content && todoWithPrimitiveUnion.data.content.note) {
      const noteValue: string = todoWithPrimitiveUnion.data.content.note;
    }

    // Test priorityValue field (number primitive)
    if ("priorityValue" in todoWithPrimitiveUnion.data.content && todoWithPrimitiveUnion.data.content.priorityValue) {
      const priorityValue: number = todoWithPrimitiveUnion.data.content.priorityValue;
    }
  }
}

// Test 2: Complex union member field selection
export const todoWithComplexUnion = await getTodo({
  fields: [
    "id",
    "title",
    {
      content: [
        {
          text: ["id", "text", "wordCount", "formatting"],
        },
      ],
    },
  ],
});

// Validate complex union selection through typed assignments
if (todoWithComplexUnion.success && todoWithComplexUnion.data) {
  const todoId: string = todoWithComplexUnion.data.id;
  const todoTitle: string = todoWithComplexUnion.data.title;

  if (todoWithComplexUnion.data.content) {
    // Test text content (complex embedded resource)
    if ("text" in todoWithComplexUnion.data.content && todoWithComplexUnion.data.content.text) {
      const textId: string = todoWithComplexUnion.data.content.text.id;
      const textContent: string = todoWithComplexUnion.data.content.text.text;
      const wordCount: number | null | undefined = todoWithComplexUnion.data.content.text.wordCount;
      const formatting: string | null | undefined = todoWithComplexUnion.data.content.text.formatting;
    }
  }
}

// Test 3: Mixed union field selection (primitive + complex)
export const todoWithMixedUnion = await getTodo({
  fields: [
    "id",
    "title",
    {
      content: [
        "note",
        {
          text: ["text", "wordCount"],
        },
        "priorityValue",
      ],
    },
  ],
});

// Validate mixed union selection through typed assignments
if (todoWithMixedUnion.success && todoWithMixedUnion.data) {
  const todoId: string = todoWithMixedUnion.data.id;
  const todoTitle: string = todoWithMixedUnion.data.title;

  if (todoWithMixedUnion.data.content) {
    // Test primitive note field
    if ("note" in todoWithMixedUnion.data.content && todoWithMixedUnion.data.content.note) {
      const noteValue: string = todoWithMixedUnion.data.content.note;
    }

    // Test complex text field with selected fields only
    if ("text" in todoWithMixedUnion.data.content && todoWithMixedUnion.data.content.text) {
      const textContent: string = todoWithMixedUnion.data.content.text.text;
      const wordCount: number | null | undefined = todoWithMixedUnion.data.content.text.wordCount;
      // formatting field should NOT be available since it wasn't selected
    }

    // Test primitive priorityValue field
    if ("priorityValue" in todoWithMixedUnion.data.content && todoWithMixedUnion.data.content.priorityValue) {
      const priorityValue: number = todoWithMixedUnion.data.content.priorityValue;
    }
  }
}

// Test 4: Create todo with text content union type
export const createTodoWithTextContent = await createTodo({
  input: {
    title: "Text Content Todo",
    userId: "123e4567-e89b-12d3-a456-426614174000",
    content: {
      text: {
        id: "text-content-1",
        text: "This is formatted text content",
        wordCount: 5,
        formatting: "markdown",
      },
    },
  },
  fields: [
    "id",
    "title",
    {
      content: [
        {
          text: ["id", "text", "wordCount"],
        },
      ],
    },
  ],
});

// Validate created todo with text content
if (createTodoWithTextContent.success && createTodoWithTextContent.data) {
  const createdId: string = createTodoWithTextContent.data.id;
  const createdTitle: string = createTodoWithTextContent.data.title;

  if (createTodoWithTextContent.data.content) {
    if ("text" in createTodoWithTextContent.data.content && createTodoWithTextContent.data.content.text) {
      const textId: string = createTodoWithTextContent.data.content.text.id;
      const textContent: string = createTodoWithTextContent.data.content.text.text;
      const wordCount: number | null | undefined = createTodoWithTextContent.data.content.text.wordCount;
      // formatting should NOT be available since it wasn't selected
    }
  }
}

// Test 5: Create todo with checklist content union type
export const createTodoWithChecklistContent = await createTodo({
  input: {
    title: "Checklist Todo",
    userId: "123e4567-e89b-12d3-a456-426614174000",
    content: {
      checklist: {
        id: "checklist-1",
        title: "Development Tasks",
        items: [
          {
            text: "Design API",
            completed: true,
            createdAt: "2024-01-01T00:00:00Z",
          },
          {
            text: "Implement features",
            completed: false,
            createdAt: "2024-01-02T00:00:00Z",
          },
        ],
        completedCount: 1,
      },
    },
  },
  fields: [
    "id",
    "title",
    {
      content: [
        {
          checklist: ["title", "items", "completedCount"],
        },
      ],
    },
  ],
});

// Validate created todo with checklist content
if (createTodoWithChecklistContent.success && createTodoWithChecklistContent.data) {
  const createdId: string = createTodoWithChecklistContent.data.id;
  const createdTitle: string = createTodoWithChecklistContent.data.title;

  if (createTodoWithChecklistContent.data.content) {
    if ("checklist" in createTodoWithChecklistContent.data.content && createTodoWithChecklistContent.data.content.checklist) {
      const checklistTitle: string = createTodoWithChecklistContent.data.content.checklist.title;
      const items = createTodoWithChecklistContent.data.content.checklist.items;
      const completedCount: number | null | undefined = createTodoWithChecklistContent.data.content.checklist.completedCount;

      if (items && items.length > 0) {
        const firstItem = items[0];
        const itemText: string = firstItem.text;
        const itemCompleted: boolean | null | undefined = firstItem.completed;
        const itemCreatedAt: string | null | undefined = firstItem.createdAt;
      }
    }
  }
}

// Test 6: Create todo with primitive union content
export const createTodoWithPrimitiveContent = await createTodo({
  input: {
    title: "Simple Note Todo",
    userId: "123e4567-e89b-12d3-a456-426614174000",
    content: {
      note: "This is a simple text note",
    },
  },
  fields: [
    "id",
    "title",
    {
      content: ["note"],
    },
  ],
});

// Validate created todo with primitive content
if (createTodoWithPrimitiveContent.success && createTodoWithPrimitiveContent.data) {
  const createdId: string = createTodoWithPrimitiveContent.data.id;
  const createdTitle: string = createTodoWithPrimitiveContent.data.title;

  if (createTodoWithPrimitiveContent.data.content) {
    if ("note" in createTodoWithPrimitiveContent.data.content && createTodoWithPrimitiveContent.data.content.note) {
      const noteContent: string = createTodoWithPrimitiveContent.data.content.note;
    }
  }
}

// Test 7: Array union types with attachments
export const todoWithAttachments = await getTodo({
  fields: [
    "id",
    "title",
    {
      attachments: [
        {
          file: ["filename", "size", "mimeType"],
        },
        "url",
      ],
    },
  ],
});

// Validate array union types through typed assignments
if (todoWithAttachments.success && todoWithAttachments.data) {
  const todoId: string = todoWithAttachments.data.id;
  const todoTitle: string = todoWithAttachments.data.title;

  if (todoWithAttachments.data.attachments && Array.isArray(todoWithAttachments.data.attachments)) {
    const attachments = todoWithAttachments.data.attachments;
    
    for (const attachment of attachments) {
      // Test file attachment (complex union member)
      if (attachment && typeof attachment === 'object' && "file" in attachment && attachment.file) {
        const filename: string = attachment.file.filename;
        const size: number | null | undefined = attachment.file.size;
        const mimeType: string | null | undefined = attachment.file.mimeType;
      }
      
      // Test URL attachment (primitive union member)
      if (attachment && typeof attachment === 'object' && "url" in attachment && attachment.url) {
        const urlValue: string = attachment.url;
      }
    }
  }
}

// Test 8: Union types with calculations
export const todoWithUnionCalculation = await getTodo({
  fields: [
    "id",
    "title",
    {
      content: [
        {
          text: ["text", "wordCount"],
        },
        "note",
      ],
    },
    {
      self: {
        args: { prefix: "calc_" },
        fields: [
          "id",
          {
            content: [
              {
                text: ["text"],
              },
              "priorityValue",
            ],
          },
        ],
      },
    },
  ],
});

// Validate union types with calculations
if (todoWithUnionCalculation.success && todoWithUnionCalculation.data) {
  const todoId: string = todoWithUnionCalculation.data.id;
  const todoTitle: string = todoWithUnionCalculation.data.title;

  // Top-level union content
  if (todoWithUnionCalculation.data.content) {
    if ("text" in todoWithUnionCalculation.data.content && todoWithUnionCalculation.data.content.text) {
      const textContent: string = todoWithUnionCalculation.data.content.text.text;
      const wordCount: number | null | undefined = todoWithUnionCalculation.data.content.text.wordCount;
    }
    
    if ("note" in todoWithUnionCalculation.data.content && todoWithUnionCalculation.data.content.note) {
      const noteContent: string = todoWithUnionCalculation.data.content.note;
    }
  }

  // Calculation-level union content
  if (todoWithUnionCalculation.data.self?.content) {
    if ("text" in todoWithUnionCalculation.data.self.content && todoWithUnionCalculation.data.self.content.text) {
      const calcTextContent: string = todoWithUnionCalculation.data.self.content.text.text;
    }
    
    if ("priorityValue" in todoWithUnionCalculation.data.self.content && todoWithUnionCalculation.data.self.content.priorityValue) {
      const calcPriorityValue: number = todoWithUnionCalculation.data.self.content.priorityValue;
    }
  }
}

// Test 9: Update todo with union content
export const updatedUnionTodo = await updateTodo({
  primaryKey: "123e4567-e89b-12d3-a456-426614174000",
  input: {
    title: "Updated Union Todo",
    content: {
      priorityValue: 9,
    },
  },
  fields: [
    "id",
    "title",
    {
      content: ["priorityValue", "note"],
    },
  ],
});

// Validate updated union todo
if (updatedUnionTodo.success && updatedUnionTodo.data) {
  const updatedId: string = updatedUnionTodo.data.id;
  const updatedTitle: string = updatedUnionTodo.data.title;

  if (updatedUnionTodo.data.content) {
    if ("priorityValue" in updatedUnionTodo.data.content && updatedUnionTodo.data.content.priorityValue !== undefined) {
      const priorityValue: number = updatedUnionTodo.data.content.priorityValue;
    }
    
    if ("note" in updatedUnionTodo.data.content && updatedUnionTodo.data.content.note !== undefined) {
      const noteContent: string = updatedUnionTodo.data.content.note;
    }
  }
}

// Test 10: Null/undefined handling for union types
export const todoWithNullableUnion = await getTodo({
  fields: [
    "id",
    "title",
    {
      content: [
        {
          text: ["text"],
        },
      ],
    },
    {
      attachments: [
        {
          file: ["filename"],
        },
      ],
    },
  ],
});

// Validate null handling for union types
if (todoWithNullableUnion.success && todoWithNullableUnion.data) {
  const todoId: string = todoWithNullableUnion.data.id;
  const todoTitle: string = todoWithNullableUnion.data.title;

  // Content might be null - should handle gracefully
  if (todoWithNullableUnion.data.content === null || todoWithNullableUnion.data.content === undefined) {
    // This should be valid - union types are nullable
  } else {
    if ("text" in todoWithNullableUnion.data.content && todoWithNullableUnion.data.content.text) {
      const textContent: string = todoWithNullableUnion.data.content.text.text;
    }
  }

  // Attachments might be null or empty array
  if (todoWithNullableUnion.data.attachments === null || todoWithNullableUnion.data.attachments === undefined) {
    // This should be valid - array union types are nullable
  } else if (Array.isArray(todoWithNullableUnion.data.attachments) && todoWithNullableUnion.data.attachments.length === 0) {
    // Empty array should be valid
  } else if (Array.isArray(todoWithNullableUnion.data.attachments)) {
    for (const attachment of todoWithNullableUnion.data.attachments) {
      if (attachment && typeof attachment === 'object' && "file" in attachment && attachment.file) {
        const filename: string = attachment.file.filename;
      }
    }
  }
}

console.log("Union types tests should compile successfully!");