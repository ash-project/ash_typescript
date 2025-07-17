// Embedded Resources Tests - shouldPass
// Tests for embedded resource field selection and input types

import {
  getTodo,
  createTodo,
  updateTodo,
  TodoMetadataInputSchema,
} from "../generated";

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

export const createWithEmbedded = await createTodo({
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
export const updateWithEmbedded = await updateTodo({
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
export const todoWithSelectedMetadata = await getTodo({
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
export const complexEmbeddedScenario = await getTodo({
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

export const createWithStrictInput = await createTodo({
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

console.log("Embedded resources tests should compile successfully!");