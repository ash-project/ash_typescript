// SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
//
// SPDX-License-Identifier: MIT

// TypeScript test file for validating INCORRECT usage patterns
// This file should FAIL to compile and demonstrates invalid usage that should be caught by TypeScript
//
// This is the entry point that imports all feature-specific failure test files

// Import all shouldFail feature tests
import "./shouldFail/invalidFields";
import "./shouldFail/invalidCalcArgs";
import "./shouldFail/invalidStructure";
import "./shouldFail/typeMismatches";
import "./shouldFail/unionValidation";
import "./shouldFail/customFetchErrors";
import "./shouldFail/invalidChannelUsage";
import "./shouldFail/operations";
import "./shouldFail/wrongPaginationTypes";

// Import Zod schema validation failure tests
import "./zod/shouldFail/invalidZodUsage";
import "./zod/shouldFail/complexInvalidSchemas";

console.log("This file should NOT compile due to TypeScript errors!");
