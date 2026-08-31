// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Hand-authored Zod schemas referenced from `zod_mapping_overrides`, pulled into
// the generated schema file via `zod_import_into_generated`.
import { z } from "zod";

export const objectId = z.string().min(3);
