// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Constraint Validation Tests - shouldPass
// Tests for valid constraint validation with generated schemas

import { z } from "zod";
import {
  createOrgTodo,
  createOrgTodoZodSchema,
  AshTypescriptTestTodoContentLinkContentZodSchema,
} from "../../generated";

// Helper to create valid base data
function createValidBaseData() {
  return {
    title: "Test",
    userId: "123e4567-e89b-12d3-a456-426614174000",
    numberOfEmployees: 10,
    someString: "valid",
    email: "test@example.com",
    phoneNumber: "+15551234567",
    hexColor: "#123456",
    slug: "test",
    version: "1.0.0",
    caseInsensitiveCode: "ABC-1234",
    price: 10.50,
    temperature: 20.0,
    percentage: 50.0,
    username: "testuser",
    companyName: "Acme Corp",
    countryCode: "US",
    autoComplete: false,
    address: { streetAddress: "123 Main St", locationId: "LOC123" },
  };
}

// Test 1: Valid integer constraints - minimum value
export function testIntegerMinConstraint() {
  const validData = {
    ...createValidBaseData(),
    numberOfEmployees: 1, // Exactly at minimum (min: 1)
  };

  const validated = createOrgTodoZodSchema.parse(validData);
  console.log("Integer min constraint passed:", validated.numberOfEmployees);
  return validated;
}

// Test 2: Valid integer constraints - maximum value
export function testIntegerMaxConstraint() {
  const validData = {
    ...createValidBaseData(),
    numberOfEmployees: 1000, // Exactly at maximum (max: 1000)
  };

  const validated = createOrgTodoZodSchema.parse(validData);
  console.log("Integer max constraint passed:", validated.numberOfEmployees);
  return validated;
}

// Test 3: Valid integer constraints - mid-range value
export function testIntegerMidRangeConstraint() {
  const validData = {
    ...createValidBaseData(),
    numberOfEmployees: 500, // Mid-range value
  };

  const validated = createOrgTodoZodSchema.parse(validData);
  return validated;
}

// Test 4: Valid string constraints - minimum length
export function testStringMinLengthConstraint() {
  const validData = {
    ...createValidBaseData(),
    someString: "a", // Exactly at minimum (min_length: 1)
  };

  const validated = createOrgTodoZodSchema.parse(validData);
  console.log("String min length constraint passed:", validated.someString);
  return validated;
}

// Test 5: Valid string constraints - maximum length
export function testStringMaxLengthConstraint() {
  const validData = {
    ...createValidBaseData(),
    someString: "a".repeat(100), // Exactly at maximum (max_length: 100)
  };

  const validated = createOrgTodoZodSchema.parse(validData);
  console.log("String max length constraint passed, length:", validated.someString.length);
  return validated;
}

// Test 6: Valid string constraints - mid-range length
export function testStringMidRangeLengthConstraint() {
  const validData = {
    ...createValidBaseData(),
    someString: "This is a valid string with moderate length",
  };

  const validated = createOrgTodoZodSchema.parse(validData);
  return validated;
}

// Test 7: Valid regex constraint - simple URL pattern
export function testRegexConstraintValid() {
  const validData = {
    url: "https://example.com", // Matches ^https?://
    title: "Example link",
  };

  const validated = AshTypescriptTestTodoContentLinkContentZodSchema.parse(validData);
  console.log("Regex constraint passed:", validated.url);
  return validated;
}

// Test 8: Valid regex constraint - HTTP URL
export function testRegexConstraintHttpUrl() {
  const validData = {
    url: "http://example.com", // Also matches ^https?://
    title: "Example link",
  };

  const validated = AshTypescriptTestTodoContentLinkContentZodSchema.parse(validData);
  return validated;
}

// Test 9: All constraints together - valid scenario
export function testAllConstraintsTogether() {
  const validData = {
    ...createValidBaseData(),
    title: "Complete todo",
    description: "This has all valid fields",
    status: "pending",
    priority: "high",
    numberOfEmployees: 250, // Valid: between 1 and 1000
    someString: "Valid string with good length", // Valid: between 1 and 100 chars
    email: "complete@example.com",
    slug: "complete-todo",
    version: "2.1.5",
    caseInsensitiveCode: "XYZ-9999",
    autoComplete: true,
    tags: ["work", "urgent"],
  };

  const validated = createOrgTodoZodSchema.parse(validData);
  console.log("All constraints passed:", {
    employees: validated.numberOfEmployees,
    stringLength: validated.someString.length,
  });
  return validated;
}

// Test 10: Safe parsing with valid constraints
export function testSafeParsingWithConstraints() {
  const validData = {
    ...createValidBaseData(),
    numberOfEmployees: 50,
  };

  const result = createOrgTodoZodSchema.safeParse(validData);

  if (result.success) {
    console.log("Safe parse succeeded with constraints:", result.data);
    return result.data;
  } else {
    throw new Error("Unexpected validation failure");
  }
}

// Test 11: Type inference with constraints
export type CreateOrgTodoInput = z.infer<typeof createOrgTodoZodSchema>;

export function validateWithConstraints(input: unknown): CreateOrgTodoInput {
  return createOrgTodoZodSchema.parse(input);
}

// Test 12: Constraint validation in function context
export function createOrgTodoWithValidation(data: CreateOrgTodoInput) {
  // If this compiles, the constraints are in the type system
  const employees: number = data.numberOfEmployees;
  const str: string = data.someString;

  return { employees, str };
}

// Test 13: Optional fields with constraints still validate when present
export function testOptionalConstrainedField() {
  // If a field is optional but has constraints, those constraints
  // should still apply when the field is present
  const validData = {
    ...createValidBaseData(),
    numberOfEmployees: 100, // Valid when present
    slug: "test-slug-123",
    version: "1.2.3",
    // Optional fields can be omitted or included with valid values
    description: "Valid description",
  };

  const validated = createOrgTodoZodSchema.parse(validData);
  return validated;
}

// Test 14: Valid email addresses
export function testValidEmails() {
  const validEmails = [
    "user@example.com",
    "test.user@example.com",
    "test+tag@example.co.uk",
    "user_name@example-domain.com",
  ];

  for (const email of validEmails) {
    const validData = { ...createValidBaseData(), email };
    createOrgTodoZodSchema.parse(validData);
  }

  console.log("All valid emails passed!");
  return true;
}

// Test 15: Valid phone numbers
export function testValidPhoneNumbers() {
  const validPhones = [
    "+15551234567",
    "+442071234567",
    "+861234567890",
    "15551234567", // Without + is valid
  ];

  for (const phone of validPhones) {
    const validData = { ...createValidBaseData(), phoneNumber: phone };
    createOrgTodoZodSchema.parse(validData);
  }

  console.log("All valid phone numbers passed!");
  return true;
}

// Test 16: Valid hex colors
export function testValidHexColors() {
  const validColors = [
    "#000000",
    "#FFFFFF",
    "#FF5733",
    "#aAbBcC",
    "#123456",
  ];

  for (const color of validColors) {
    const validData = { ...createValidBaseData(), hexColor: color };
    createOrgTodoZodSchema.parse(validData);
  }

  console.log("All valid hex colors passed!");
  return true;
}

// Test 17: Valid slugs
export function testValidSlugs() {
  const validSlugs = [
    "test",
    "test-slug",
    "test-slug-123",
    "a-b-c-d-e",
    "123-456",
  ];

  for (const slug of validSlugs) {
    const validData = { ...createValidBaseData(), slug };
    createOrgTodoZodSchema.parse(validData);
  }

  console.log("All valid slugs passed!");
  return true;
}

// Test 18: Valid semantic versions
export function testValidVersions() {
  const validVersions = [
    "0.0.0",
    "1.0.0",
    "1.2.3",
    "10.20.30",
    "999.999.999",
  ];

  for (const version of validVersions) {
    const validData = { ...createValidBaseData(), version };
    createOrgTodoZodSchema.parse(validData);
  }

  console.log("All valid versions passed!");
  return true;
}

// Test 19: Case-insensitive codes (both upper and lower case should work)
export function testCaseInsensitiveCodes() {
  const validCodes = [
    "ABC-1234", // All uppercase
    "abc-1234", // All lowercase (should work due to /i flag)
    "AbC-5678", // Mixed case
    "XYZ-0000",
  ];

  for (const code of validCodes) {
    const validData = { ...createValidBaseData(), caseInsensitiveCode: code };
    createOrgTodoZodSchema.parse(validData);
  }

  console.log("All case-insensitive codes passed!");
  return true;
}

// Test 20: Optional URL field can be omitted
export function testOptionalUrlOmitted() {
  const validData = createValidBaseData();
  // optionalUrl is not provided

  const validated = createOrgTodoZodSchema.parse(validData);
  console.log("Optional URL field successfully omitted");
  return validated;
}

// Test 21: Optional URL field with valid value
export function testOptionalUrlProvided() {
  const validUrls = [
    "https://example.com",
    "http://test.com",
    "https://example.com/path/to/resource",
    "http://localhost:3000",
  ];

  for (const url of validUrls) {
    const validData = { ...createValidBaseData(), optionalUrl: url };
    createOrgTodoZodSchema.parse(validData);
  }

  console.log("All optional URLs passed!");
  return true;
}

// Test 22: Valid float constraints - price within range
export function testFloatPriceValid() {
  const validPrices = [
    0.0,        // Minimum
    0.01,       // Just above minimum
    100.50,     // Mid-range
    999999.99,  // Maximum
  ];

  for (const price of validPrices) {
    const validData = { ...createValidBaseData(), price };
    createOrgTodoZodSchema.parse(validData);
  }

  console.log("All valid prices passed!");
  return true;
}

// Test 23: Valid float constraints - temperature with gt/lt
export function testFloatTemperatureValid() {
  const validTemperatures = [
    -273.14,    // Just above greater_than: -273.15
    0.0,        // Zero
    100.0,      // Positive
    999999.99,  // Just below less_than: 1000000.0
  ];

  for (const temperature of validTemperatures) {
    const validData = { ...createValidBaseData(), temperature };
    createOrgTodoZodSchema.parse(validData);
  }

  console.log("All valid temperatures passed!");
  return true;
}

// Test 24: Valid float constraints - percentage 0-100
export function testFloatPercentageValid() {
  const validPercentages = [
    0.0,    // Minimum
    0.5,    // Small decimal
    50.0,   // Middle
    99.99,  // Near maximum
    100.0,  // Maximum
  ];

  for (const percentage of validPercentages) {
    const validData = { ...createValidBaseData(), percentage };
    createOrgTodoZodSchema.parse(validData);
  }

  console.log("All valid percentages passed!");
  return true;
}

// Test 25: Optional float field - can be omitted
export function testOptionalFloatOmitted() {
  const validData = createValidBaseData();
  // optionalRating is not provided
  const validated = createOrgTodoZodSchema.parse(validData);
  console.log("Optional rating successfully omitted");
  return validated;
}

// Test 26: Optional float field - valid when provided
export function testOptionalFloatProvided() {
  const validRatings = [
    0.0,   // Minimum
    2.5,   // Middle
    4.99,  // Near maximum
    5.0,   // Maximum
  ];

  for (const rating of validRatings) {
    const validData = { ...createValidBaseData(), optionalRating: rating };
    createOrgTodoZodSchema.parse(validData);
  }

  console.log("All optional ratings passed!");
  return true;
}

// Test 27: Float precision is preserved
export function testFloatPrecision() {
  const testCases = [
    { price: 19.99 },
    { price: 123.456 },
    { temperature: -100.123 },
    { percentage: 33.333 },
  ];

  for (const testCase of testCases) {
    const validData = { ...createValidBaseData(), ...testCase };
    const validated = createOrgTodoZodSchema.parse(validData);
    // Zod preserves the float values
    if ('price' in testCase) {
      console.log(`Price precision: ${validated.price}`);
    }
  }

  console.log("Float precision preserved!");
  return true;
}

// Test 28: CiString constraints - username length
export function testCiStringUsernameValid() {
  const validUsernames = [
    "abc",        // Minimum length (3)
    "testuser",   // Mid-range
    "a".repeat(20), // Maximum length (20)
  ];

  for (const username of validUsernames) {
    const validData = { ...createValidBaseData(), username };
    createOrgTodoZodSchema.parse(validData);
  }

  console.log("All valid usernames passed!");
  return true;
}

// Test 29: CiString with regex - company name
export function testCiStringCompanyNameValid() {
  const validCompanyNames = [
    "AB",              // Minimum length (2)
    "Acme Corp",       // Alphanumeric with space
    "Test Company 123", // With numbers
    "A".repeat(100),   // Maximum length (100)
  ];

  for (const companyName of validCompanyNames) {
    const validData = { ...createValidBaseData(), companyName };
    createOrgTodoZodSchema.parse(validData);
  }

  console.log("All valid company names passed!");
  return true;
}

// Test 30: CiString with case-insensitive regex - country code
export function testCiStringCountryCodeValid() {
  const validCountryCodes = [
    "US",  // Uppercase
    "uk",  // Lowercase (should work due to /i flag)
    "Ca",  // Mixed case
    "FR",  // Another uppercase
  ];

  for (const countryCode of validCountryCodes) {
    const validData = { ...createValidBaseData(), countryCode };
    createOrgTodoZodSchema.parse(validData);
  }

  console.log("All valid country codes passed!");
  return true;
}

// Test 31: Optional CiString - can be omitted
export function testOptionalCiStringOmitted() {
  const validData = createValidBaseData();
  // optionalNickname is not provided
  const validated = createOrgTodoZodSchema.parse(validData);
  console.log("Optional nickname successfully omitted");
  return validated;
}

// Test 32: Optional CiString - valid when provided
export function testOptionalCiStringProvided() {
  const validNicknames = [
    "ab",           // Minimum length (2)
    "Johnny",       // Mid-range
    "a".repeat(15), // Maximum length (15)
  ];

  for (const nickname of validNicknames) {
    const validData = { ...createValidBaseData(), optionalNickname: nickname };
    createOrgTodoZodSchema.parse(validData);
  }

  console.log("All optional nicknames passed!");
  return true;
}

// Test 33: CiString case variations (all should be accepted)
export function testCiStringCaseVariations() {
  const testCases = [
    { username: "TestUser", companyName: "ACME CORP", countryCode: "us" },
    { username: "TESTUSER", companyName: "acme corp", countryCode: "US" },
    { username: "testuser", companyName: "Acme Corp", countryCode: "Us" },
  ];

  for (const testCase of testCases) {
    const validData = { ...createValidBaseData(), ...testCase };
    createOrgTodoZodSchema.parse(validData);
  }

  console.log("All case variations passed!");
  return true;
}

console.log("Constraint validation tests should compile and pass successfully!");
