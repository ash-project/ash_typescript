// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

import * as v from "valibot";
import {
  createOrgTodoValibotSchema,
  createTaskValibotSchema,
  AshTypescriptTestTodoContentLinkContentValibotSchema,
} from "../../ash_valibot";

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

export function testIntegerMinConstraint() {
  const validData = {
    ...createValidBaseData(),
    numberOfEmployees: 1, // Exactly at minimum (min: 1)
  };

  const validated = v.parse(createOrgTodoValibotSchema, validData);
  console.log("Integer min constraint passed:", validated.numberOfEmployees);
  return validated;
}

export function testIntegerMaxConstraint() {
  const validData = {
    ...createValidBaseData(),
    numberOfEmployees: 1000, // Exactly at maximum (max: 1000)
  };

  const validated = v.parse(createOrgTodoValibotSchema, validData);
  console.log("Integer max constraint passed:", validated.numberOfEmployees);
  return validated;
}

export function testIntegerMidRangeConstraint() {
  const validData = {
    ...createValidBaseData(),
    numberOfEmployees: 500, // Mid-range value
  };

  const validated = v.parse(createOrgTodoValibotSchema, validData);
  return validated;
}

export function testStringMinLengthConstraint() {
  const validData = {
    ...createValidBaseData(),
    someString: "a", // Exactly at minimum (min_length: 1)
  };

  const validated = v.parse(createOrgTodoValibotSchema, validData);
  console.log("String min length constraint passed:", validated.someString);
  return validated;
}

export function testStringMaxLengthConstraint() {
  const validData = {
    ...createValidBaseData(),
    someString: "a".repeat(100), // Exactly at maximum (max_length: 100)
  };

  const validated = v.parse(createOrgTodoValibotSchema, validData);
  console.log("String max length constraint passed, length:", validated.someString.length);
  return validated;
}

export function testStringMidRangeLengthConstraint() {
  const validData = {
    ...createValidBaseData(),
    someString: "This is a valid string with moderate length",
  };

  const validated = v.parse(createOrgTodoValibotSchema, validData);
  return validated;
}

export function testRegexConstraintValid() {
  const validData = {
    url: "https://example.com", // Matches ^https?://
    title: "Example link",
  };

  const validated = v.parse(AshTypescriptTestTodoContentLinkContentValibotSchema, validData);
  console.log("Regex constraint passed:", validated.url);
  return validated;
}

export function testRegexConstraintHttpUrl() {
  const validData = {
    url: "http://example.com", // Also matches ^https?://
    title: "Example link",
  };

  const validated = v.parse(AshTypescriptTestTodoContentLinkContentValibotSchema, validData);
  return validated;
}

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

  const validated = v.parse(createOrgTodoValibotSchema, validData);
  console.log("All constraints passed:", {
    employees: validated.numberOfEmployees,
    stringLength: validated.someString.length,
  });
  return validated;
}

export function testSafeParsingWithConstraints() {
  const validData = {
    ...createValidBaseData(),
    numberOfEmployees: 50,
  };

  const result = v.safeParse(createOrgTodoValibotSchema, validData);

  if (result.success) {
    console.log("Safe parse succeeded with constraints:", result.output);
    return result.output;
  } else {
    throw new Error("Unexpected validation failure");
  }
}

export function testOptionalConstrainedField() {
  const validData = {
    ...createValidBaseData(),
    numberOfEmployees: 100, // Valid when present
    slug: "test-slug-123",
    version: "1.2.3",
    description: "Valid description",
  };

  const validated = v.parse(createOrgTodoValibotSchema, validData);
  return validated;
}

export function testValidEmails() {
  const validEmails = [
    "user@example.com",
    "test.user@example.com",
    "test+tag@example.co.uk",
    "user_name@example-domain.com",
  ];

  for (const email of validEmails) {
    const validData = { ...createValidBaseData(), email };
    v.parse(createOrgTodoValibotSchema, validData);
  }

  console.log("All valid emails passed!");
  return true;
}

export function testValidPhoneNumbers() {
  const validPhones = [
    "+15551234567",
    "+442071234567",
    "+861234567890",
    "15551234567", // Without + is valid
  ];

  for (const phone of validPhones) {
    const validData = { ...createValidBaseData(), phoneNumber: phone };
    v.parse(createOrgTodoValibotSchema, validData);
  }

  console.log("All valid phone numbers passed!");
  return true;
}

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
    v.parse(createOrgTodoValibotSchema, validData);
  }

  console.log("All valid hex colors passed!");
  return true;
}

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
    v.parse(createOrgTodoValibotSchema, validData);
  }

  console.log("All valid slugs passed!");
  return true;
}

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
    v.parse(createOrgTodoValibotSchema, validData);
  }

  console.log("All valid versions passed!");
  return true;
}

export function testCaseInsensitiveCodes() {
  const validCodes = [
    "ABC-1234",
    "abc-1234",
    "AbC-5678",
    "XYZ-0000",
  ];

  for (const code of validCodes) {
    const validData = { ...createValidBaseData(), caseInsensitiveCode: code };
    v.parse(createOrgTodoValibotSchema, validData);
  }

  console.log("All case-insensitive codes passed!");
  return true;
}

export function testOptionalUrlOmitted() {
  const validData = createValidBaseData();

  const validated = v.parse(createOrgTodoValibotSchema, validData);
  console.log("Optional URL field successfully omitted");
  return validated;
}

export function testOptionalUrlProvided() {
  const validUrls = [
    "https://example.com",
    "http://test.com",
    "https://example.com/path/to/resource",
    "http://localhost:3000",
  ];

  for (const url of validUrls) {
    const validData = { ...createValidBaseData(), optionalUrl: url };
    v.parse(createOrgTodoValibotSchema, validData);
  }

  console.log("All optional URLs passed!");
  return true;
}

export function testFloatPriceValid() {
  const validPrices = [
    0.0,
    0.01,
    100.50,
    999999.99,
  ];

  for (const price of validPrices) {
    const validData = { ...createValidBaseData(), price };
    v.parse(createOrgTodoValibotSchema, validData);
  }

  console.log("All valid prices passed!");
  return true;
}

export function testFloatTemperatureValid() {
  const validTemperatures = [
    -273.14,
    0.0,
    100.0,
    999999.99,
  ];

  for (const temperature of validTemperatures) {
    const validData = { ...createValidBaseData(), temperature };
    v.parse(createOrgTodoValibotSchema, validData);
  }

  console.log("All valid temperatures passed!");
  return true;
}

export function testFloatPercentageValid() {
  const validPercentages = [
    0.0,
    0.5,
    50.0,
    99.99,
    100.0,
  ];

  for (const percentage of validPercentages) {
    const validData = { ...createValidBaseData(), percentage };
    v.parse(createOrgTodoValibotSchema, validData);
  }

  console.log("All valid percentages passed!");
  return true;
}

export function testOptionalFloatOmitted() {
  const validData = createValidBaseData();
  const validated = v.parse(createOrgTodoValibotSchema, validData);
  console.log("Optional rating successfully omitted");
  return validated;
}

export function testOptionalFloatProvided() {
  const validRatings = [
    0.0,
    2.5,
    4.99,
    5.0,
  ];

  for (const rating of validRatings) {
    const validData = { ...createValidBaseData(), optionalRating: rating };
    v.parse(createOrgTodoValibotSchema, validData);
  }

  console.log("All optional ratings passed!");
  return true;
}

export function testFloatPrecision() {
  const testCases = [
    { price: 19.99 },
    { price: 123.456 },
    { temperature: -100.123 },
    { percentage: 33.333 },
  ];

  for (const testCase of testCases) {
    const validData = { ...createValidBaseData(), ...testCase };
    const validated = v.parse(createOrgTodoValibotSchema, validData);
    if ('price' in testCase) {
      console.log(`Price precision: ${validated.price}`);
    }
  }

  console.log("Float precision preserved!");
  return true;
}

export function testCiStringUsernameValid() {
  const validUsernames = [
    "abc",
    "testuser",
    "a".repeat(20),
  ];

  for (const username of validUsernames) {
    const validData = { ...createValidBaseData(), username };
    v.parse(createOrgTodoValibotSchema, validData);
  }

  console.log("All valid usernames passed!");
  return true;
}

export function testCiStringCompanyNameValid() {
  const validCompanyNames = [
    "AB",
    "Acme Corp",
    "Test Company 123",
    "A".repeat(100),
  ];

  for (const companyName of validCompanyNames) {
    const validData = { ...createValidBaseData(), companyName };
    v.parse(createOrgTodoValibotSchema, validData);
  }

  console.log("All valid company names passed!");
  return true;
}

export function testCiStringCountryCodeValid() {
  const validCountryCodes = [
    "US",
    "uk",
    "Ca",
    "FR",
  ];

  for (const countryCode of validCountryCodes) {
    const validData = { ...createValidBaseData(), countryCode };
    v.parse(createOrgTodoValibotSchema, validData);
  }

  console.log("All valid country codes passed!");
  return true;
}

export function testOptionalCiStringOmitted() {
  const validData = createValidBaseData();
  const validated = v.parse(createOrgTodoValibotSchema, validData);
  console.log("Optional nickname successfully omitted");
  return validated;
}

export function testOptionalCiStringProvided() {
  const validNicknames = [
    "ab",
    "Johnny",
    "a".repeat(15),
  ];

  for (const nickname of validNicknames) {
    const validData = { ...createValidBaseData(), optionalNickname: nickname };
    v.parse(createOrgTodoValibotSchema, validData);
  }

  console.log("All optional nicknames passed!");
  return true;
}

export function testCiStringCaseVariations() {
  const testCases = [
    { username: "TestUser", companyName: "ACME CORP", countryCode: "us" },
    { username: "TESTUSER", companyName: "acme corp", countryCode: "US" },
    { username: "testuser", companyName: "Acme Corp", countryCode: "Us" },
  ];

  for (const testCase of testCases) {
    const validData = { ...createValidBaseData(), ...testCase };
    v.parse(createOrgTodoValibotSchema, validData);
  }

  console.log("All case variations passed!");
  return true;
}

// Third-party type: AshMoney.Types.Money
// Expected validation shape: { amount: string; currency: string }

export function testMoneyValidShape() {
  const validated = v.parse(createTaskValibotSchema, {
    title: "Buy milk",
    price: { amount: "4.99", currency: "USD" },
  });
  console.log("Money valid shape passed:", validated.price);
  return validated;
}

export function testMoneyOptionalOmitted() {
  const validated = v.parse(createTaskValibotSchema, { title: "Priceless" });
  console.log("Money optional omitted passed:", validated.price);
  return validated;
}

console.log("Valibot Constraint validation tests should compile and pass successfully!");
