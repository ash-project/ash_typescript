// SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
//
// SPDX-License-Identifier: MIT

// Typed Maps Tests - shouldPass
// Tests for typed map field selection and validation using current field syntax

import {
  getTodo,
  createTodo,
  updateTodo,
  buildCSRFHeaders,
} from "../generated";

// Test 1: Basic typed map field selection - settings map with all fields
export const todoWithFullSettings = await getTodo({
  input: {},
  fields: [
    "id",
    "title",
    {
      metadata: ["category", "settings"],
    },
  ],
});

// Validate full settings map through typed assignments
if (todoWithFullSettings.success && todoWithFullSettings.data) {
  const todoId: string = todoWithFullSettings.data.id;
  const todoTitle: string = todoWithFullSettings.data.title;

  if (todoWithFullSettings.data.metadata?.settings) {
    // Test all typed map fields
    const notifications: boolean | null =
      todoWithFullSettings.data.metadata.settings.notifications;
    const autoArchive: boolean | null =
      todoWithFullSettings.data.metadata.settings.autoArchive;
    const reminderFrequency: number | null =
      todoWithFullSettings.data.metadata.settings.reminderFrequency;

    // Validate TypedMap metadata
    const mapType: "TypedMap" =
      todoWithFullSettings.data.metadata.settings.__type;
    const primitiveFields:
      | "notifications"
      | "autoArchive"
      | "reminderFrequency" = "notifications"; // Example usage
  }
}

// Test 2: Typed map with field selection - selecting specific fields
export const todoWithPartialSettings = await getTodo({
  input: {},
  fields: [
    "id",
    "title",
    {
      metadata: ["category", "settings"],
    },
  ],
});

// Validate partial settings selection
if (todoWithPartialSettings.success && todoWithPartialSettings.data) {
  const todoId: string = todoWithPartialSettings.data.id;
  const todoTitle: string = todoWithPartialSettings.data.title;

  if (todoWithPartialSettings.data.metadata?.settings) {
    // Should have all typed map fields available
    const notifications: boolean | null =
      todoWithPartialSettings.data.metadata.settings.notifications;
    const autoArchive: boolean | null =
      todoWithPartialSettings.data.metadata.settings.autoArchive;
    const reminderFrequency: number | null =
      todoWithPartialSettings.data.metadata.settings.reminderFrequency;
  }
}

// Test 3: Multiple typed maps - settings and customFields
export const todoWithMultipleTypedMaps = await getTodo({
  input: {},
  fields: [
    "id",
    "title",
    {
      metadata: ["category", "settings", "customFields"],
    },
  ],
});

// Validate multiple typed maps
if (todoWithMultipleTypedMaps.success && todoWithMultipleTypedMaps.data) {
  const todoId: string = todoWithMultipleTypedMaps.data.id;
  const todoTitle: string = todoWithMultipleTypedMaps.data.title;

  if (todoWithMultipleTypedMaps.data.metadata) {
    // Test structured typed map (settings)
    if (todoWithMultipleTypedMaps.data.metadata.settings) {
      const notifications: boolean | null =
        todoWithMultipleTypedMaps.data.metadata.settings.notifications;
      const autoArchive: boolean | null =
        todoWithMultipleTypedMaps.data.metadata.settings.autoArchive;
      const reminderFrequency: number | null =
        todoWithMultipleTypedMaps.data.metadata.settings.reminderFrequency;
    }

    // Test generic typed map (customFields - Record<string, any>)
    if (todoWithMultipleTypedMaps.data.metadata.customFields) {
      const customFields: Record<string, any> =
        todoWithMultipleTypedMaps.data.metadata.customFields;
    }
  }
}

// Test 4: Create todo with typed map input
export const createTodoWithTypedMap = await createTodo({
  input: {
    title: "Todo with Typed Map Settings",
    userId: "123e4567-e89b-12d3-a456-426614174000",
    metadata: {
      category: "Work",
      priorityScore: 85,
      settings: {
        notifications: true,
        autoArchive: false,
        reminderFrequency: 24,
      },
      customFields: {
        project: "ash-typescript",
        complexity: "high",
        estimatedDays: 5,
      },
    },
  },
  fields: [
    "id",
    "title",
    {
      metadata: ["category", "priorityScore", "settings", "customFields"],
    },
  ],
  headers: buildCSRFHeaders(),
});

// Validate created todo with typed maps
if (createTodoWithTypedMap.success && createTodoWithTypedMap.data) {
  const createdId: string = createTodoWithTypedMap.data.id;
  const createdTitle: string = createTodoWithTypedMap.data.title;

  if (createTodoWithTypedMap.data.metadata) {
    const category: string = createTodoWithTypedMap.data.metadata.category;
    const priorityScore: number | null =
      createTodoWithTypedMap.data.metadata.priorityScore;

    // Validate settings typed map input worked
    if (createTodoWithTypedMap.data.metadata.settings) {
      const notifications: boolean | null =
        createTodoWithTypedMap.data.metadata.settings.notifications;
      const autoArchive: boolean | null =
        createTodoWithTypedMap.data.metadata.settings.autoArchive;
      const reminderFrequency: number | null =
        createTodoWithTypedMap.data.metadata.settings.reminderFrequency;
    }

    // Validate customFields generic map input worked
    if (createTodoWithTypedMap.data.metadata.customFields) {
      const customFields: Record<string, any> =
        createTodoWithTypedMap.data.metadata.customFields;
    }
  }
}

// Test 5: Update todo with typed map changes
export const updateTodoWithTypedMap = await updateTodo({
  primaryKey: "123e4567-e89b-12d3-a456-426614174000",
  input: {
    title: "Updated Todo with Modified Settings",
    metadata: {
      category: "Personal",
      settings: {
        notifications: false,
        autoArchive: true,
        reminderFrequency: 48,
      },
      customFields: {
        project: "personal-tasks",
        priority: "medium",
      },
    },
  },
  fields: [
    "id",
    "title",
    {
      metadata: ["category", "settings", "customFields"],
    },
  ],
});

// Validate updated typed maps
if (updateTodoWithTypedMap.success && updateTodoWithTypedMap.data) {
  const updatedId: string = updateTodoWithTypedMap.data.id;
  const updatedTitle: string = updateTodoWithTypedMap.data.title;

  if (updateTodoWithTypedMap.data.metadata) {
    const updatedCategory: string =
      updateTodoWithTypedMap.data.metadata.category;

    // Validate updated settings
    if (updateTodoWithTypedMap.data.metadata.settings) {
      const notifications: boolean | null =
        updateTodoWithTypedMap.data.metadata.settings.notifications;
      const autoArchive: boolean | null =
        updateTodoWithTypedMap.data.metadata.settings.autoArchive;
      const reminderFrequency: number | null =
        updateTodoWithTypedMap.data.metadata.settings.reminderFrequency;
    }

    // Validate updated customFields
    if (updateTodoWithTypedMap.data.metadata.customFields) {
      const customFields: Record<string, any> =
        updateTodoWithTypedMap.data.metadata.customFields;
    }
  }
}

// Test 6: Typed map with calculations
export const todoWithTypedMapCalculation = await getTodo({
  input: {},
  fields: [
    "id",
    "title",
    {
      metadata: ["category", "settings"],
    },
    {
      self: {
        args: { prefix: "settings_test_" },
        fields: [
          "id",
          {
            metadata: ["category", "settings", "customFields"],
          },
        ],
      },
    },
  ],
});

// Validate typed maps with calculations
if (todoWithTypedMapCalculation.success && todoWithTypedMapCalculation.data) {
  const todoId: string = todoWithTypedMapCalculation.data.id;
  const todoTitle: string = todoWithTypedMapCalculation.data.title;

  // Top-level metadata with typed maps
  if (todoWithTypedMapCalculation.data.metadata?.settings) {
    const notifications: boolean | null =
      todoWithTypedMapCalculation.data.metadata.settings.notifications;
    const autoArchive: boolean | null =
      todoWithTypedMapCalculation.data.metadata.settings.autoArchive;
    const reminderFrequency: number | null =
      todoWithTypedMapCalculation.data.metadata.settings.reminderFrequency;
  }

  // Calculation-level metadata with typed maps
  if (todoWithTypedMapCalculation.data.self?.metadata) {
    const calcCategory: string =
      todoWithTypedMapCalculation.data.self.metadata.category;

    if (todoWithTypedMapCalculation.data.self.metadata.settings) {
      const calcNotifications: boolean | null =
        todoWithTypedMapCalculation.data.self.metadata.settings.notifications;
      const calcAutoArchive: boolean | null =
        todoWithTypedMapCalculation.data.self.metadata.settings.autoArchive;
      const calcReminderFreq: number | null =
        todoWithTypedMapCalculation.data.self.metadata.settings
          .reminderFrequency;
    }

    if (todoWithTypedMapCalculation.data.self.metadata.customFields) {
      const calcCustomFields: Record<string, any> =
        todoWithTypedMapCalculation.data.self.metadata.customFields;
    }
  }
}

// Test 7: Null/undefined handling for typed maps
export const todoWithNullableTypedMaps = await getTodo({
  input: {},
  fields: [
    "id",
    "title",
    {
      metadata: ["category", "settings", "customFields"],
    },
  ],
});

// Validate null handling for typed maps
if (todoWithNullableTypedMaps.success && todoWithNullableTypedMaps.data) {
  const todoId: string = todoWithNullableTypedMaps.data.id;
  const todoTitle: string = todoWithNullableTypedMaps.data.title;

  if (todoWithNullableTypedMaps.data.metadata) {
    const category: string = todoWithNullableTypedMaps.data.metadata.category;

    // Settings might be null - should handle gracefully
    if (todoWithNullableTypedMaps.data.metadata.settings === null) {
      // This should be valid - typed maps can be nullable
    } else if (todoWithNullableTypedMaps.data.metadata.settings) {
      // Settings exists, so we can access its fields
      const notifications: boolean | null =
        todoWithNullableTypedMaps.data.metadata.settings.notifications;
      const autoArchive: boolean | null =
        todoWithNullableTypedMaps.data.metadata.settings.autoArchive;
      const reminderFrequency: number | null =
        todoWithNullableTypedMaps.data.metadata.settings.reminderFrequency;
    }

    // CustomFields might be null - should handle gracefully
    if (todoWithNullableTypedMaps.data.metadata.customFields === null) {
      // This should be valid - generic maps can be nullable
    } else if (todoWithNullableTypedMaps.data.metadata.customFields) {
      // CustomFields exists, so we can access it
      const customFields: Record<string, any> =
        todoWithNullableTypedMaps.data.metadata.customFields;
    }
  }
}

// Test 8: Minimal typed map input - only required fields
const minimalSettings = {
  notifications: true,
  autoArchive: null,
  reminderFrequency: null,
} as const;

export const createTodoWithMinimalTypedMap = await createTodo({
  input: {
    title: "Todo with Minimal Typed Map",
    userId: "123e4567-e89b-12d3-a456-426614174000",
    metadata: {
      category: "Test", // Only required field
      settings: minimalSettings,
    },
  },
  fields: [
    "id",
    "title",
    {
      metadata: ["category", "settings"],
    },
  ],
});

// Validate minimal typed map input
if (
  createTodoWithMinimalTypedMap.success &&
  createTodoWithMinimalTypedMap.data
) {
  const createdId: string = createTodoWithMinimalTypedMap.data.id;
  const createdTitle: string = createTodoWithMinimalTypedMap.data.title;

  if (createTodoWithMinimalTypedMap.data.metadata) {
    const category: string =
      createTodoWithMinimalTypedMap.data.metadata.category;

    if (createTodoWithMinimalTypedMap.data.metadata.settings) {
      const notifications: boolean | null =
        createTodoWithMinimalTypedMap.data.metadata.settings.notifications;
      // These should be null/undefined since they weren't provided
      const autoArchive: boolean | null =
        createTodoWithMinimalTypedMap.data.metadata.settings.autoArchive;
      const reminderFrequency: number | null =
        createTodoWithMinimalTypedMap.data.metadata.settings.reminderFrequency;
    }
  }
}

// Test 9: Typed map field formatting (camelCase conversion)
export const typedMapFormattingTest = await getTodo({
  input: {},
  fields: [
    "id",
    "title",
    {
      metadata: ["settings"],
    },
  ],
});

// Validate that typed map fields are properly camelCased
if (typedMapFormattingTest.success && typedMapFormattingTest.data) {
  const todoId: string = typedMapFormattingTest.data.id;
  const todoTitle: string = typedMapFormattingTest.data.title;

  if (typedMapFormattingTest.data.metadata?.settings) {
    // Test that snake_case fields are converted to camelCase
    const autoArchive: boolean | null =
      typedMapFormattingTest.data.metadata.settings.autoArchive; // auto_archive -> autoArchive
    const reminderFrequency: number | null =
      typedMapFormattingTest.data.metadata.settings.reminderFrequency; // reminder_frequency -> reminderFrequency
    const notifications: boolean | null =
      typedMapFormattingTest.data.metadata.settings.notifications; // already camelCase

    // Validate TypedMap metadata includes properly formatted primitive fields
    const primitiveFields:
      | "notifications"
      | "autoArchive"
      | "reminderFrequency" = "autoArchive"; // Example usage
  }
}

// Test 10: Complex nested scenario with typed maps
export const complexTypedMapScenario = await getTodo({
  input: {},
  fields: [
    "id",
    "title",
    {
      metadata: ["category", "settings", "customFields"],
      metadataHistory: ["category", "settings"],
    },
    {
      self: {
        args: { prefix: "nested_" },
        fields: [
          "id",
          {
            metadata: ["settings"],
            metadataHistory: ["settings", "customFields"],
          },
        ],
      },
    },
  ],
});

// Validate complex nested typed map scenario
if (complexTypedMapScenario.success && complexTypedMapScenario.data) {
  const todoId: string = complexTypedMapScenario.data.id;
  const todoTitle: string = complexTypedMapScenario.data.title;

  // Top-level metadata
  if (complexTypedMapScenario.data.metadata?.settings) {
    const topNotifications: boolean | null =
      complexTypedMapScenario.data.metadata.settings.notifications;
    const topAutoArchive: boolean | null =
      complexTypedMapScenario.data.metadata.settings.autoArchive;
    const topReminderFreq: number | null =
      complexTypedMapScenario.data.metadata.settings.reminderFrequency;
  }

  // Array embedded resources (metadataHistory) with typed maps
  if (
    complexTypedMapScenario.data.metadataHistory &&
    complexTypedMapScenario.data.metadataHistory.length > 0
  ) {
    const firstHistory = complexTypedMapScenario.data.metadataHistory[0];
    const historyCategory: string = firstHistory.category;

    if (firstHistory.settings) {
      const historyNotifications: boolean | null =
        firstHistory.settings.notifications;
      const historyAutoArchive: boolean | null =
        firstHistory.settings.autoArchive;
      const historyReminderFreq: number | null =
        firstHistory.settings.reminderFrequency;
    }
  }

  // Nested calculations with typed maps
  if (complexTypedMapScenario.data.self?.metadata?.settings) {
    const nestedNotifications: boolean | null =
      complexTypedMapScenario.data.self.metadata.settings.notifications;
    const nestedAutoArchive: boolean | null =
      complexTypedMapScenario.data.self.metadata.settings.autoArchive;
    const nestedReminderFreq: number | null =
      complexTypedMapScenario.data.self.metadata.settings.reminderFrequency;
  }

  // Nested calculation metadataHistory with typed maps
  if (
    complexTypedMapScenario.data.self?.metadataHistory &&
    complexTypedMapScenario.data.self.metadataHistory.length > 0
  ) {
    const nestedFirstHistory =
      complexTypedMapScenario.data.self.metadataHistory[0];

    if (nestedFirstHistory.settings) {
      const nestedHistoryNotifications: boolean | null =
        nestedFirstHistory.settings.notifications;
      const nestedHistoryAutoArchive: boolean | null =
        nestedFirstHistory.settings.autoArchive;
      const nestedHistoryReminderFreq: number | null =
        nestedFirstHistory.settings.reminderFrequency;
    }

    if (nestedFirstHistory.customFields) {
      const nestedHistoryCustomFields: Record<string, any> =
        nestedFirstHistory.customFields;
    }
  }
}

console.log("Typed maps tests should compile successfully!");
