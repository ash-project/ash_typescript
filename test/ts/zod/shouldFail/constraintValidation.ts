// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Constraint Validation Tests - shouldFail
// Tests that constraint validation properly rejects invalid values at runtime
// Note: These are runtime validation failures, not TypeScript compilation errors

import { z } from "zod";
import {
  createOrgTodoZodschema,
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

// Test 1: Integer constraint - below minimum (runtime failure)
export function testIntegerBelowMin() {
  const invalidData = {
    ...createValidBaseData(),
    numberOfEmployees: 0, // Below min: 1
  };

  try {
    createOrgTodoZodschema.parse(invalidData);
    throw new Error("Should have failed validation");
  } catch (error) {
    if (error instanceof z.ZodError) {
      console.log("Correctly rejected numberOfEmployees < 1:", error.issues);
      return error.issues;
    }
    throw error;
  }
}

// Test 2: Integer constraint - above maximum (runtime failure)
export function testIntegerAboveMax() {
  const invalidData = {
    ...createValidBaseData(),
    numberOfEmployees: 1001, // Above max: 1000
  };

  try {
    createOrgTodoZodschema.parse(invalidData);
    throw new Error("Should have failed validation");
  } catch (error) {
    if (error instanceof z.ZodError) {
      console.log("Correctly rejected numberOfEmployees > 1000:", error.issues);
      return error.issues;
    }
    throw error;
  }
}

// Test 3: Integer constraint - negative value (runtime failure)
export function testIntegerNegative() {
  const invalidData = {
    ...createValidBaseData(),
    numberOfEmployees: -10, // Negative, below min: 1
  };

  try {
    createOrgTodoZodschema.parse(invalidData);
    throw new Error("Should have failed validation");
  } catch (error) {
    if (error instanceof z.ZodError) {
      console.log("Correctly rejected negative numberOfEmployees:", error.issues);
      return error.issues;
    }
    throw error;
  }
}

// Test 4: String constraint - empty string (runtime failure)
export function testStringEmpty() {
  const invalidData = {
    ...createValidBaseData(),
    someString: "", // Below min_length: 1
  };

  try {
    createOrgTodoZodschema.parse(invalidData);
    throw new Error("Should have failed validation");
  } catch (error) {
    if (error instanceof z.ZodError) {
      console.log("Correctly rejected empty someString:", error.issues);
      return error.issues;
    }
    throw error;
  }
}

// Test 5: String constraint - too long (runtime failure)
export function testStringTooLong() {
  const invalidData = {
    ...createValidBaseData(),
    someString: "a".repeat(101), // Above max_length: 100
  };

  try {
    createOrgTodoZodschema.parse(invalidData);
    throw new Error("Should have failed validation");
  } catch (error) {
    if (error instanceof z.ZodError) {
      console.log("Correctly rejected someString > 100 chars:", error.issues);
      return error.issues;
    }
    throw error;
  }
}

// Test 6: String constraint - way too long (runtime failure)
export function testStringWayTooLong() {
  const invalidData = {
    ...createValidBaseData(),
    someString: "a".repeat(500), // Way above max_length: 100
  };

  try {
    createOrgTodoZodschema.parse(invalidData);
    throw new Error("Should have failed validation");
  } catch (error) {
    if (error instanceof z.ZodError) {
      console.log("Correctly rejected someString way over limit:", error.issues);
      return error.issues;
    }
    throw error;
  }
}

// Test 7: Regex constraint - invalid URL format (runtime failure)
export function testRegexInvalidUrl() {
  const invalidData = {
    url: "not-a-url", // Doesn't match ^https?://
    title: "Invalid link",
  };

  try {
    AshTypescriptTestTodoContentLinkContentZodSchema.parse(invalidData);
    throw new Error("Should have failed validation");
  } catch (error) {
    if (error instanceof z.ZodError) {
      console.log("Correctly rejected invalid URL format:", error.issues);
      return error.issues;
    }
    throw error;
  }
}

// Test 8: Regex constraint - FTP URL (runtime failure)
export function testRegexFtpUrl() {
  const invalidData = {
    url: "ftp://example.com", // Doesn't match ^https?:// (no ftp)
    title: "FTP link",
  };

  try {
    AshTypescriptTestTodoContentLinkContentZodSchema.parse(invalidData);
    throw new Error("Should have failed validation");
  } catch (error) {
    if (error instanceof z.ZodError) {
      console.log("Correctly rejected FTP URL:", error.issues);
      return error.issues;
    }
    throw error;
  }
}

// Test 9: Multiple constraint violations (runtime failure)
export function testMultipleConstraintViolations() {
  const invalidData = {
    ...createValidBaseData(),
    numberOfEmployees: 5000, // Above max: 1000
    someString: "", // Below min_length: 1
  };

  try {
    createOrgTodoZodschema.parse(invalidData);
    throw new Error("Should have failed validation");
  } catch (error) {
    if (error instanceof z.ZodError) {
      console.log("Correctly rejected multiple violations:", error.issues);
      // Should have errors for both numberOfEmployees and someString
      const hasEmployeeError = error.issues.some(e =>
        e.path.includes("numberOfEmployees")
      );
      const hasStringError = error.issues.some(e =>
        e.path.includes("someString")
      );

      if (hasEmployeeError && hasStringError) {
        console.log("Both constraint violations detected correctly");
      }
      return error.issues;
    }
    throw error;
  }
}

// Test 10: Safe parsing with constraint violations
export function testSafeParseConstraintViolation() {
  const invalidData = {
    ...createValidBaseData(),
    numberOfEmployees: 2000, // Above max: 1000
  };

  const result = createOrgTodoZodschema.safeParse(invalidData);

  if (!result.success) {
    console.log("Safe parse correctly failed:", result.error.issues);
    return result.error.issues;
  } else {
    throw new Error("Should have failed validation");
  }
}

// Test 11: Integer constraint - floating point (might pass int check but fail range)
export function testIntegerFloatingPoint() {
  const invalidData = {
    ...createValidBaseData(),
    numberOfEmployees: 10.5, // Float when integer expected
  };

  try {
    createOrgTodoZodschema.parse(invalidData);
    // Note: Zod .int() will fail on floating point numbers
    throw new Error("Should have failed validation");
  } catch (error) {
    if (error instanceof z.ZodError) {
      console.log("Correctly rejected floating point:", error.issues);
      return error.issues;
    }
    throw error;
  }
}

// Test 12: Boundary testing - just outside valid range
export function testBoundaryViolations() {
  const justBelowMin = {
    ...createValidBaseData(),
    numberOfEmployees: 0.99, // Just below 1
  };

  const justAboveMax = {
    ...createValidBaseData(),
    numberOfEmployees: 1000.01, // Just above 1000
  };

  const errors = [];

  try {
    createOrgTodoZodschema.parse(justBelowMin);
    throw new Error("Should have failed for below min");
  } catch (error) {
    if (error instanceof z.ZodError) {
      errors.push({ case: "below min", errors: error.issues });
    }
  }

  try {
    createOrgTodoZodschema.parse(justAboveMax);
    throw new Error("Should have failed for above max");
  } catch (error) {
    if (error instanceof z.ZodError) {
      errors.push({ case: "above max", errors: error.issues });
    }
  }

  console.log("Boundary violations detected:", errors);
  return errors;
}

// Test 13: Required field with constraint - missing value
export function testRequiredFieldMissing() {
  const { numberOfEmployees, ...invalidData } = createValidBaseData();
  // numberOfEmployees is missing (required)

  try {
    createOrgTodoZodschema.parse(invalidData);
    throw new Error("Should have failed validation");
  } catch (error) {
    if (error instanceof z.ZodError) {
      console.log("Correctly rejected missing required field:", error.issues);
      return error.issues;
    }
    throw error;
  }
}

// Test 14: Invalid email - missing @ symbol
export function testInvalidEmailNoAt() {
  const invalidData = {
    title: "Test",
    userId: "123e4567-e89b-12d3-a456-426614174000",
    numberOfEmployees: 10,
    someString: "valid",
    email: "notanemail.com", // Missing @
    phoneNumber: "+15551234567",
    hexColor: "#123456",
    slug: "test",
    version: "1.0.0",
    caseInsensitiveCode: "ABC-1234",
    autoComplete: false,
    address: { streetAddress: "123 Main St", locationId: "LOC123" },
  };

  try {
    createOrgTodoZodschema.parse(invalidData);
    throw new Error("Should have failed validation");
  } catch (error) {
    if (error instanceof z.ZodError) {
      console.log("Correctly rejected invalid email:", error.issues);
      return error.issues;
    }
    throw error;
  }
}

// Test 15: Invalid email - missing domain extension
export function testInvalidEmailNoDomain() {
  const invalidData = {
    title: "Test",
    userId: "123e4567-e89b-12d3-a456-426614174000",
    numberOfEmployees: 10,
    someString: "valid",
    email: "user@example", // Missing .com or similar
    phoneNumber: "+15551234567",
    hexColor: "#123456",
    slug: "test",
    version: "1.0.0",
    caseInsensitiveCode: "ABC-1234",
    autoComplete: false,
    address: { streetAddress: "123 Main St", locationId: "LOC123" },
  };

  try {
    createOrgTodoZodschema.parse(invalidData);
    throw new Error("Should have failed validation");
  } catch (error) {
    if (error instanceof z.ZodError) {
      console.log("Correctly rejected email without domain extension:", error.issues);
      return error.issues;
    }
    throw error;
  }
}

// Test 16: Invalid phone - starts with 0
export function testInvalidPhoneStartsWithZero() {
  const invalidData = {
    title: "Test",
    userId: "123e4567-e89b-12d3-a456-426614174000",
    numberOfEmployees: 10,
    someString: "valid",
    email: "test@example.com",
    phoneNumber: "+05551234567", // Starts with 0 after +
    hexColor: "#123456",
    slug: "test",
    version: "1.0.0",
    caseInsensitiveCode: "ABC-1234",
    autoComplete: false,
    address: { streetAddress: "123 Main St", locationId: "LOC123" },
  };

  try {
    createOrgTodoZodschema.parse(invalidData);
    throw new Error("Should have failed validation");
  } catch (error) {
    if (error instanceof z.ZodError) {
      console.log("Correctly rejected phone starting with 0:", error.issues);
      return error.issues;
    }
    throw error;
  }
}

// Test 17: Invalid phone - too short
export function testInvalidPhoneTooShort() {
  const invalidData = {
    title: "Test",
    userId: "123e4567-e89b-12d3-a456-426614174000",
    numberOfEmployees: 10,
    someString: "valid",
    email: "test@example.com",
    phoneNumber: "+1", // Too short (needs at least 2 digits after country code)
    hexColor: "#123456",
    slug: "test",
    version: "1.0.0",
    caseInsensitiveCode: "ABC-1234",
    autoComplete: false,
    address: { streetAddress: "123 Main St", locationId: "LOC123" },
  };

  try {
    createOrgTodoZodschema.parse(invalidData);
    throw new Error("Should have failed validation");
  } catch (error) {
    if (error instanceof z.ZodError) {
      console.log("Correctly rejected phone too short:", error.issues);
      return error.issues;
    }
    throw error;
  }
}

// Test 18: Invalid hex color - wrong length
export function testInvalidHexColorLength() {
  const invalidData = {
    title: "Test",
    userId: "123e4567-e89b-12d3-a456-426614174000",
    numberOfEmployees: 10,
    someString: "valid",
    email: "test@example.com",
    phoneNumber: "+15551234567",
    hexColor: "#FFF", // Only 3 characters, needs 6
    slug: "test",
    version: "1.0.0",
    caseInsensitiveCode: "ABC-1234",
    autoComplete: false,
    address: { streetAddress: "123 Main St", locationId: "LOC123" },
  };

  try {
    createOrgTodoZodschema.parse(invalidData);
    throw new Error("Should have failed validation");
  } catch (error) {
    if (error instanceof z.ZodError) {
      console.log("Correctly rejected hex color with wrong length:", error.issues);
      return error.issues;
    }
    throw error;
  }
}

// Test 19: Invalid hex color - missing #
export function testInvalidHexColorNoHash() {
  const invalidData = {
    title: "Test",
    userId: "123e4567-e89b-12d3-a456-426614174000",
    numberOfEmployees: 10,
    someString: "valid",
    email: "test@example.com",
    phoneNumber: "+15551234567",
    hexColor: "FF5733", // Missing #
    slug: "test",
    version: "1.0.0",
    caseInsensitiveCode: "ABC-1234",
    autoComplete: false,
    address: { streetAddress: "123 Main St", locationId: "LOC123" },
  };

  try {
    createOrgTodoZodschema.parse(invalidData);
    throw new Error("Should have failed validation");
  } catch (error) {
    if (error instanceof z.ZodError) {
      console.log("Correctly rejected hex color without #:", error.issues);
      return error.issues;
    }
    throw error;
  }
}

// Test 20: Invalid slug - contains uppercase
export function testInvalidSlugUppercase() {
  const invalidData = {
    title: "Test",
    userId: "123e4567-e89b-12d3-a456-426614174000",
    numberOfEmployees: 10,
    someString: "valid",
    email: "test@example.com",
    phoneNumber: "+15551234567",
    hexColor: "#123456",
    slug: "Test-Slug", // Contains uppercase (only lowercase allowed)
    version: "1.0.0",
    caseInsensitiveCode: "ABC-1234",
    autoComplete: false,
    address: { streetAddress: "123 Main St", locationId: "LOC123" },
  };

  try {
    createOrgTodoZodschema.parse(invalidData);
    throw new Error("Should have failed validation");
  } catch (error) {
    if (error instanceof z.ZodError) {
      console.log("Correctly rejected slug with uppercase:", error.issues);
      return error.issues;
    }
    throw error;
  }
}

// Test 21: Invalid slug - starts with hyphen
export function testInvalidSlugStartsWithHyphen() {
  const invalidData = {
    title: "Test",
    userId: "123e4567-e89b-12d3-a456-426614174000",
    numberOfEmployees: 10,
    someString: "valid",
    email: "test@example.com",
    phoneNumber: "+15551234567",
    hexColor: "#123456",
    slug: "-test-slug", // Cannot start with hyphen
    version: "1.0.0",
    caseInsensitiveCode: "ABC-1234",
    autoComplete: false,
    address: { streetAddress: "123 Main St", locationId: "LOC123" },
  };

  try {
    createOrgTodoZodschema.parse(invalidData);
    throw new Error("Should have failed validation");
  } catch (error) {
    if (error instanceof z.ZodError) {
      console.log("Correctly rejected slug starting with hyphen:", error.issues);
      return error.issues;
    }
    throw error;
  }
}

// Test 22: Invalid version - missing patch number
export function testInvalidVersionMissingPatch() {
  const invalidData = {
    title: "Test",
    userId: "123e4567-e89b-12d3-a456-426614174000",
    numberOfEmployees: 10,
    someString: "valid",
    email: "test@example.com",
    phoneNumber: "+15551234567",
    hexColor: "#123456",
    slug: "test",
    version: "1.0", // Missing patch version (needs X.Y.Z)
    caseInsensitiveCode: "ABC-1234",
    autoComplete: false,
    address: { streetAddress: "123 Main St", locationId: "LOC123" },
  };

  try {
    createOrgTodoZodschema.parse(invalidData);
    throw new Error("Should have failed validation");
  } catch (error) {
    if (error instanceof z.ZodError) {
      console.log("Correctly rejected version missing patch:", error.issues);
      return error.issues;
    }
    throw error;
  }
}

// Test 23: Invalid version - contains letters
export function testInvalidVersionWithLetters() {
  const invalidData = {
    title: "Test",
    userId: "123e4567-e89b-12d3-a456-426614174000",
    numberOfEmployees: 10,
    someString: "valid",
    email: "test@example.com",
    phoneNumber: "+15551234567",
    hexColor: "#123456",
    slug: "test",
    version: "1.0.0-beta", // Contains non-numeric characters
    caseInsensitiveCode: "ABC-1234",
    autoComplete: false,
    address: { streetAddress: "123 Main St", locationId: "LOC123" },
  };

  try {
    createOrgTodoZodschema.parse(invalidData);
    throw new Error("Should have failed validation");
  } catch (error) {
    if (error instanceof z.ZodError) {
      console.log("Correctly rejected version with letters:", error.issues);
      return error.issues;
    }
    throw error;
  }
}

// Test 24: Invalid case-insensitive code - wrong format
export function testInvalidCodeWrongFormat() {
  const invalidData = {
    title: "Test",
    userId: "123e4567-e89b-12d3-a456-426614174000",
    numberOfEmployees: 10,
    someString: "valid",
    email: "test@example.com",
    phoneNumber: "+15551234567",
    hexColor: "#123456",
    slug: "test",
    version: "1.0.0",
    caseInsensitiveCode: "AB-1234", // Only 2 letters instead of 3
    autoComplete: false,
    address: { streetAddress: "123 Main St", locationId: "LOC123" },
  };

  try {
    createOrgTodoZodschema.parse(invalidData);
    throw new Error("Should have failed validation");
  } catch (error) {
    if (error instanceof z.ZodError) {
      console.log("Correctly rejected code with wrong format:", error.issues);
      return error.issues;
    }
    throw error;
  }
}

// Test 25: Invalid optional URL - wrong protocol
export function testInvalidOptionalUrlWrongProtocol() {
  const invalidData = {
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
    autoComplete: false,
    address: { streetAddress: "123 Main St", locationId: "LOC123" },
    optionalUrl: "ftp://example.com", // Wrong protocol
  };

  try {
    createOrgTodoZodschema.parse(invalidData);
    throw new Error("Should have failed validation");
  } catch (error) {
    if (error instanceof z.ZodError) {
      console.log("Correctly rejected URL with wrong protocol:", error.issues);
      return error.issues;
    }
    throw error;
  }
}

// Test 26: Float constraint - price below minimum
export function testFloatPriceBelowMin() {
  const invalidData = { ...createValidBaseData(), price: -0.01 }; // Below min: 0.0

  try {
    createOrgTodoZodschema.parse(invalidData);
    throw new Error("Should have failed validation");
  } catch (error) {
    if (error instanceof z.ZodError) {
      console.log("Correctly rejected price below minimum:", error.issues);
      return error.issues;
    }
    throw error;
  }
}

// Test 27: Float constraint - price above maximum
export function testFloatPriceAboveMax() {
  const invalidData = { ...createValidBaseData(), price: 1000000.00 }; // Above max: 999999.99

  try {
    createOrgTodoZodschema.parse(invalidData);
    throw new Error("Should have failed validation");
  } catch (error) {
    if (error instanceof z.ZodError) {
      console.log("Correctly rejected price above maximum:", error.issues);
      return error.issues;
    }
    throw error;
  }
}

// Test 28: Float constraint - temperature at exclusive boundary (gt)
export function testFloatTemperatureAtGtBoundary() {
  const invalidData = { ...createValidBaseData(), temperature: -273.15 }; // At greater_than boundary (exclusive)

  try {
    createOrgTodoZodschema.parse(invalidData);
    throw new Error("Should have failed validation");
  } catch (error) {
    if (error instanceof z.ZodError) {
      console.log("Correctly rejected temperature at gt boundary:", error.issues);
      return error.issues;
    }
    throw error;
  }
}

// Test 29: Float constraint - temperature at exclusive boundary (lt)
export function testFloatTemperatureAtLtBoundary() {
  const invalidData = { ...createValidBaseData(), temperature: 1000000.0 }; // At less_than boundary (exclusive)

  try {
    createOrgTodoZodschema.parse(invalidData);
    throw new Error("Should have failed validation");
  } catch (error) {
    if (error instanceof z.ZodError) {
      console.log("Correctly rejected temperature at lt boundary:", error.issues);
      return error.issues;
    }
    throw error;
  }
}

// Test 30: Float constraint - percentage below minimum
export function testFloatPercentageBelowMin() {
  const invalidData = { ...createValidBaseData(), percentage: -0.1 }; // Below min: 0.0

  try {
    createOrgTodoZodschema.parse(invalidData);
    throw new Error("Should have failed validation");
  } catch (error) {
    if (error instanceof z.ZodError) {
      console.log("Correctly rejected percentage below minimum:", error.issues);
      return error.issues;
    }
    throw error;
  }
}

// Test 31: Float constraint - percentage above maximum
export function testFloatPercentageAboveMax() {
  const invalidData = { ...createValidBaseData(), percentage: 100.01 }; // Above max: 100.0

  try {
    createOrgTodoZodschema.parse(invalidData);
    throw new Error("Should have failed validation");
  } catch (error) {
    if (error instanceof z.ZodError) {
      console.log("Correctly rejected percentage above maximum:", error.issues);
      return error.issues;
    }
    throw error;
  }
}

// Test 32: Optional float - invalid when provided
export function testOptionalFloatInvalid() {
  const invalidData = { ...createValidBaseData(), optionalRating: 5.5 }; // Above max: 5.0

  try {
    createOrgTodoZodschema.parse(invalidData);
    throw new Error("Should have failed validation");
  } catch (error) {
    if (error instanceof z.ZodError) {
      console.log("Correctly rejected invalid optional rating:", error.issues);
      return error.issues;
    }
    throw error;
  }
}

// Test 33: Multiple float constraints violated
export function testMultipleFloatViolations() {
  const invalidData = {
    ...createValidBaseData(),
    price: -100.0,        // Below min
    temperature: -300.0,  // Below gt
    percentage: 150.0,    // Above max
  };

  try {
    createOrgTodoZodschema.parse(invalidData);
    throw new Error("Should have failed validation");
  } catch (error) {
    if (error instanceof z.ZodError) {
      console.log("Correctly rejected multiple float violations:", error.issues);
      const hasPriceError = error.issues.some(e => e.path.includes("price"));
      const hasTempError = error.issues.some(e => e.path.includes("temperature"));
      const hasPercentError = error.issues.some(e => e.path.includes("percentage"));

      if (hasPriceError && hasTempError && hasPercentError) {
        console.log("All three float constraint violations detected correctly");
      }
      return error.issues;
    }
    throw error;
  }
}

// Test 34: CiString constraint - username too short
export function testCiStringUsernameTooShort() {
  const invalidData = { ...createValidBaseData(), username: "ab" }; // Below min: 3

  try {
    createOrgTodoZodschema.parse(invalidData);
    throw new Error("Should have failed validation");
  } catch (error) {
    if (error instanceof z.ZodError) {
      console.log("Correctly rejected username too short:", error.issues);
      return error.issues;
    }
    throw error;
  }
}

// Test 35: CiString constraint - username too long
export function testCiStringUsernameTooLong() {
  const invalidData = { ...createValidBaseData(), username: "a".repeat(21) }; // Above max: 20

  try {
    createOrgTodoZodschema.parse(invalidData);
    throw new Error("Should have failed validation");
  } catch (error) {
    if (error instanceof z.ZodError) {
      console.log("Correctly rejected username too long:", error.issues);
      return error.issues;
    }
    throw error;
  }
}

// Test 36: CiString constraint - company name with invalid characters
export function testCiStringCompanyNameInvalidChars() {
  const invalidData = { ...createValidBaseData(), companyName: "Acme@Corp!" }; // Contains @ and !

  try {
    createOrgTodoZodschema.parse(invalidData);
    throw new Error("Should have failed validation");
  } catch (error) {
    if (error instanceof z.ZodError) {
      console.log("Correctly rejected company name with invalid chars:", error.issues);
      return error.issues;
    }
    throw error;
  }
}

// Test 37: CiString constraint - company name too short
export function testCiStringCompanyNameTooShort() {
  const invalidData = { ...createValidBaseData(), companyName: "A" }; // Below min: 2

  try {
    createOrgTodoZodschema.parse(invalidData);
    throw new Error("Should have failed validation");
  } catch (error) {
    if (error instanceof z.ZodError) {
      console.log("Correctly rejected company name too short:", error.issues);
      return error.issues;
    }
    throw error;
  }
}

// Test 38: CiString constraint - country code wrong length
export function testCiStringCountryCodeWrongLength() {
  const invalidData = { ...createValidBaseData(), countryCode: "USA" }; // 3 characters instead of 2

  try {
    createOrgTodoZodschema.parse(invalidData);
    throw new Error("Should have failed validation");
  } catch (error) {
    if (error instanceof z.ZodError) {
      console.log("Correctly rejected country code wrong length:", error.issues);
      return error.issues;
    }
    throw error;
  }
}

// Test 39: CiString constraint - country code with number
export function testCiStringCountryCodeWithNumber() {
  const invalidData = { ...createValidBaseData(), countryCode: "U1" }; // Contains number

  try {
    createOrgTodoZodschema.parse(invalidData);
    throw new Error("Should have failed validation");
  } catch (error) {
    if (error instanceof z.ZodError) {
      console.log("Correctly rejected country code with number:", error.issues);
      return error.issues;
    }
    throw error;
  }
}

// Test 40: Optional CiString - invalid when provided
export function testOptionalCiStringInvalid() {
  const invalidData = { ...createValidBaseData(), optionalNickname: "a" }; // Below min: 2

  try {
    createOrgTodoZodschema.parse(invalidData);
    throw new Error("Should have failed validation");
  } catch (error) {
    if (error instanceof z.ZodError) {
      console.log("Correctly rejected invalid optional nickname:", error.issues);
      return error.issues;
    }
    throw error;
  }
}

// Test 41: Multiple CiString constraints violated
export function testMultipleCiStringViolations() {
  const invalidData = {
    ...createValidBaseData(),
    username: "ab",           // Too short
    companyName: "A",         // Too short
    countryCode: "123",       // Invalid format
  };

  try {
    createOrgTodoZodschema.parse(invalidData);
    throw new Error("Should have failed validation");
  } catch (error) {
    if (error instanceof z.ZodError) {
      console.log("Correctly rejected multiple CiString violations:", error.issues);
      const hasUsernameError = error.issues.some(e => e.path.includes("username"));
      const hasCompanyError = error.issues.some(e => e.path.includes("companyName"));
      const hasCountryError = error.issues.some(e => e.path.includes("countryCode"));

      if (hasUsernameError && hasCompanyError && hasCountryError) {
        console.log("All three CiString constraint violations detected correctly");
      }
      return error.issues;
    }
    throw error;
  }
}

console.log("Constraint validation failure tests should compile successfully!");
console.log("These tests verify that constraints are enforced at runtime.");
