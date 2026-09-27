// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Hand-authored Effect schemas referenced from `effect_mapping_overrides`,
// pulled into the generated schema file via a second
// `effect_import_into_generated` entry.
//
// Deliberately in a subdirectory: the generated `ash_effect.ts` sits one level
// up, so the emitted import path must resolve to
// `./custom/nestedEffectSchemas` rather than a same-directory sibling.
import { Schema } from "effect";

export const geoPoint = Schema.Struct({
  lat: Schema.Finite.check(Schema.isGreaterThanOrEqualTo(-90), Schema.isLessThanOrEqualTo(90)),
  lng: Schema.Finite.check(Schema.isGreaterThanOrEqualTo(-180), Schema.isLessThanOrEqualTo(180)),
});
