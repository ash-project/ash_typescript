// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
//
// SPDX-License-Identifier: MIT

// Sort Fields Tests - shouldPass
// Tests that valid sort field usage compiles correctly

import {
  listTodos,
  listUsers,
  listTodosNoFilter,
  listTodosNoSort,
} from "../generated";

import type { TodoSortField, UserSortField, SortString, TodoFilterField } from "../ash_types";
import { todoSortFields, todoFilterFields, userSortFields } from "../ash_types";

// Test 1: Single sort field (no prefix = ascending)
export const sortAsc = await listTodos({
  fields: ["id", "title"],
  sort: "title",
});

// Test 2: Descending sort with - prefix
export const sortDesc = await listTodos({
  fields: ["id", "title"],
  sort: "-createdAt",
});

// Test 3: Ascending with + prefix
export const sortAscExplicit = await listTodos({
  fields: ["id", "title"],
  sort: "+title",
});

// Test 4: Ascending nils first with ++ prefix
export const sortAscNilsFirst = await listTodos({
  fields: ["id", "title"],
  sort: "++dueDate",
});

// Test 5: Descending nils last with -- prefix
export const sortDescNilsLast = await listTodos({
  fields: ["id", "title"],
  sort: "--createdAt",
});

// Test 6: Array of sort fields (multiple sorts)
export const multiSort = await listTodos({
  fields: ["id", "title", "createdAt"],
  sort: ["-createdAt", "+title", "id"],
});

// Test 7: Sort by aggregate field
export const sortByAggregate = await listTodos({
  fields: ["id", "title"],
  sort: "-commentCount",
});

// Test 8: Sort by calculation field
export const sortByCalc = await listTodos({
  fields: ["id", "title"],
  sort: "isOverdue",
});

// Test 9: Sort works on action with filter disabled but sort enabled
export const sortNoFilter = await listTodosNoFilter({
  fields: ["id", "title"],
  sort: ["-title", "++id"],
});

// Test 10: Sort field type is usable as a standalone type
const field: TodoSortField = "title";
const userField: UserSortField = "name";
const sortExpr: SortString<TodoSortField> = "--createdAt";

// Test 11: Sort with all prefix variants on same call
export const allPrefixes = await listTodos({
  fields: ["id"],
  sort: ["title", "+title", "-title", "++title", "--title"],
});

// Test 12: User resource sort field
export const userSort = await listUsers({
  fields: ["id", "name"],
  sort: "-name",
});

// Test 13: as const arrays are runtime values — iterable and usable in UI
const sortFieldCount: number = todoSortFields.length;
const firstSortField: string = todoSortFields[0];
const sortFieldList: readonly string[] = todoSortFields;

// Test 14: filter field as const array
const filterFieldCount: number = todoFilterFields.length;
const firstFilterField: string = todoFilterFields[0];
const filterFieldList: readonly string[] = todoFilterFields;

// Test 15: as const array includes relationships for filter but not sort
// todoFilterFields includes "user", "comments" etc (relationships)
// todoSortFields does NOT include relationships
const sortHasNoRelationships: boolean = !todoSortFields.includes("user" as any);
const filterHasRelationships: boolean = todoFilterFields.includes("user");

// Test 16: filter fields include all aggregate kinds
const filterHasExists: boolean = todoFilterFields.includes("hasComments");
const filterHasMax: boolean = todoFilterFields.includes("highestRating");
const filterHasAvg: boolean = todoFilterFields.includes("averageRating");
const filterHasFirst: boolean = todoFilterFields.includes("latestCommentContent");
const filterHasList: boolean = todoFilterFields.includes("commentAuthors");

// Test 17: user sort fields as const array
const userSortFieldCount: number = userSortFields.length;

// Test 18: FilterField type works as standalone type
const filterField: TodoFilterField = "title";

console.log(field, userField, sortExpr, sortFieldCount, firstSortField, sortFieldList);
console.log(filterFieldCount, firstFilterField, filterFieldList, filterField);
console.log(sortHasNoRelationships, filterHasRelationships);
console.log(filterHasExists, filterHasMax, filterHasAvg, filterHasFirst, filterHasList);
console.log(userSortFieldCount);
console.log("All sort field tests should compile successfully!");
