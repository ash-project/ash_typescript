// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Hoisted `satisfies` field selections — regression coverage for issue #83.
//
// Hoisting a selection to a `const ... satisfies <Action>Fields` widens the
// array literal to an array-of-union, and TypeScript's union normalization
// adds synthetic `?: undefined` sibling properties to each object member.
// InferResult must skip those siblings instead of walking them as real
// selections, which previously collapsed the whole result type to `never`.

import { getTodo } from "../generated";
import type { GetTodoFields } from "../generated";
import type {
  InferResult,
  UnifiedFieldSelection,
  PostResourceSchema,
} from "../ash_types";

// Test 1: TypedMap field + relationship, hoisted with satisfies.
// The widened selection contains `{ options: ...; user?: undefined }` and
// `{ user: ...; options?: undefined }` members.
const typedMapAndRelationshipFields = [
  "id",
  { options: ["priority"] },
  { user: ["name"] },
] satisfies GetTodoFields;

export const todoWithTypedMapAndRelationship = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: typedMapAndRelationshipFields,
});

if (
  todoWithTypedMapAndRelationship.success &&
  todoWithTypedMapAndRelationship.data
) {
  const todoId: string = todoWithTypedMapAndRelationship.data.id;
  const userName: string = todoWithTypedMapAndRelationship.data.user.name;
  const options = todoWithTypedMapAndRelationship.data.options;
  if (options) {
    const priority: number = options.priority;
    console.log(todoId, userName, priority);
  }
}

// Test 2: two TypedMap fields side by side + relationship — every widened
// member carries `?: undefined` siblings for the other two object keys.
const twoTypedMapsFields = [
  "id",
  { options: ["priority"] },
  { statistics: ["viewCount"] },
  { user: ["name"] },
] satisfies GetTodoFields;

export const todoWithTwoTypedMaps = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: twoTypedMapsFields,
});

if (todoWithTwoTypedMaps.success && todoWithTwoTypedMaps.data) {
  const todoId: string = todoWithTwoTypedMaps.data.id;
  const viewCount: number | null | undefined =
    todoWithTwoTypedMaps.data.statistics?.viewCount;
  console.log(todoId, viewCount);
}

// Test 3: nullable union + relationship, hoisted with satisfies.
const nullableUnionFields = [
  "id",
  { content: ["note"] },
  { user: ["name"] },
] satisfies GetTodoFields;

export const todoWithNullableUnion = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: nullableUnionFields,
});

if (todoWithNullableUnion.success && todoWithNullableUnion.data) {
  const userName: string = todoWithNullableUnion.data.user.name;
  const note: string | undefined = todoWithNullableUnion.data.content?.note;
  console.log(userName, note);
}

// Test 4: two object member selections inside a union selection — the INNER
// array also widens, so the union member walker must skip `?: undefined`
// siblings too (`{ text: ...; checklist?: undefined }` etc.).
const unionMemberFields = [
  "id",
  { content: [{ text: ["text", "wordCount"] }, { checklist: ["title"] }] },
  { user: ["name"] },
] satisfies GetTodoFields;

export const todoWithUnionMembers = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: unionMemberFields,
});

if (todoWithUnionMembers.success && todoWithUnionMembers.data) {
  const todoId: string = todoWithUnionMembers.data.id;
  const content = todoWithUnionMembers.data.content;
  if (content && "text" in content && content.text) {
    const text: string = content.text.text;
    const wordCount: number | null = content.text.wordCount;
    console.log(text, wordCount);
  }
  if (content && "checklist" in content && content.checklist) {
    const title: string = content.checklist.title;
    console.log(title);
  }
  console.log(todoId);
}

// Test 5: NON-nullable union + relationship — the exact shape from issue #83.
// A non-nullable union enters the union branch of InferFieldValue directly,
// where a synthetic `engagement?: undefined` sibling previously produced
// `never` and the UnionToIntersection collapsed the whole result.
const postFields = [
  "id",
  { engagement: ["none", { metrics: ["views"] }, { survey: ["score"] }] },
  { author: ["name"] },
] satisfies UnifiedFieldSelection<PostResourceSchema>[];

declare const postResult: InferResult<PostResourceSchema, typeof postFields>;

const postId: string = postResult.id;
const authorName: string | undefined = postResult.author?.name;
const engagement = postResult.engagement;
if ("metrics" in engagement && engagement.metrics) {
  const views: number = engagement.metrics.views;
  console.log(views);
}
if ("survey" in engagement && engagement.survey) {
  const score: number = engagement.survey.score;
  console.log(score);
}
console.log(postId, authorName);

// Test 6: hoisted tuple selections (the documented workaround) keep working.
const tupleFields = <const F extends GetTodoFields>(f: F): F => f;
const HOISTED_TUPLE = tupleFields([
  "id",
  { options: ["priority"] },
  { user: ["name"] },
]);

export const todoWithHoistedTuple = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: HOISTED_TUPLE,
});

if (todoWithHoistedTuple.success && todoWithHoistedTuple.data) {
  const todoId: string = todoWithHoistedTuple.data.id;
  console.log(todoId);
}
