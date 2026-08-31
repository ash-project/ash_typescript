// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Hand-authored Valibot schemas referenced from `valibot_mapping_overrides`,
// pulled into the generated schema file via a second
// `valibot_import_into_generated` entry.
//
// Deliberately in a subdirectory: the generated `ash_valibot.ts` sits one level
// up, so the emitted import path must resolve to
// `./custom/nestedValibotSchemas` rather than a same-directory sibling.
import * as v from "valibot";

export const geoPoint = v.object({
  lat: v.pipe(v.number(), v.minValue(-90), v.maxValue(90)),
  lng: v.pipe(v.number(), v.minValue(-180), v.maxValue(180)),
});
