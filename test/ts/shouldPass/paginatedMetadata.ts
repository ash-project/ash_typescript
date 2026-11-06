// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Paginated reads with metadata: each page's results carry the selected
// metadata fields, with and without a page in the config.

import {
  readTasksMetadataOffset,
  readTasksMetadataKeysetRequired,
  readTasksMetadataMixed,
} from "../generated";

export const unpaged = await readTasksMetadataOffset({
  fields: ["id"],
  metadataFields: ["someString"],
});

if (unpaged.success) {
  for (const task of unpaged.data) {
    const id: string = task.id;
    const meta: string | null | undefined = task.someString;
  }
}

export const offsetPage = await readTasksMetadataOffset({
  fields: ["id"],
  metadataFields: ["someString"],
  page: { limit: 10, offset: 0 },
});

if (offsetPage.success) {
  const offset: number = offsetPage.data.offset;
  const meta: string | null | undefined = offsetPage.data.results[0].someString;
}

export const keysetPage = await readTasksMetadataKeysetRequired({
  fields: ["id"],
  metadataFields: ["someString"],
  page: { limit: 10 },
});

if (keysetPage.success) {
  const next: string | null = keysetPage.data.nextPage;
  const meta: string | null | undefined = keysetPage.data.results[0].someString;
}

export const mixedPage = await readTasksMetadataMixed({
  fields: ["id"],
  metadataFields: ["someString"],
  page: { limit: 10, after: "cursor" },
});

if (mixedPage.success && mixedPage.data.type === "keyset") {
  const meta: string | null | undefined = mixedPage.data.results[0].someString;
}
