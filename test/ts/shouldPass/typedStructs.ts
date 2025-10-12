// SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
//
// SPDX-License-Identifier: MIT

import { getTodo } from "../generated";

export const todoWithStatistics = await getTodo({
  input: {},
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
