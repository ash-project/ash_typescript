// Test file for keyword and tuple type handling in generated TypeScript
import { listTodos } from "../generated";

async function testKeywordTupleFieldSelection() {
  console.log("Testing keyword and tuple field selection...");

  try {
    // Test 1: Try to request keyword field without field selection - should fail
    try {
      await listTodos({
        input: {},
        fields: ["id", "title", { options: ["category"] }],
      });
      console.log(
        "ERROR: Should have failed without field selection for options",
      );
    } catch (error) {
      console.log("Expected error for options without field selection:", error);
    }

    // Test 2: Try to request tuple field without field selection - should fail
    try {
      await listTodos({
        input: {},
        fields: ["id", "title", { coordinates: ["latitude", "longitude"] }],
      });
      console.log(
        "ERROR: Should have failed without field selection for coordinates",
      );
    } catch (error) {
      console.log(
        "Expected error for coordinates without field selection:",
        error,
      );
    }

    // Test 3: Try with field selection for keyword type
    try {
      const todosWithOptions = await listTodos({
        input: {},
        fields: [
          "id",
          "title",
          {
            options: ["priority", "category", "notify"],
          },
        ],
      });
      console.log("Success with keyword field selection:", todosWithOptions);
    } catch (error) {
      console.log("Error with keyword field selection:", error);
    }

    // Test 4: Try with field selection for tuple type
    try {
      const todosWithCoordinates = await listTodos({
        input: {},
        fields: [
          "id",
          "title",
          {
            coordinates: ["latitude", "longitude"],
          },
        ],
      });
      console.log("Success with tuple field selection:", todosWithCoordinates);
    } catch (error) {
      console.log("Error with tuple field selection:", error);
    }

    // Test 5: Try with partial field selection for keyword type
    try {
      const todosWithPartialOptions = await listTodos({
        input: {},
        fields: [
          "id",
          "title",
          {
            options: ["priority", "category"], // Only some fields
          },
        ],
      });
      console.log(
        "Success with partial keyword field selection:",
        todosWithPartialOptions,
      );
    } catch (error) {
      console.log("Error with partial keyword field selection:", error);
    }
  } catch (error) {
    console.error("Unexpected error:", error);
  }
}

// Export for potential use
export { testKeywordTupleFieldSelection };
