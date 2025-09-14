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
import "./validate_fields_prototype";

// Import Zod schema validation tests
import "./zod/shouldPass/basicZodUsage";
import "./zod/shouldPass/complexSchemaValidation";

console.log("All shouldPass tests should compile successfully!");
