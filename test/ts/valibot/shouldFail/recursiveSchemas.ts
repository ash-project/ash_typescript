// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// The rejection half of recursiveSchemas: the lazy schemas still validate
// below the first level.

import * as v from "valibot";
import {
  acceptTaskNotesValibotSchema,
  TaskNoteValibotSchema,
  TaskOutlineValibotSchema,
} from "../../ash_valibot";

function expectValiError(fn: () => unknown, message: string) {
  try {
    fn();
  } catch (error) {
    if (error instanceof v.ValiError) {
      return error.issues;
    }
    throw error;
  }

  throw new Error(message);
}

export function testRecursiveNoteRejectsInvalidNestedReply() {
  return expectValiError(
    () => v.parse(TaskNoteValibotSchema, { body: "Root", replies: [{ body: "Reply", replies: [{ body: "" }] }] }),
    "Should have thrown for an empty body two levels down",
  );
}

export function testMutuallyRecursiveOutlineRejectsInvalidNestedItem() {
  return expectValiError(
    () => v.parse(TaskOutlineValibotSchema, { title: "Plan", items: [{ label: "Step", sublist: { title: "Details", items: [{}] } }] }),
    "Should have thrown for a nested item without a label",
  );
}

export function testActionSchemaRejectsInvalidPinnedReply() {
  return expectValiError(
    () => v.parse(acceptTaskNotesValibotSchema, { board: { pinned: { body: "Pinned", replies: [{ body: 1 }] } } }),
    "Should have thrown for a non-string reply body under the board",
  );
}
