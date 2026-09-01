<!--
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>

SPDX-License-Identifier: MIT
-->

# Change Log

All notable changes to this project will be documented in this file.
See [Conventional Commits](Https://conventionalcommits.org) for commit guidelines.

<!-- changelog -->

## [v0.18.0](https://github.com/ash-project/ash_typescript/compare/v0.17.3...v0.18.0) (2026-08-31)

### Highlights:

Fuller context for the most significant changes in this release. The complete
commit-level record follows below.

#### Breaking

* typed-channel: broadcast payloads are now formatted with the `output_field_formatter` before reaching the client — `use AshTypescript.TypedChannel` intercepts the declared events and formats via `handle_out/3`, so the wire matches the generated payload types; the module must now also `use Phoenix.Channel` (compile warning otherwise) (#79)

* rpc: top-level `filter`/`sort`/`page` parameters now return `filter_not_supported`/`sort_not_supported`/`pagination_not_supported` errors when the action cannot honor them (non-list reads, disabled via `enable_filter?`/`enable_sort?`, or no pagination configured) instead of being silently dropped

* validation-schemas: the `AshTypescript.Codegen.SchemaFormatter` behaviour replaces the `custom_type_fallback/0` callback with `mapping_overrides/0`. Only affects out-of-tree formatter implementations; the two in-tree formatters (Zod, Valibot) are updated

#### Features

* rpc: nested relationship query options — paginate, filter, sort, and slice has_many/many_to_many loads inside field selection, with capability-gated TypeScript types and page-shaped results

* manifest-json: JSON manifest version 1.1 — new top-level `resources` object exposing per-relationship query capabilities (additive)

* codegen: `mix ash_typescript.codegen --output PATH` (alias `-o`) overrides the `output_file` config for a single run; a `.ts` path is used as the RPC file, anything else is treated as a directory (#65)

* validation-schemas: new `zod_mapping_overrides` / `valibot_mapping_overrides` config for controlling the schema generated for hand-rolled custom Ash types — the counterpart to `type_mapping_overrides`, and the only way to emit raw library syntax such as a Zod brand (#84)

* validation-schemas: new `zod_import_into_generated` / `valibot_import_into_generated` config injects user-authored imports into the generated schema files, so a mapping override can name a schema written in TypeScript (e.g. `"CustomZodSchemas.objectId"`) instead of an inline expression. Scoped per library rather than reusing `import_into_generated`, which targets the types and RPC files (#84)

#### Bug Fixes

* codegen: generated RPC action wrappers now type-check under `exactOptionalPropertyTypes: true` — the static `ActionConfig`/`ValidationConfig`/`ActionChannelConfig`/`ValidationChannelConfig` interfaces declare `| undefined` on their optional properties (#77)

* validation-schemas: hand-rolled custom Ash types now derive their schema from `Ash.Type.storage_type/1` instead of collapsing to a flat `z.string()`/`v.string()`. A custom type storing `:integer` previously generated a string schema that *rejected* its own valid values while the generated TypeScript type said `number`. `Ash.Type.NewType` was never affected — its constraints already flowed through (#84)

### Breaking Changes:

* rpc: nested query envelopes; strict top-level filter/sort/page by [@Torkan](https://github.com/Torkan)

* typed-controller: return route errors in the RPC error shape by [@Torkan](https://github.com/Torkan)

* errors: replace error `code` with `type` and keep placeholders client-resolvable by [@Torkan](https://github.com/Torkan)



### Features:

* validation-schemas: add schema mapping overrides for custom Ash types by [@Torkan](https://github.com/Torkan)

* codegen: add --output flag to override output_file for a single run (closes #65) by [@Torkan](https://github.com/Torkan)

* manifest-json: expose relationship query capabilities (manifest 1.1) by [@Torkan](https://github.com/Torkan)

* codegen: capability-gated types for nested relationship query options by [@Torkan](https://github.com/Torkan)

* manifest: decorate many-relationships with query capabilities by [@Torkan](https://github.com/Torkan)

* typed-controller: support array route arguments by [@Torkan](https://github.com/Torkan)

* manifest: add a Valibot Schema column to the Markdown manifest by [@Torkan](https://github.com/Torkan)

* typed-controller: apply Ash argument semantics and generate Valibot route schemas (CVE-2026-82732) by [@Torkan](https://github.com/Torkan)

* manifest: reject unmappable types and invalid rpc_action options at compile time by [@Torkan](https://github.com/Torkan)

* typed-channel: add independently toggleable publication warnings by [@Torkan](https://github.com/Torkan)

* installer: scaffold AshTypescriptManifest module and manifest config by [@Torkan](https://github.com/Torkan)

* manifest: precompute action classification, input maps and bulk strategy under Custom by [@Torkan](https://github.com/Torkan)

* manifest: add O(1) entrypoint lookup maps for RPC actions and typed queries by [@Torkan](https://github.com/Torkan)

* manifest: precompute runtime source-of-truth data under Custom decoration by [@Torkan](https://github.com/Torkan)

* manifest: decorate manifest with ash_typescript metadata under custom namespace by [@Torkan](https://github.com/Torkan)

* ash_api_spec: raise on non-public attrs in entrypoint accept lists by [@Torkan](https://github.com/Torkan)

* ash_api_spec: add type_lookup with strict get_type! lookup by [@Torkan](https://github.com/Torkan)

* ash_api_spec: add visibility options to include private fields in spec generation by [@Torkan](https://github.com/Torkan)

* add SpecCache with persistent_term for zero-cost spec reads by [@Torkan](https://github.com/Torkan)

* AshApiSpec: add convenience functions to Type and top-level module by [@Torkan](https://github.com/Torkan)

* AshApiSpec: hydrate union members with tag info and resolved types by [@Torkan](https://github.com/Torkan)

* populate entrypoint config from RPC DSL and use it in codegen by [@Torkan](https://github.com/Torkan)

* AshApiSpec: move actions from resources to top-level entrypoints by [@Torkan](https://github.com/Torkan)

* resolve type_ref in codegen and RPC runtime consumers by [@Torkan](https://github.com/Torkan)

* AshApiSpec: add overrides option and type_ref references for named types by [@Torkan](https://github.com/Torkan)

* ash-api-spec: add accessible_relationships and accepted_fields convenience functions by [@Torkan](https://github.com/Torkan)

* ash-api-spec: expand convenience API and adopt throughout codebase by [@Torkan](https://github.com/Torkan)

* rpc: add TypeIndex for pre-computed runtime type lookups by [@Torkan](https://github.com/Torkan)

* ash-api-spec: add resource lookup API and action-scoped generation by [@Torkan](https://github.com/Torkan)

* codegen: add AshApiSpec fast-path to FilterTypes and enforce resource_lookup by [@Torkan](https://github.com/Torkan)

* codegen: add AshApiSpec fast-path to ResourceSchemas and enforce resource_lookup by [@Torkan](https://github.com/Torkan)

* codegen: add %AshApiSpec.Field{} dispatch to TypeMapper and fix ensure_codegen_instance_of by [@Torkan](https://github.com/Torkan)

* codegen: generate AshApiSpec at entry point and thread resource_lookup to submodules by [@Torkan](https://github.com/Torkan)

* rpc: add %AshApiSpec.Resource{} fast path to FieldSelector by [@Torkan](https://github.com/Torkan)

* rpc: thread resource_lookups through runtime pipeline by [@Torkan](https://github.com/Torkan)

* rpc: persist resource lookups and add %Type{} dispatch for runtime type resolution by [@Torkan](https://github.com/Torkan)

* codegen: add %AshApiSpec.Type{} dispatch to TypeMapper and ResourceSchemas by [@Torkan](https://github.com/Torkan)

* ash-api-spec: add missing primitive types and fix type resolver edge cases by [@Torkan](https://github.com/Torkan)

* ash-api-spec: add reachability analysis, generator pipeline, and JSON serializer by [@Torkan](https://github.com/Torkan)

* ash-api-spec: add type resolver and builders by [@Torkan](https://github.com/Torkan)

* ash-api-spec: add struct definitions for API specification IR by [@Torkan](https://github.com/Torkan)

### Bug Fixes:

* typed-channel: format broadcast payloads with output_field_formatter (closes #79) by [@Torkan](https://github.com/Torkan)

* codegen: add | undefined to optional config props for exactOptionalPropertyTypes (closes #77) by [@Torkan](https://github.com/Torkan)

* typed-controller: gate unexpected handler return detail behind show_raised_errors (CVE-2026-82733) by [@Torkan](https://github.com/Torkan)

* typed-controller: reject colliding request params instead of silently merging by [@Torkan](https://github.com/Torkan)

* typed-controller: encode path params in generated route URLs (CVE-2026-82731) by [@Torkan](https://github.com/Torkan)

* rpc: redact ForbiddenField and NotLoaded in normalize_primitive (CVE-2026-82730) by [@Torkan](https://github.com/Torkan)

* rpc: reject non-scalar get_by values before trusted filter by [@Torkan](https://github.com/Torkan)

* rpc: reject non-scalar identity values before trusted filter by [@Torkan](https://github.com/Torkan)

* codegen: make restricted schemas restrict scalar loads by [@Torkan](https://github.com/Torkan)

* rpc: enforce load restrictions during field selection by [@Torkan](https://github.com/Torkan)

* rpc: stop minting atoms for typed struct field names (CVE-2026-77856) by [@Torkan](https://github.com/Torkan)

* rpc: stop unwrapping unknown structs into RPC error payloads by [@Torkan](https://github.com/Torkan)

* rpc: fail closed when a configured error handler crashes (CVE-2026-77950) by [@Torkan](https://github.com/Torkan)

* rpc: scope validate_action target lookup to the configured read_action by [@Torkan](https://github.com/Torkan)

* rpc: prevent atom-table exhaustion from client-supplied field names (CVE-2026-74837) by [@Torkan](https://github.com/Torkan)

* codegen: skip satisfies-widened undefined keys in InferResult by [@Torkan](https://github.com/Torkan)

* codegen: resolve leaf validation types by module before kind by [@Torkan](https://github.com/Torkan)

* rpc: serialize Ash.Type.Vector values as number arrays by [@Torkan](https://github.com/Torkan)

* codegen: add AshVector type alias for Ash.Type.Vector by [@Torkan](https://github.com/Torkan)

* typed-channel: emit grouped publication warnings to stderr by [@Torkan](https://github.com/Torkan)

* manifest: stop RPC config warnings failing --warnings-as-errors by [@Torkan](https://github.com/Torkan)

* mix: raise when npm install exits non-zero by [@Torkan](https://github.com/Torkan)

* installer: warn on a missing router and scaffold valibot config by [@Torkan](https://github.com/Torkan)

* codegen: support generation from an empty manifest by [@Torkan](https://github.com/Torkan)

* codegen: align pagination result types with runtime payloads by [@Torkan](https://github.com/Torkan)

* codegen: advertise the validation-channel function and centralize generated names by [@Torkan](https://github.com/Torkan)

* manifest: only advertise schema variants for actions that have one by [@Torkan](https://github.com/Torkan)

* typed-controller: export and advertise GET-route validation schemas by [@Torkan](https://github.com/Torkan)

* codegen: check and preview the manifests like any other artifact by [@Torkan](https://github.com/Torkan)

* codegen: attribute non-RPC resource references in the warning by [@Torkan](https://github.com/Torkan)

* rpc: resolve resources against scoped manifests during field processing by [@Torkan](https://github.com/Torkan)

* codegen: drive non-empty string schemas from allow_empty? constraints by [@Torkan](https://github.com/Torkan)

* codegen: correct type-level shapes for typed maps, keyset pages and channels by [@Torkan](https://github.com/Torkan)

* manifest: recompile the manifest module when its domains change by [@Torkan](https://github.com/Torkan)

* codegen: propagate array cardinality constraints by Rodolfo Torres

* codegen: restore @ashActionDef JSDoc tag via concrete action lookup by [@Torkan](https://github.com/Torkan)

* codegen: map Money/Ltree/ULID third-party types instead of falling back to any by [@Torkan](https://github.com/Torkan)

* test: respect explicit false for deadline_factor calc option by [@Torkan](https://github.com/Torkan)

* resource: validate map field names through NewType and array constraints by [@Torkan](https://github.com/Torkan)

* rpc: preserve false values when extracting plain map fields by [@Torkan](https://github.com/Torkan)

* guard typescript_field_names checks with Code.ensure_loaded?/1 by [@Torkan](https://github.com/Torkan)

* preserve false values when extracting plain map fields (#80) by [@vasspilka](https://github.com/vasspilka)

* reachability: traverse action returns and metadata types by [@Torkan](https://github.com/Torkan)

* resolve all dialyzer warnings in value_formatter and spec_cache by [@Torkan](https://github.com/Torkan)

* resolve rebase conflicts in codegen modules by [@Torkan](https://github.com/Torkan)

* handle type_ref in resource schema classification and action introspection by [@Torkan](https://github.com/Torkan)

* resolve dialyzer warning in generate_resource_lookup by [@Torkan](https://github.com/Torkan)

* remove dead code branch flagged by dialyzer in type_mapper by [@Torkan](https://github.com/Torkan)

* resolve dialyzer warnings by extracting array tuple clauses and removing dead fallbacks by [@Torkan](https://github.com/Torkan)

* rpc: use ActionIntrospection to determine input type for exports by [@Torkan](https://github.com/Torkan)

### Performance Improvements:

* use pre-computed resource_lookup instead of regenerating AshApiSpec inline by [@Torkan](https://github.com/Torkan)

## [v0.17.3](https://github.com/ash-project/ash_typescript/compare/v0.17.2...v0.17.3) (2026-04-30)




### Bug Fixes:

* perf: use persisted resource field names by [@Torkan](https://github.com/Torkan)

## [v0.17.2](https://github.com/ash-project/ash_typescript/compare/v0.17.1...v0.17.2) (2026-04-29)




### Bug Fixes:

* codegen: distinguish nullable from optional in zod and valibot schemas by Mike Wilson [(#70)](https://github.com/ash-project/ash_typescript/pull/70)

* codegen: sort enum values alphabetically in generated types by [@Torkan](https://github.com/Torkan)

### Performance Improvements:

* field_formatter: cache atom field name lookups per process by Mike Wilson [(#68)](https://github.com/ash-project/ash_typescript/pull/68)

## [v0.17.1](https://github.com/ash-project/ash_typescript/compare/v0.17.0...v0.17.1) (2026-04-15)




### Bug Fixes:

* generate correct validation schemas for AshMoney.Types.Money by [@Torkan](https://github.com/Torkan)

* preserve unconstrained map keys in action metadata by [@Torkan](https://github.com/Torkan)

* preserve unconstrained map keys in generic action output by [@Torkan](https://github.com/Torkan)

* camelize nested keys in read action typed map metadata by Mike Wilson [(#63)](https://github.com/ash-project/ash_typescript/pull/63)

## [v0.17.0](https://github.com/ash-project/ash_typescript/compare/v0.16.0...v0.17.0) (2026-03-29)




### Features:

* manifest: add valibot entries to JSON manifest by [@Torkan](https://github.com/Torkan)

* codegen: add typed sort fields with SortString utility type and array support by [@Torkan](https://github.com/Torkan)

* codegen: add isNil operator, expand aggregate filters, generate filter field arrays by [@Torkan](https://github.com/Torkan)

* valibot by [@directormac](https://github.com/directormac)

* add valibot to resolver and orchestrator by [@directormac](https://github.com/directormac)

* valibot generators by [@directormac](https://github.com/directormac)

### Bug Fixes:

* codegen: remove dead valibot import from generated RPC file by [@Torkan](https://github.com/Torkan)

* valibot: namespace export harcoded suffix by [@directormac](https://github.com/directormac)

* valibot: piped constraints by [@directormac](https://github.com/directormac)

* rpc: use load-through format for resource-returning calculations by [@Torkan](https://github.com/Torkan)

* codegen: distinguish resource from typed struct in return type classification by [@Torkan](https://github.com/Torkan)

* test: scope typed query const assertion to Typed Queries section by [@Torkan](https://github.com/Torkan)

* codegen: unwrap NewTypes before classifying return types for field selection by Mike Wilson

* delete vite/inertia combo as SSR didnt really work by Victor Batarse

* in prod if there was no manifest.json assets.deploy would crash with vite by Victor Batarse

* add csrf headers in all layouts by Victor Batarse

* colocated hooks on non react version by Victor Batarse

* on non-jsx framework caused crash by Victor Batarse

* esbuild versions CSS issues by Victor Batarse

## [v0.16.0](https://github.com/ash-project/ash_typescript/compare/v0.15.3...v0.16.0) (2026-03-23)


### Breaking Changes:

import_into_generated and typed_controller_import_into_generated file paths are now project-root-relative (e.g., "assets/js/hooks.ts") instead of JS-relative import paths (e.g., "./hooks")

### Features:

* codegen: exclude calculations with field?: false from generated types by [@Torkan](https://github.com/Torkan)

* typed-channel: auto-derive payload types from calculation transforms by [@Torkan](https://github.com/Torkan)

* rpc: verify actions and relationship read actions are public? by [@Torkan](https://github.com/Torkan)

* rpc: add machine-readable JSON manifest generation by [@Torkan](https://github.com/Torkan)

* typed-channel: detect payload type name conflicts across channels by [@Torkan](https://github.com/Torkan)

* typed-channel: add config accessors and orchestrator integration by [@Torkan](https://github.com/Torkan)

* typed-channel: add DSL, verifier, and codegen for typed channel event subscriptions by [@Torkan](https://github.com/Torkan)

* add typed_controller_base_path config for route URL prefixing by [@Torkan](https://github.com/Torkan)

* add HTTP verb shortcuts and positional method arg to typed controller DSL by [@Torkan](https://github.com/Torkan)

* add controller namespace support and simplify codegen orchestration by [@Torkan](https://github.com/Torkan)

* add multi-file codegen architecture and typed controller enhancements by [@Torkan](https://github.com/Torkan)

### Bug Fixes:

* test: use domain: nil for inline test resource not registered in a domain by [@Torkan](https://github.com/Torkan)

* bump minimum ash dep to >= 3.21.1 for field? support by [@Torkan](https://github.com/Torkan)

* rpc: unwrap Reactor.Error.Invalid.RunStepError to inner error by [@Torkan](https://github.com/Torkan)

* test: replace length/1 comparisons with empty list checks by [@Torkan](https://github.com/Torkan)

* test: use CodegenTestHelper instead of removed Rpc.Codegen API by [@Torkan](https://github.com/Torkan)

* codegen: generate Array<Record<string, any>> for {:array, :map} return types by [@barnabasJ](https://github.com/barnabasJ) [(#56)](https://github.com/ash-project/ash_typescript/pull/56)

* codegen: prefix unused actionName param with underscore when hooks disabled by [@Torkan](https://github.com/Torkan)

* test: add returns type to item_deleted publication to fix compile warning by [@Torkan](https://github.com/Torkan)

* codegen: resolve relative import paths correctly for parent directories by [@Torkan](https://github.com/Torkan)

* rpc: apply output formatter to channel field in channel functions by [@Torkan](https://github.com/Torkan)

* test: redirect typed_channels_output_file to tmp dir in codegen tests by [@Torkan](https://github.com/Torkan)

* typed-controller: default route method to nil instead of :get by [@Torkan](https://github.com/Torkan)

* use field formatter for channel handler fields by [@Torkan](https://github.com/Torkan)

## [v0.15.3](https://github.com/ash-project/ash_typescript/compare/v0.15.2...v0.15.3) (2026-02-21)




### Bug Fixes:

* sort RPC codegen output for deterministic TypeScript generation by [@Torkan](https://github.com/Torkan)

## [v0.15.2](https://github.com/ash-project/ash_typescript/compare/v0.15.1...v0.15.2) (2026-02-21)




### Bug Fixes:

* sort typed controller output for deterministic codegen by [@Torkan](https://github.com/Torkan)

## [v0.15.1](https://github.com/ash-project/ash_typescript/compare/v0.15.0...v0.15.1) (2026-02-21)




### Bug Fixes:

* restore method/module_name in spark formatter locals_without_parens by [@Torkan](https://github.com/Torkan)

* add typed_controller_path_params_style config option by [@Torkan](https://github.com/Torkan)

* codegen: check typescript_type_name before unwrapping NewTypes (#52) by [@Torkan](https://github.com/Torkan)

## [v0.15.0](https://github.com/ash-project/ash_typescript/compare/v0.14.4...v0.15.0) (2026-02-19)




### Features:

* add typed_controller_mode config for paths_only generation by [@Torkan](https://github.com/Torkan)

* generate query params and typed path helpers for TypedController routes by [@Torkan](https://github.com/Torkan)

* validate that path params have matching DSL arguments by [@Torkan](https://github.com/Torkan)

* typed-controller: validate route and argument names for TypeScript compatibility by [@Torkan](https://github.com/Torkan)

* add TypedController as standalone Spark DSL with argument extraction and type casting by [@Torkan](https://github.com/Torkan)

* controller-resource: normalize camelCase request params to snake_case by [@Torkan](https://github.com/Torkan)

* codegen: integrate controller resource route generation into mix task by [@Torkan](https://github.com/Torkan)

* add TypeScript route codegen with router introspection by [@Torkan](https://github.com/Torkan)

* add ControllerResource DSL extension with controller generation by [@Torkan](https://github.com/Torkan)

### Bug Fixes:

* codegen: check typescript_type_name before unwrapping NewTypes (#52) by [@Torkan](https://github.com/Torkan)

* prevent policy breakdown leak in Forbidden.Policy error responses by [@Torkan](https://github.com/Torkan)


## [v0.14.4](https://github.com/ash-project/ash_typescript/compare/v0.14.3...v0.14.4) (2026-02-14)




### Bug Fixes:

* rpc: add JSON-safe error serialization for policy breakdowns by [@Torkan](https://github.com/Torkan)

* zod: topologically sort resource schemas to fix declaration order by [@Torkan](https://github.com/Torkan)

## [v0.14.3](https://github.com/ash-project/ash_typescript/compare/v0.14.2...v0.14.3) (2026-02-11)




### Bug Fixes:

* codegen: scope always_regenerate to only apply with --dev flag by [@Torkan](https://github.com/Torkan)

## [v0.14.2](https://github.com/ash-project/ash_typescript/compare/v0.14.1...v0.14.2) (2026-02-10)




### Bug Fixes:

* rpc: ensure error responses are JSON-serializable by [@Torkan](https://github.com/Torkan)

* codegen: only export Config type for actions with optional pagination by [@Torkan](https://github.com/Torkan)

## [v0.14.1](https://github.com/ash-project/ash_typescript/compare/v0.14.0...v0.14.1) (2026-02-07)




### Bug Fixes:

* codegen: skip file writes when generated content is unchanged by [@Torkan](https://github.com/Torkan)

## [v0.14.0](https://github.com/ash-project/ash_typescript/compare/v0.13.2...v0.14.0) (2026-02-06)




### Features:

* codegen: add `always_regenerate` config to skip diff check by [@Torkan](https://github.com/Torkan)

### Bug Fixes:

* handle list input in ErrorBuilder.build_error_response/1 by Oliver Severin Mulelid-Tynes [(#48)](https://github.com/ash-project/ash_typescript/pull/48)

## [v0.13.2](https://github.com/ash-project/ash_typescript/compare/v0.13.1...v0.13.2) (2026-02-04)




### Bug Fixes:

* codegen: use field formatter more consistently by [@Torkan](https://github.com/Torkan)

## [v0.13.1](https://github.com/ash-project/ash_typescript/compare/v0.13.0...v0.13.1) (2026-02-04)




### Bug Fixes:

* codegen: use Mix.raise for clearer error output by [@Torkan](https://github.com/Torkan)

* verifiers: validate union member names for TypeScript compatibility by [@Torkan](https://github.com/Torkan)

* verifiers: skip field name validation when mapping exists by [@Torkan](https://github.com/Torkan)

## [v0.13.0](https://github.com/ash-project/ash_typescript/compare/v0.12.1...v0.13.0) (2026-02-01)




### Features:

* config: add developer experience configuration options by [@Torkan](https://github.com/Torkan)

* mix: handle multi-file output and manifest generation by [@Torkan](https://github.com/Torkan)

* codegen: add multi-file namespace output support by [@Torkan](https://github.com/Torkan)

* codegen: add markdown manifest generator by [@Torkan](https://github.com/Torkan)

* codegen: add JSDoc generator with configurable tags by [@Torkan](https://github.com/Torkan)

* codegen: add namespace resolution and domain grouping by [@Torkan](https://github.com/Torkan)

* dsl: add namespace, description, deprecated, and see options by [@Torkan](https://github.com/Torkan)

### Bug Fixes:

* codegen: fix TypeScript inference for NewType-wrapped unions by [@Torkan](https://github.com/Torkan)

* codegen: unwrap NewTypes in type discovery to find union members by [@Torkan](https://github.com/Torkan)

## [v0.12.1](https://github.com/ash-project/ash_typescript/compare/v0.12.0...v0.12.1) (2026-01-26)




### Bug Fixes:

* typed-queries: use satisfies for type-safe field constants by [@Torkan](https://github.com/Torkan)

* rpc: make tenant optional for non-multitenancy resources by [@Torkan](https://github.com/Torkan)

* don't expose exception messages for unknown errors by [@zachdaniel](https://github.com/zachdaniel)

## [v0.12.0](https://github.com/ash-project/ash_typescript/compare/v0.11.6...v0.12.0) (2026-01-17)




### Features:

* rpc: generate restricted schemas for allowed_loads actions by [@Torkan](https://github.com/Torkan)

* rpc: support first aggregates returning embedded resources and unions by [@Torkan](https://github.com/Torkan)

* rpc: add allowed_loads and denied_loads options for rpc_action by [@Torkan](https://github.com/Torkan)

* rpc: add enable_filter? and enable_sort? options for rpc_action by [@Torkan](https://github.com/Torkan)

## [v0.11.6](https://github.com/ash-project/ash_typescript/compare/v0.11.5...v0.11.6) (2026-01-13)




### Bug Fixes:

* rpc: prioritize direct headers and fetchOptions over lifecycle hook config by [@Torkan](https://github.com/Torkan)

## [v0.11.5](https://github.com/ash-project/ash_typescript/compare/v0.11.4...v0.11.5) (2026-01-08)




### Bug Fixes:

* codegen: discover embedded resources used as direct action arguments by [@Torkan](https://github.com/Torkan)

## [v0.11.4](https://github.com/ash-project/ash_typescript/compare/v0.11.3...v0.11.4) (2025-12-19)




### Bug Fixes:

* install: use find_module to locate router for custom module names by [@Torkan](https://github.com/Torkan)

## [v0.11.3](https://github.com/ash-project/ash_typescript/compare/v0.11.2...v0.11.3) (2025-12-17)




### Bug Fixes:

* types: add Duration struct support with ISO 8601 serialization by [@Torkan](https://github.com/Torkan)

## [v0.11.2](https://github.com/ash-project/ash_typescript/compare/v0.11.1...v0.11.2) (2025-12-09)




### Bug Fixes:

* rpc: simplify field mapping module selection with ActionIntrospection by [@Torkan](https://github.com/Torkan)

## [v0.11.1](https://github.com/ash-project/ash_typescript/compare/v0.11.0...v0.11.1) (2025-12-09)




### Bug Fixes:

* rpc: preserve empty arrays in JSON serialization (fixes #32) by [@Torkan](https://github.com/Torkan)

## [v0.11.0](https://github.com/ash-project/ash_typescript/compare/v0.10.2...v0.11.0) (2025-12-09)

### Breaking changes:

* All field mapping dsls and callbacks now require strings instead of atoms.
* Fields requested from calculations without arguments no longer need to be wrapped in `{fields: [...]}`


### Features:

* add VerifyActionTypes and VerifyUniqueInputFieldNames verifiers by [@Torkan](https://github.com/Torkan)

* add ResourceFields helper and extend Introspection by [@Torkan](https://github.com/Torkan)

* add FieldSelector for unified type-driven field selection by [@Torkan](https://github.com/Torkan)

* add ValueFormatter for unified type-aware value formatting by [@Torkan](https://github.com/Torkan)

### Bug Fixes:

* remove underscore in Zod schema name generation by [@Torkan](https://github.com/Torkan)

* cast struct inputs fully using Ash.Type by [@zachdaniel](https://github.com/zachdaniel)

* handle private arguments in action_inputs lookup by [@Torkan](https://github.com/Torkan)

* don't include private arguments in typescript codegen by [@zachdaniel](https://github.com/zachdaniel)

## [v0.10.2](https://github.com/ash-project/ash_typescript/compare/v0.10.1...v0.10.2) (2025-12-05)




### Bug Fixes:

* codegen: use field formatters for generated TypeScript config interfaces & rename hardcoded primaryKey fields to identity [@Torkan](https://github.com/Torkan)

## [v0.10.1](https://github.com/ash-project/ash_typescript/compare/v0.10.0...v0.10.1) (2025-12-04)




### Bug Fixes:

* rpc: consolidate field formatting and format error field names for by [@Torkan](https://github.com/Torkan)

* rpc: flatten multiple error responses by removing nested wrapper by [@Torkan](https://github.com/Torkan)

* test: generate TypeScript inline instead of reading from file by [@Torkan](https://github.com/Torkan)

## [v0.10.0](https://github.com/ash-project/ash_typescript/compare/v0.9.1...v0.10.0) (2025-12-04)

### Breaking Changes:

`primaryKey` input field for update & destroy rpc actions are now replaced by the more flexible `identities`-field


### Features:

* identities: add compile-time identity verification by [@Torkan](https://github.com/Torkan)

* identities: add identity-based record lookup for update/destroy actions by [@Torkan](https://github.com/Torkan)

### Bug Fixes:

* codegen: raise error instead of System.halt on generation failure by [@Torkan](https://github.com/Torkan)

## [v0.9.1](https://github.com/ash-project/ash_typescript/compare/v0.9.0...v0.9.1) (2025-12-01)




### Bug Fixes:

* struct-args: support Ash resources as struct action arguments by [@Torkan](https://github.com/Torkan)

## [v0.9.0](https://github.com/ash-project/ash_typescript/compare/v0.8.0...v0.9.0) (2025-11-30)




### Features:

* codegen: generate TypeScript types for get? and get_by actions by [@Torkan](https://github.com/Torkan)

* rpc: add compile-time verification for get options by [@Torkan](https://github.com/Torkan)

* rpc: implement get? and get_by runtime execution by [@Torkan](https://github.com/Torkan)

* rpc: add get?, get_by, and not_found_error? DSL options by [@Torkan](https://github.com/Torkan)

## [v0.9.0](https://github.com/ash-project/ash_typescript/compare/v0.8.4...v0.9.0) (2025-11-30)




### Features:

* codegen: generate TypeScript types for get? and get_by actions by [@Torkan](https://github.com/Torkan)

* rpc: add compile-time verification for get options by [@Torkan](https://github.com/Torkan)

* rpc: implement get? and get_by runtime execution by [@Torkan](https://github.com/Torkan)

* rpc: add get?, get_by, and not_found_error? DSL options by [@Torkan](https://github.com/Torkan)

## [v0.8.4](https://github.com/ash-project/ash_typescript/compare/v0.8.3...v0.8.4) (2025-11-25)




### Bug Fixes:

* codegen: support calculation fields in aggregates across all modules by [@Torkan](https://github.com/Torkan)

* rpc: respect allow_nil_input and require_attributes for input type optionality by [@Torkan](https://github.com/Torkan)

* support sum aggregates over calculations and discover calculation argument types by Oliver Severin Mulelid-Tynes [(#23)](https://github.com/ash-project/ash_typescript/pull/23)

## [v0.8.3](https://github.com/ash-project/ash_typescript/compare/v0.8.2...v0.8.3) (2025-11-24)




### Bug Fixes:

* improved error message for missing AshTypescript.Resource extension or missing typescript dsl-block
* add closing backticks on the code example for composite type field selection by Jacob Bahn [(#21)](https://github.com/ash-project/ash_typescript/pull/21)

## [v0.8.2](https://github.com/ash-project/ash_typescript/compare/v0.8.1...v0.8.2) (2025-11-20)




### Bug Fixes:

* codegen: export Infer*Result types from generated TypeScript by [@Torkan](https://github.com/Torkan)

## [v0.8.1](https://github.com/ash-project/ash_typescript/compare/v0.8.0...v0.8.1) (2025-11-20)




### Bug Fixes:

* test: remove URLs from argsWithFieldConstraints to fix parser issue by [@Torkan](https://github.com/Torkan)

* codegen: make nullable fields optional and fix spacing in input types by [@Torkan](https://github.com/Torkan)

* codegen: use get_ts_input_type for argument types in input schemas by [@Torkan](https://github.com/Torkan)

* Add default boolean values to config getters by zeadhani [(#20)](https://github.com/ash-project/ash_typescript/pull/20)

## [v0.8.0](https://github.com/ash-project/ash_typescript/compare/v0.7.1...v0.8.0) (2025-11-19)




### Features:

* add FieldExtractor module for unified tuple/keyword/map extraction by [@Torkan](https://github.com/Torkan)

### Bug Fixes:

* exclude struct union members with instance_of from primitiveFields by [@Torkan](https://github.com/Torkan)

* require wrapped format for union inputs with proper validation by [@Torkan](https://github.com/Torkan)

* add is_primitive_struct? check in result_processor by [@Torkan](https://github.com/Torkan) [(#17)](https://github.com/ash-project/ash_typescript/pull/17)

### Improvements:

* preserve TypedStruct instance_of for field name mappings by [@Torkan](https://github.com/Torkan)

* standardize RPC error structure with vars, path, fields, details by [@Torkan](https://github.com/Torkan)

* use bulk actions for update/destroy by [@zachdaniel](https://github.com/zachdaniel) [(#17)](https://github.com/ash-project/ash_typescript/pull/17)

* support `read_action` configuration by [@zachdaniel](https://github.com/zachdaniel) [(#17)](https://github.com/ash-project/ash_typescript/pull/17)

* better error handling & struct field selection in RPC by [@zachdaniel](https://github.com/zachdaniel) [(#17)](https://github.com/ash-project/ash_typescript/pull/17)

## [v0.7.1](https://github.com/ash-project/ash_typescript/compare/v0.7.0...v0.7.1) (2025-11-08)




### Bug Fixes:

* add missing resources to typescript_rpc in test setup to fix compile warnings by [@Torkan](https://github.com/Torkan)

## [v0.7.0](https://github.com/ash-project/ash_typescript/compare/v0.6.4...v0.7.0) (2025-11-08)




### Features:

* add configurable warnings for RPC resource discovery and references by [@Torkan](https://github.com/Torkan)

* add resource scanner for embedded resource discovery by [@Torkan](https://github.com/Torkan)

## [v0.6.4](https://github.com/ash-project/ash_typescript/compare/v0.6.3...v0.6.4) (2025-11-03)




### Bug Fixes:

* add reusable action/validation helpers, improve lifecycle hook types by [@Torkan](https://github.com/Torkan)

## [v0.6.3](https://github.com/ash-project/ash_typescript/compare/v0.6.2...v0.6.3) (2025-11-01)




### Bug Fixes:

* use type constraints in zod schema generation by [@Torkan](https://github.com/Torkan)

## [v0.6.2](https://github.com/ash-project/ash_typescript/compare/v0.6.1...v0.6.2) (2025-10-28)




### Bug Fixes:

* rpc: make fields parameter optional with proper type inference by [@Torkan](https://github.com/Torkan)

* rpc: improve type inference for optional fields parameter by [@Torkan](https://github.com/Torkan)

* rpc: generate optional fields parameter for create/update in TypeScript by [@Torkan](https://github.com/Torkan)

* rpc: make fields parameter optional for create and update actions by [@Torkan](https://github.com/Torkan)

## [v0.6.1](https://github.com/ash-project/ash_typescript/compare/v0.6.0...v0.6.1) (2025-10-27)




### Bug Fixes:

* codegen: deduplicate resources when exposed in multiple domains by [@Torkan](https://github.com/Torkan)

* codegen: fix mapped field names usage in typed queries by [@Torkan](https://github.com/Torkan)

## [v0.6.0](https://github.com/ash-project/ash_typescript/compare/v0.5.0...v0.6.0) (2025-10-21)




### Features:

* rpc: implement lifecycle hooks in TypeScript codegen by [@Torkan](https://github.com/Torkan)

* rpc: add lifecycle hooks configuration API by [@Torkan](https://github.com/Torkan)

* codegen: add configurable untyped map type by [@Torkan](https://github.com/Torkan)

* rpc: add custom error response handler support by [@Torkan](https://github.com/Torkan)

* rpc: add support for dynamic endpoint configuration via imported TypeScript functions by [@Torkan](https://github.com/Torkan)

* rpc: add typed query field verification at compile time by [@Torkan](https://github.com/Torkan)

* add type_mapping_overrides config setting by [@Torkan](https://github.com/Torkan)

* codegen: warn when resources have extension but missing from domain by [@Torkan](https://github.com/Torkan)

### Bug Fixes:

* add support for generic actions returning typed struct(s) by [@Torkan](https://github.com/Torkan)

## [v0.5.0](https://github.com/ash-project/ash_typescript/compare/v0.4.0...v0.5.0) (2025-10-13)




### Features:

* add action metadata support with field name mapping by [@Torkan](https://github.com/Torkan)

* add precise pagination type constraints to prevent misuse by [@Torkan](https://github.com/Torkan)

* add VerifierChecker utility for Spark verifier validation by [@Torkan](https://github.com/Torkan)

* support typescript_field_names callback in codegen by [@Torkan](https://github.com/Torkan)

* add map field name validation for custom types by [@Torkan](https://github.com/Torkan)

* add field_names & argument_names for mapping invalid typescript names to valid ones by [@Torkan](https://github.com/Torkan)

### Bug Fixes:

* apply field name mappings to Zod schemas for all field types by [@Torkan](https://github.com/Torkan)

* apply field name mappings in RPC request/result processing by [@Torkan](https://github.com/Torkan)

* apply field name mappings in TypeScript codegen by [@Torkan](https://github.com/Torkan)

* use mapped field names & argument names in codegen by [@Torkan](https://github.com/Torkan)

## [v0.4.0](https://github.com/ash-project/ash_typescript/compare/v0.3.3...v0.4.0) (2025-09-29)




### Features:

* Properly handle map without constraints, both as input and output. by [@Torkan](https://github.com/Torkan)

### Bug Fixes:

* Add verifier that checks that resources with rpc actions use by [@Torkan](https://github.com/Torkan)

* reject loading of relationships for resources without AshTypescript.Resource extension. by [@Torkan](https://github.com/Torkan)

* use __array: true for union types on resource schema by [@Torkan](https://github.com/Torkan)

* generate correct types for array union attributes. by [@Torkan](https://github.com/Torkan)

* For generic actions that return an untyped map, remove fields-arg by [@Torkan](https://github.com/Torkan)

### Improvements:

* add unique type_name verifier for AshTypescript.Resource by [@Torkan](https://github.com/Torkan)

* remove redundant path-tracking & cleanup of code in formatters. by [@Torkan](https://github.com/Torkan)

* remove redundant cast_input in color_palette.ex by [@Torkan](https://github.com/Torkan)

## v0.3.3 (2025-09-20)




### Improvements:

* run npm install automatically on installation by Zach Daniel

## v0.3.2 (2025-09-20)




### Bug Fixes:

* change installer config: --react -> --framework react by Torkild Kjevik

## v0.3.1 (2025-09-20)




### Improvements:

* add igniter install notices. by Torkild Kjevik

## v0.3.0 (2025-09-20)




### Features:

* add igniter installer by Torkild Kjevik

### Improvements:

* add rpc routes & basic react setup in installer by Torkild Kjevik

* use String.contains? for checking if rpc routes already exist by Torkild Kjevik

* Set default config in config.exs by Torkild Kjevik

## v0.2.0 (2025-09-17)




### Features:

* Add Phoenix Channel support & generation of channel functions. by Torkild Kjevik

### Bug Fixes:

* Only send relevant data to the backend. by Torkild Kjevik

### Improvements:

* prefix socket assigns with `ash_` by Torkild Kjevik

* Add timeout parameter to channel rpc actions. by Torkild Kjevik

## v0.1.2 (2025-09-15)




### Improvements:

* Use correct casing in dsl docs filenames. by Torkild Kjevik

## v0.1.1 (2025-09-15)




### Bug Fixes:

* Add codegen-callback for ash.codegen. by Torkild Kjevik

* update typespec for run_typed_query/4 by Torkild Kjevik

* Use correct name for entities in rpc verifier. by Torkild Kjevik

### Improvements:

* add support for AshPostgres.Ltree type. by Torkild Kjevik

* add custom http client support. by Torkild Kjevik

* build related issues, update ash by Zach Daniel

## v0.1.0 (2025-09-13)


### Features:

* Initial feature set
