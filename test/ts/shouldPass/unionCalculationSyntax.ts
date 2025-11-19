// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Test file to demonstrate fetching a ash resource in a calculation that returns a union type
import { getContent } from "../generated";

const result = await getContent({
  input: { id: "123e4567-e89b-12d3-a456-426614174000" },
  fields: [
    "id",
    "category",
    "title",
    "type",
    "thumbnailUrl",
    "thumbnailAlt",
    "publishedAt",
    {
      item: {
        fields: [{ article: ["id", "heroImageAlt"] }],
      },
    },
  ],
});
