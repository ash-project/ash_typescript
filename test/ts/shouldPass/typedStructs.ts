// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

import { getTodo } from "../generated";

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
