// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Runtime test runner for Zod constraint validation
// This script executes the constraint validation tests and verifies they work at runtime

import * as shouldPass from "./zod/shouldPass/constraintValidation";
import * as shouldFail from "./zod/shouldFail/constraintValidation";

interface TestResult {
  name: string;
  passed: boolean;
  error?: string;
}

const results: TestResult[] = [];

function runTest(name: string, fn: () => any): void {
  try {
    fn();
    results.push({ name, passed: true });
    console.log(`✓ ${name}`);
  } catch (error) {
    results.push({
      name,
      passed: false,
      error: error instanceof Error ? error.message : String(error)
    });
    console.error(`✗ ${name}: ${error instanceof Error ? error.message : error}`);
  }
}

console.log("\n========================================");
console.log("Running Zod Constraint Validation Tests");
console.log("========================================\n");

console.log("--- Tests that SHOULD PASS (valid constraints) ---\n");

runTest("testIntegerMinConstraint", () => shouldPass.testIntegerMinConstraint());
runTest("testIntegerMaxConstraint", () => shouldPass.testIntegerMaxConstraint());
runTest("testIntegerMidRangeConstraint", () => shouldPass.testIntegerMidRangeConstraint());
runTest("testStringMinLengthConstraint", () => shouldPass.testStringMinLengthConstraint());
runTest("testStringMaxLengthConstraint", () => shouldPass.testStringMaxLengthConstraint());
runTest("testStringMidRangeLengthConstraint", () => shouldPass.testStringMidRangeLengthConstraint());
runTest("testRegexConstraintValid", () => shouldPass.testRegexConstraintValid());
runTest("testRegexConstraintHttpUrl", () => shouldPass.testRegexConstraintHttpUrl());
runTest("testAllConstraintsTogether", () => shouldPass.testAllConstraintsTogether());
runTest("testSafeParsingWithConstraints", () => shouldPass.testSafeParsingWithConstraints());
runTest("testOptionalConstrainedField", () => shouldPass.testOptionalConstrainedField());

console.log("\n--- Tests that SHOULD FAIL (invalid constraints) ---\n");

runTest("testIntegerBelowMin", () => shouldFail.testIntegerBelowMin());
runTest("testIntegerAboveMax", () => shouldFail.testIntegerAboveMax());
runTest("testIntegerNegative", () => shouldFail.testIntegerNegative());
runTest("testStringEmpty", () => shouldFail.testStringEmpty());
runTest("testStringTooLong", () => shouldFail.testStringTooLong());
runTest("testStringWayTooLong", () => shouldFail.testStringWayTooLong());
runTest("testRegexInvalidUrl", () => shouldFail.testRegexInvalidUrl());
runTest("testRegexFtpUrl", () => shouldFail.testRegexFtpUrl());
runTest("testMultipleConstraintViolations", () => shouldFail.testMultipleConstraintViolations());
runTest("testSafeParseConstraintViolation", () => shouldFail.testSafeParseConstraintViolation());
runTest("testIntegerFloatingPoint", () => shouldFail.testIntegerFloatingPoint());
runTest("testBoundaryViolations", () => shouldFail.testBoundaryViolations());
runTest("testRequiredFieldMissing", () => shouldFail.testRequiredFieldMissing());

console.log("\n========================================");
console.log("Test Results Summary");
console.log("========================================\n");

const passed = results.filter(r => r.passed).length;
const failed = results.filter(r => !r.passed).length;
const total = results.length;

console.log(`Total: ${total}`);
console.log(`Passed: ${passed} ✓`);
console.log(`Failed: ${failed} ✗`);

if (failed > 0) {
  console.log("\nFailed tests:");
  results
    .filter(r => !r.passed)
    .forEach(r => {
      console.log(`  - ${r.name}: ${r.error}`);
    });
  throw new Error(`${failed} test(s) failed`);
} else {
  console.log("\n✓ All Zod constraint validation tests passed!");
}
