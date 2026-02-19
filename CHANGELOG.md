<!--
SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>

SPDX-License-Identifier: MIT
-->

# Change Log

All notable changes to this project will be documented in this file.
See [Conventional Commits](Https://conventionalcommits.org) for commit guidelines.

<!-- changelog -->

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
