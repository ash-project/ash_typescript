// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// TypeScript test file for validating correct usage of generated types
// This file should compile without errors and demonstrates valid usage patterns
//
// This is the entry point that imports all feature-specific test files

// Import all shouldPass feature tests
import "./shouldPass/customTypes";
import "./shouldPass/calculations";
import "./shouldPass/relationships";
import "./shouldPass/operations";
import "./shouldPass/embeddedResources";
import "./shouldPass/unionTypes";
import "./shouldPass/typedMaps";
import "./shouldPass/complexScenarios";
import "./shouldPass/typedStructs";
import "./shouldPass/validationErrors";
import "./shouldPass/keywordTuple";
import "./shouldPass/customFetch";
import "./shouldPass/fetchOptionsAdvanced";
import "./shouldPass/channelOperations";
import "./shouldPass/channelValidations";
import "./shouldPass/channelTimeoutTest";
import "./shouldPass/channelLifecycleHooks";
import "./shouldPass/untypedMaps";
import "./shouldPass/conditionalPagination";
import "./shouldPass/precisePaginationTypes";
import "./shouldPass/metadata";
import "./shouldPass/genericActionTypedStruct";
import "./shouldPass/rpcLifecycleHooks";
import "./shouldPass/noFields";
import "./rpcHooks";

// Import Zod schema validation tests
import "./zod/shouldPass/basicZodUsage";
import "./zod/shouldPass/complexSchemaValidation";

console.log("All shouldPass tests should compile successfully!");
