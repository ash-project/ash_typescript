// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Lazy schemas of recursive embedded resources (TaskNote contains itself,
// TaskOutline and TaskOutlineItem each other) validate nested data.

import * as v from "valibot";
import {
  acceptTaskNotesValibotSchema,
  TaskNoteValibotSchema,
  TaskOutlineValibotSchema,
} from "../../ash_valibot";
import type { TaskNoteInputSchema } from "../../ash_types";

export function testRecursiveNoteAccepted() {
  const note: TaskNoteInputSchema = v.parse(TaskNoteValibotSchema, {
    body: "Root",
    replies: [{ body: "Reply", replies: [{ body: "Nested reply", replies: null }] }],
  });

  if (note.replies?.[0]?.replies?.[0]?.body !== "Nested reply") {
    throw new Error("Expected the nested reply to round-trip through the lazy schema");
  }
}

export function testMutuallyRecursiveOutlineAccepted() {
  const outline = v.parse(TaskOutlineValibotSchema, {
    title: "Plan",
    items: [{ label: "Step", sublist: { title: "Details", items: [{ label: "Substep" }] } }],
  });

  if (outline.items[0]?.sublist?.items[0]?.label !== "Substep") {
    throw new Error("Expected the nested outline to round-trip through the lazy schemas");
  }
}

export function testActionSchemaWithRecursiveArgumentsAccepted() {
  const input = v.parse(acceptTaskNotesValibotSchema, {
    note: { body: "Root", replies: [{ body: "Reply" }] },
    board: { pinned: { body: "Pinned", replies: [{ body: "Reply" }] } },
  });

  if (input.board?.pinned.replies?.[0]?.body !== "Reply") {
    throw new Error("Expected the board's pinned note to use the lazy note schema");
  }
}
