// SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
//
// SPDX-License-Identifier: MIT

// Metadata Tests - shouldPass
// Tests for metadata field selection and type inference with actions that have metadata

import {
  readTasksWithMetadata,
  readTasksWithMappedMetadata,
  createTask,
  updateTask,
  markCompletedTask,
  destroyTask,
} from "../generated";

// Test 1: Read action with metadata - selecting all metadata fields
export const readWithAllMetadata = await readTasksWithMetadata({
  fields: ["id", "title"],
  metadataFields: ["someString", "someNumber", "someBoolean"],
});

// Type validation for read with all metadata fields
if (readWithAllMetadata.success) {
  for (const task of readWithAllMetadata.data) {
    // Resource fields
    const taskId: string = task.id;
    const taskTitle: string = task.title;

    // Metadata fields - should be present and properly typed
    const metaString: string = task.someString;
    const metaNumber: number = task.someNumber;
    const metaBoolean: boolean | null | undefined = task.someBoolean;
  }
}

// Test 2: Read action with metadata - selecting only specific metadata fields
export const readWithSelectiveMetadata = await readTasksWithMetadata({
  fields: ["id", "title", "completed"],
  metadataFields: ["someString"],
});

// Type validation for selective metadata
if (readWithSelectiveMetadata.success) {
  for (const task of readWithSelectiveMetadata.data) {
    const taskId: string = task.id;
    const taskTitle: string = task.title;
    const taskCompleted: boolean = task.completed;

    // Only someString should be present
    const metaString: string = task.someString;

    // These should NOT be accessible (TypeScript should error if uncommented):
    // const metaNumber: number = task.someNumber; // ❌ Should not exist
    // const metaBoolean: boolean = task.someBoolean; // ❌ Should not exist
  }
}

// Test 3: Read action with metadata - selecting multiple metadata fields
export const readWithPartialMetadata = await readTasksWithMetadata({
  fields: ["id", "title"],
  metadataFields: ["someString", "someNumber"],
});

// Type validation for partial metadata
if (readWithPartialMetadata.success) {
  for (const task of readWithPartialMetadata.data) {
    const taskId: string = task.id;
    const taskTitle: string = task.title;

    // These two metadata fields should be present
    const metaString: string = task.someString;
    const metaNumber: number = task.someNumber;

    // This should NOT be accessible:
    // const metaBoolean: boolean = task.someBoolean; // ❌ Should not exist
  }
}

// Test 4: Read action with metadata - no metadata fields selected (default)
export const readWithNoMetadata = await readTasksWithMetadata({
  fields: ["id", "title", "completed"],
});

// Type validation - no metadata fields should be present
if (readWithNoMetadata.success) {
  for (const task of readWithNoMetadata.data) {
    const taskId: string = task.id;
    const taskTitle: string = task.title;
    const taskCompleted: boolean = task.completed;

    // Metadata fields should NOT be accessible:
    // const metaString: string = task.someString; // ❌ Should not exist
    // const metaNumber: number = task.someNumber; // ❌ Should not exist
    // const metaBoolean: boolean = task.someBoolean; // ❌ Should not exist
  }
}

// Test 5: Create action with metadata - must explicitly request metadata fields
export const createWithMetadata = await createTask({
  input: {
    title: "Task with metadata",
  },
  fields: ["id", "title", "completed"],
  metadataFields: ["someString", "someNumber", "someBoolean"],
});

// Type validation for create with metadata
if (createWithMetadata.success) {
  // Resource fields
  const taskId: string = createWithMetadata.data.id;
  const taskTitle: string = createWithMetadata.data.title;
  const taskCompleted: boolean = createWithMetadata.data.completed;

  // Metadata is returned as separate field for mutations
  const metaString: string = createWithMetadata.metadata.someString;
  const metaNumber: number = createWithMetadata.metadata.someNumber;
  const metaBoolean: boolean | null | undefined =
    createWithMetadata.metadata.someBoolean;
}

// Test 6: Update action with metadata - must explicitly request metadata fields
export const updateWithMetadata = await updateTask({
  primaryKey: "some-task-id",
  input: {
    title: "Updated task",
  },
  fields: ["id", "title", "completed"],
  metadataFields: ["someString", "someNumber", "someBoolean"],
});

// Type validation for update with metadata
if (updateWithMetadata.success) {
  const taskId: string = updateWithMetadata.data.id;
  const taskTitle: string = updateWithMetadata.data.title;

  // Metadata returned separately
  const metaString: string = updateWithMetadata.metadata.someString;
  const metaNumber: number = updateWithMetadata.metadata.someNumber;
  const metaBoolean: boolean | null | undefined =
    updateWithMetadata.metadata.someBoolean;
}

// Test 7: Update action with arguments and metadata
export const markCompletedWithMetadata = await markCompletedTask({
  primaryKey: "some-task-id",
  input: {
    isCompleted: true, // Note: mapped from completed? to isCompleted
  },
  fields: ["id", "title", "completed"],
  metadataFields: ["someString", "someNumber"],
});

// Type validation for mark completed with metadata
if (markCompletedWithMetadata.success) {
  const taskId: string = markCompletedWithMetadata.data.id;
  const taskTitle: string = markCompletedWithMetadata.data.title;
  const taskCompleted: boolean = markCompletedWithMetadata.data.completed;

  // Metadata returned separately - only requested fields
  const metaString: string = markCompletedWithMetadata.metadata.someString;
  const metaNumber: number = markCompletedWithMetadata.metadata.someNumber;

  // This should NOT be accessible (only someString and someNumber were requested):
  // const metaBoolean: boolean = markCompletedWithMetadata.metadata.someBoolean; // ❌ Should not exist
}

// Test 8: Destroy action with metadata - must explicitly request metadata fields
export const destroyWithMetadata = await destroyTask({
  primaryKey: "some-task-id",
  metadataFields: ["someString"],
});

// Type validation for destroy with metadata
if (destroyWithMetadata.success) {
  // Destroy returns empty data object
  const emptyData: {} = destroyWithMetadata.data;

  // Only requested metadata field is returned
  const metaString: string = destroyWithMetadata.metadata.someString;

  // These should NOT be accessible (only someString was requested):
  // const metaNumber: number = destroyWithMetadata.metadata.someNumber; // ❌ Should not exist
  // const metaBoolean: boolean = destroyWithMetadata.metadata.someBoolean; // ❌ Should not exist
}

// Test 9: Read with metadata and embedded resource attribute
export const readMetadataWithEmbedded = await readTasksWithMetadata({
  fields: ["id", "title"],
  metadataFields: ["someString", "someNumber"],
});

// Type validation for action metadata with embedded resource attribute
if (readMetadataWithEmbedded.success) {
  for (const task of readMetadataWithEmbedded.data) {
    const taskId: string = task.id;
    const taskTitle: string = task.title;

    // Action metadata (from metadataFields parameter)
    const actionMetaString: string = task.someString;
    const actionMetaNumber: number = task.someNumber;
  }
}

// Test 10: Verify TypeScript inference with const assertion
export const readMetadataConst = await readTasksWithMetadata({
  fields: ["id", "title"] as const,
  metadataFields: ["someString", "someNumber"] as const,
});

// Type validation with const assertion
if (readMetadataConst.success) {
  // TypeScript should infer exact field types
  for (const task of readMetadataConst.data) {
    const id: string = task.id;
    const title: string = task.title;
    const someString: string = task.someString;
    const someNumber: number = task.someNumber;
  }
}

// Test 11: Read action with mapped metadata field names - all fields
export const readWithMappedMetadataAll = await readTasksWithMappedMetadata({
  fields: ["id", "title"],
  metadataFields: ["meta1", "isValid", "field2"],
});

// Type validation for mapped metadata fields
if (readWithMappedMetadataAll.success) {
  for (const task of readWithMappedMetadataAll.data) {
    const taskId: string = task.id;
    const taskTitle: string = task.title;

    // Mapped metadata field names should be available
    const meta1: string = task.meta1;
    const isValid: boolean = task.isValid;
    const field2: number = task.field2;

    // Original invalid names should NOT be accessible:
    // const meta_1: string = task.meta_1; // ❌ Should not exist
    // const is_valid: boolean = task.is_valid?; // ❌ Should not exist (invalid TS)
    // const field_2: number = task.field_2; // ❌ Should not exist
  }
}

// Test 12: Read action with mapped metadata - selective fields
export const readWithMappedMetadataSelective =
  await readTasksWithMappedMetadata({
    fields: ["id", "title", "completed"],
    metadataFields: ["meta1", "field2"],
  });

// Type validation for selective mapped metadata
if (readWithMappedMetadataSelective.success) {
  for (const task of readWithMappedMetadataSelective.data) {
    const taskId: string = task.id;
    const taskTitle: string = task.title;
    const taskCompleted: boolean = task.completed;

    // Only requested mapped metadata fields
    const meta1: string = task.meta1;
    const field2: number = task.field2;

    // isValid should NOT be accessible (not requested):
    // const isValid: boolean = task.isValid; // ❌ Should not exist
  }
}

// Test 13: Read action with mapped metadata - single field
export const readWithMappedMetadataSingle = await readTasksWithMappedMetadata({
  fields: ["id", "title"],
  metadataFields: ["isValid"],
});

// Type validation for single mapped metadata field
if (readWithMappedMetadataSingle.success) {
  for (const task of readWithMappedMetadataSingle.data) {
    const taskId: string = task.id;
    const taskTitle: string = task.title;

    // Only isValid should be present
    const isValid: boolean = task.isValid;

    // Other fields should NOT be accessible:
    // const meta1: string = task.meta1; // ❌ Should not exist
    // const field2: number = task.field2; // ❌ Should not exist
  }
}

// Test 14: Read action with mapped metadata - no metadata fields
export const readWithMappedMetadataNone = await readTasksWithMappedMetadata({
  fields: ["id", "title", "completed"],
});

// Type validation - no metadata fields should be present
if (readWithMappedMetadataNone.success) {
  for (const task of readWithMappedMetadataNone.data) {
    const taskId: string = task.id;
    const taskTitle: string = task.title;
    const taskCompleted: boolean = task.completed;

    // No metadata fields should be accessible:
    // const meta1: string = task.meta1; // ❌ Should not exist
    // const isValid: boolean = task.isValid; // ❌ Should not exist
    // const field2: number = task.field2; // ❌ Should not exist
  }
}

// Test 15: Verify TypeScript inference with const assertion and mapped metadata
export const readMappedMetadataConst = await readTasksWithMappedMetadata({
  fields: ["id", "title"],
  metadataFields: ["meta1", "isValid"],
});

// Type validation with const assertion
if (readMappedMetadataConst.success) {
  // TypeScript should infer exact field types with mapped names
  for (const task of readMappedMetadataConst.data) {
    const id: string = task.id;
    const title: string = task.title;
    const meta1: string = task.meta1;
    const isValid: boolean = task.isValid;
  }
}

console.log("Metadata tests should compile successfully!");
