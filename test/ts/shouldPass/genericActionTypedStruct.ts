// SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
//
// SPDX-License-Identifier: MIT

import { getTaskStats, listTaskStats } from "../generated";

// Test that generic actions returning typed structs support field selection
export const taskStatsWithFieldSelection = await getTaskStats({
  input: { taskId: "123e4567-e89b-12d3-a456-426614174000" },
  fields: ["totalCount", "completed"],
});

if (taskStatsWithFieldSelection.success) {
  const data = taskStatsWithFieldSelection.data;

  // Should have selected fields
  const totalCount: number | null = data.totalCount;
  const completed: boolean | null = data.completed;

  // @ts-expect-error - isUrgent should not be accessible since it wasn't selected
  const isUrgent = data.isUrgent;

  // @ts-expect-error - averageDuration should not be accessible since it wasn't selected
  const averageDuration = data.averageDuration;
}

// Test with all fields
export const taskStatsWithAllFields = await getTaskStats({
  input: { taskId: "123e4567-e89b-12d3-a456-426614174000" },
  fields: ["totalCount", "completed", "isUrgent", "averageDuration"],
});

if (taskStatsWithAllFields.success) {
  const data = taskStatsWithAllFields.data;

  // All fields should be accessible
  const totalCount: number | null = data.totalCount;
  const completed: boolean | null = data.completed;
  const isUrgent: boolean | null = data.isUrgent;
  const averageDuration: number | null = data.averageDuration;
}

// Test array of typed structs with field selection
export const taskStatsListWithFieldSelection = await listTaskStats({
  fields: ["totalCount", "completed"],
});

if (taskStatsListWithFieldSelection.success) {
  const data = taskStatsListWithFieldSelection.data;

  // Should be an array
  const firstItem = data[0];
  if (firstItem) {
    // Should have selected fields
    const totalCount: number | null = firstItem.totalCount;
    const completed: boolean | null = firstItem.completed;

    // @ts-expect-error - isUrgent should not be accessible since it wasn't selected
    const isUrgent = firstItem.isUrgent;

    // @ts-expect-error - averageDuration should not be accessible since it wasn't selected
    const averageDuration = firstItem.averageDuration;
  }
}

// Test array of typed structs with all fields
export const taskStatsListWithAllFields = await listTaskStats({
  fields: ["totalCount", "completed", "isUrgent", "averageDuration"],
});

if (taskStatsListWithAllFields.success) {
  const data = taskStatsListWithAllFields.data;

  // Should be an array
  const firstItem = data[0];
  if (firstItem) {
    // All fields should be accessible
    const totalCount: number | null = firstItem.totalCount;
    const completed: boolean | null = firstItem.completed;
    const isUrgent: boolean | null = firstItem.isUrgent;
    const averageDuration: number | null = firstItem.averageDuration;
  }
}
