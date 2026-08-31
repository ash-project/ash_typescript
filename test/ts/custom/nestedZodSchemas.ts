// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Hand-authored Zod schemas referenced from `zod_mapping_overrides`, pulled into
// the generated schema file via a second `zod_import_into_generated` entry.
//
// Deliberately in a subdirectory: the generated `ash_zod.ts` sits one level up,
// so the emitted import path must resolve to `./custom/nestedZodSchemas` rather
// than a same-directory sibling.
import { z } from "zod";

export const geoPoint = z.object({
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180),
});
