// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

import {
  getTodo,
  structNoInstanceValue,
  EchoStructNoInstanceInput,
  InferEchoStructNoInstanceResult,
} from "../generated";

export const todoWithStatistics = await getTodo({
  input: { id: "00000000-0000-0000-0000-000000000001" },
  fields: [
    "id",
    "title",
    {
      metadata: ["category"],
      user: ["id"],
    },
  ],
});

if (todoWithStatistics.success) {
  const data = todoWithStatistics.data;

  if (data?.metadata) {
    const category: string = data.metadata.category;
  }
}

// A :struct NewType without instance_of keeps its typescript_field_names
// (is_done? -> isDone, count_1 -> countOne) in input and output types.
// The input is type-level only: Ash casts a :struct without instance_of only
// from a struct. As a return it is field-selectable.
export const structNoInstanceInput: EchoStructNoInstanceInput = {
  value: { isDone: true, countOne: 2 },
};

export function readStructNoInstance(
  result: InferEchoStructNoInstanceResult<["isDone", "countOne"]>,
) {
  const isDone: boolean = result.isDone;
  const countOne: number | null = result.countOne;
  return { isDone, countOne };
}

export const structNoInstanceResult = await structNoInstanceValue({
  fields: ["isDone", "countOne"],
});

if (structNoInstanceResult.success) {
  const isDone: boolean = structNoInstanceResult.data.isDone;
  const countOne: number | null = structNoInstanceResult.data.countOne;
}
