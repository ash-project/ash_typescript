// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Hand-authored Effect schemas referenced from `effect_mapping_overrides`,
// pulled into the generated schema file via `effect_import_into_generated`.
import { Schema } from "effect";

export const objectId = Schema.String.check(Schema.isMinLength(3));
