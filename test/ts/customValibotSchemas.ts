// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Hand-authored Valibot schemas named by the test manifest's `custom_types`
// `valibot` options, pulled into the generated schema file via
// `valibot_import_into_generated`.
import * as v from "valibot";

export const objectId = v.pipe(v.string(), v.minLength(3));
