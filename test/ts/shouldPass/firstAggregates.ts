// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// First Aggregates Complex Types Tests - shouldPass

import { getTodo } from "../generated";

export const firstAggregateWithAttributeSelection = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: [
    "id",
    "title",
    {
      firstCommentMetadata: ["category", "priorityScore", "isUrgent"],
    },
  ],
});

if (firstAggregateWithAttributeSelection.success) {
  const todo = firstAggregateWithAttributeSelection.data;
  const id: string = todo.id;
  const title: string = todo.title;
  const metadata = todo.firstCommentMetadata;
  if (metadata) {
    const category: string = metadata.category;
    const priorityScore: number | null = metadata.priorityScore;
    const isUrgent: boolean | null = metadata.isUrgent;
  }
}

export const firstAggregateWithNestedTypedMap = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: [
    "id",
    {
      firstCommentMetadata: [
        "category",
        { settings: ["notifications", "autoArchive", "reminderFrequency"] },
      ],
    },
  ],
});

if (firstAggregateWithNestedTypedMap.success) {
  const todo = firstAggregateWithNestedTypedMap.data;
  const metadata = todo.firstCommentMetadata;
  if (metadata) {
    const category: string = metadata.category;
    const settings = metadata.settings;
    if (settings) {
      const notifications: boolean | null = settings.notifications;
      const autoArchive: boolean | null = settings.autoArchive;
    }
  }
}

export const firstAggregateAllAttributes = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: [
    "id",
    "title",
    {
      firstCommentMetadata: [
        "id",
        "category",
        "priorityScore",
        "deadline",
        "tags",
        "creatorId",
      ],
    },
  ],
});

if (firstAggregateAllAttributes.success) {
  const todo = firstAggregateAllAttributes.data;
  const metadata = todo.firstCommentMetadata;
  if (metadata) {
    const id: string = metadata.id;
    const category: string = metadata.category;
    const priorityScore: number | null = metadata.priorityScore;
    const deadline = metadata.deadline;
    const tags = metadata.tags;
    const creatorId = metadata.creatorId;
  }
}

export const firstAggregateWithDateTimeFields = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: [
    "id",
    {
      firstCommentMetadata: [
        "deadline",
        "createdAt",
        "reminderTime",
        "estimatedDuration",
        "estimatedHours",
        "budget",
      ],
    },
  ],
});

if (firstAggregateWithDateTimeFields.success) {
  const todo = firstAggregateWithDateTimeFields.data;
  const metadata = todo.firstCommentMetadata;
  if (metadata) {
    const deadline = metadata.deadline;
    const createdAt = metadata.createdAt;
    const reminderTime = metadata.reminderTime;
    const estimatedDuration = metadata.estimatedDuration;
    const estimatedHours: number | null = metadata.estimatedHours;
    const budget = metadata.budget;
  }
}

export const firstAggregateWithCollectionFields = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: [
    "id",
    {
      firstCommentMetadata: ["tags", "labels", "customFields"],
    },
  ],
});

if (firstAggregateWithCollectionFields.success) {
  const todo = firstAggregateWithCollectionFields.data;
  const metadata = todo.firstCommentMetadata;
  if (metadata) {
    const tags = metadata.tags;
    if (tags) {
      const firstTag: string = tags[0];
    }
    const labels = metadata.labels;
    const customFields = metadata.customFields;
  }
}

// ============================================================================
// STRESS TESTS: Complex Nested Structures in First Aggregates
// ============================================================================

export const firstAggregateWithDeeplyNestedTypedMap = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: [
    "id",
    {
      firstCommentMetadata: [
        "category",
        {
          advancedSettings: [
            "theme",
            { display: ["fontSize", "colorScheme", "compactMode"] },
            { sync: ["enabled", "intervalMinutes", "lastSync"] },
          ],
        },
      ],
    },
  ],
});

if (firstAggregateWithDeeplyNestedTypedMap.success) {
  const todo = firstAggregateWithDeeplyNestedTypedMap.data;
  const metadata = todo.firstCommentMetadata;
  if (metadata) {
    const category: string = metadata.category;
    const advancedSettings = metadata.advancedSettings;
    if (advancedSettings) {
      const theme: string = advancedSettings.theme;
      const display = advancedSettings.display;
      if (display) {
        const fontSize: number | null = display.fontSize;
        const colorScheme: string | null = display.colorScheme;
        const compactMode: boolean | null = display.compactMode;
      }
      const sync = advancedSettings.sync;
      if (sync) {
        const enabled: boolean | null = sync.enabled;
        const intervalMinutes: number | null = sync.intervalMinutes;
        const lastSync = sync.lastSync;
      }
    }
  }
}

export const firstAggregateWithUnionAttributePrimitive = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: [
    "id",
    {
      firstCommentMetadata: [
        "category",
        {
          priorityInfo: ["simple"],
        },
      ],
    },
  ],
});

if (firstAggregateWithUnionAttributePrimitive.success) {
  const todo = firstAggregateWithUnionAttributePrimitive.data;
  const metadata = todo.firstCommentMetadata;
  if (metadata) {
    const category: string = metadata.category;
    const priorityInfo = metadata.priorityInfo;
    if (priorityInfo && priorityInfo.simple) {
      const simpleValue: string = priorityInfo.simple;
    }
  }
}

// NOTE: When selecting multiple TypedMap/complex fields, combine them in ONE object
// to avoid TypeScript type inference issues with conflicting optional properties.
export const firstAggregateMultipleComplexFieldsSameObject = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: [
    "id",
    {
      firstCommentMetadata: [
        "priorityScore",
        "isUrgent",
        {
          settings: ["notifications", "autoArchive"],
          advancedSettings: ["theme", { display: ["fontSize"] }, { sync: ["enabled"] }],
          priorityInfo: ["simple"],
        },
      ],
    },
  ],
});

if (firstAggregateMultipleComplexFieldsSameObject.success) {
  const todo = firstAggregateMultipleComplexFieldsSameObject.data;
  const metadata = todo.firstCommentMetadata;
  if (metadata) {
    const priorityScore: number | null = metadata.priorityScore;
    const isUrgent: boolean | null = metadata.isUrgent;

    const settings = metadata.settings;
    if (settings) {
      const notifications: boolean | null = settings.notifications;
      const autoArchive: boolean | null = settings.autoArchive;
    }

    const advancedSettings = metadata.advancedSettings;
    if (advancedSettings) {
      const theme: string = advancedSettings.theme;
      if (advancedSettings.display) {
        const fontSize: number | null = advancedSettings.display.fontSize;
      }
      if (advancedSettings.sync) {
        const enabled: boolean | null = advancedSettings.sync.enabled;
      }
    }

    const priorityInfo = metadata.priorityInfo;
    if (priorityInfo && priorityInfo.simple) {
      const simple: string = priorityInfo.simple;
    }
  }
}

console.log("First aggregates tests should compile successfully!");
