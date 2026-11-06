// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Typed queries with relationship envelopes and client-name selections - shouldPass

import {
  listTodos,
  listUsers,
  listUsersWithFilteredTodos,
  ListUsersWithFilteredTodosResult,
  listUsersWithListFilter,
  ListUsersWithListFilterResult,
  listUsersWithKeywordFilter,
  ListUsersWithKeywordFilterResult,
  listTodosKeywordEnvelope,
  listTodosMapEnvelope,
  ListTodosKeywordEnvelopeResult,
  ListTodosMapEnvelopeResult,
  ListTodosFields,
} from "../generated";
import type { InferResult, TodoResourceSchema } from "../ash_types";

// A keyword-form envelope with filter, sort and a bare slice infers an array
export function keywordEnvelopeComments(rows: ListTodosKeywordEnvelopeResult) {
  const contents: string[] = rows.flatMap((todo) =>
    todo.comments.map((comment) => comment.content),
  );
  return contents;
}

// A map-form envelope with page infers the page shape; fields alone an array
export function mapEnvelopeComments(rows: ListTodosMapEnvelopeResult) {
  const ids: string[] = rows.flatMap((todo) =>
    todo.comments.results.map((comment) => comment.id),
  );
  const count: number | null | undefined = rows[0]?.comments.count;
  const commenterIds: string[] = rows.flatMap((todo) =>
    todo.commenters.map((user) => user.id),
  );
  return { ids, count, commenterIds };
}

// The selection typed_query_client_names_test.exs pins for typed queries
// written with client names (strings) or internal names, as generated
const byClientNames = ["id", { user: ["id", "isActive"] }, { colorPalette: ["primary"] }, { content: ["note", { text: ["wordCount"] }] }, { self: { args: { prefix: "x" }, fields: ["id"] } }, { comments: { filter: { or: [{ authorName: { eq: "Ann" } }, { isHelpful: { eq: true } }] }, sort: ["-authorName", "id"], limit: 1, fields: ["id", "authorName"] } }, { offsetComments: { page: { limit: 1, offset: 1 }, fields: ["id"] } }, { keysetComments: { sort: ["authorName", "-content"], fields: ["content"] } }, { unfilterableComments: { sort: "-content", fields: ["content"] } }] satisfies ListTodosFields;

type ByClientNamesResult = Array<InferResult<TodoResourceSchema, ["id", { user: ["id", "isActive"] }, { colorPalette: ["primary"] }, { content: ["note", { text: ["wordCount"] }] }, { self: { args: { prefix: "x" }, fields: ["id"] } }, { comments: { filter: { or: [{ authorName: { eq: "Ann" } }, { isHelpful: { eq: true } }] }, sort: ["-authorName", "id"], limit: 1, fields: ["id", "authorName"] } }, { offsetComments: { page: { limit: 1, offset: 1 }, fields: ["id"] } }, { keysetComments: { sort: ["authorName", "-content"], fields: ["content"] } }, { unfilterableComments: { sort: "-content", fields: ["content"] } }]>>;

export function clientNameFields(rows: ByClientNamesResult) {
  const todo = rows[0];
  if (!todo) return null;
  const active: boolean | null | undefined = todo.user.isActive;
  const primary: string = todo.colorPalette?.primary ?? "";
  const authors: string[] = todo.comments.map((c) => c.authorName);
  const selfId: string | undefined = todo.self?.id;
  const offset: number = todo.offsetComments.offset;
  const pageIds: string[] = todo.offsetComments.results.map((c) => c.id);
  const sorted: string[] = todo.keysetComments.map((c) => c.content);
  return { active, primary, authors, selfId, offset, pageIds, sorted };
}

export const refetchClientNames = await listTodos({ fields: byClientNames });

// Structured filter values (keyword, union member, tuple, untyped map) in an
// envelope type-check against the destination's FilterInput
export function filteredTodoTitles(rows: ListUsersWithFilteredTodosResult) {
  const titles: string[] = rows.flatMap((user) => user.todos.map((todo) => todo.title));
  return titles;
}

export const refetchFilteredTodos = await listUsers({ fields: listUsersWithFilteredTodos });

// List and keyword-list filters render as `and`, a tuple value as its fields
export function listFilterTitles(
  listRows: ListUsersWithListFilterResult,
  keywordRows: ListUsersWithKeywordFilterResult,
) {
  const titles: string[] = [...listRows, ...keywordRows].flatMap((user) =>
    user.todos.map((todo) => todo.title),
  );
  return titles;
}

export const refetchListFilter = await listUsers({ fields: listUsersWithListFilter });
export const refetchKeywordFilter = await listUsers({ fields: listUsersWithKeywordFilter });

// The field constants are usable as RPC fields for client-side refetching
export const refetchKeyword = await listTodos({ fields: listTodosKeywordEnvelope });
export const refetchMap = await listTodos({ fields: listTodosMapEnvelope });

if (refetchMap.success) {
  const firstPage = refetchMap.data.map((todo) => todo.comments.hasMore);
  console.log(firstPage);
}
