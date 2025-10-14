// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Test file to verify explicit validation error types work with actual generated discriminated union types
// This tests with the real CreateTodoInput structure from generated.ts

import type {
  CreateTodoInput,
  CreateTodoValidationErrors,
  UpdateTodoValidationErrors,
} from "../generated";

// Test that the generated error types work correctly
function testCreateTodoValidation() {
  // This should compile correctly - testing discriminated union error handling
  const createTodoErrors: CreateTodoValidationErrors = {
    title: ["Title is required", "Title too short"],
    description: ["Description too long"],
    status: ["Invalid status value"],
    priority: ["Priority must be one of: low, medium, high, urgent"],
    dueDate: ["Invalid date format"],
    tags: [["lol"]],

    // This is the key test - union type error handling
    content: {
      // Should allow errors for any variant of the discriminated union
      text: {
        text: ["Text content is required"],
        formatting: ["Invalid formatting option"],
      },
      checklist: {
        title: ["Checklist title is required"],
        items: [
          {
            text: ["Item cannot be empty"],
            completed: ["Invalid completed value"],
          },
        ],
      },
      link: {
        url: ["Invalid URL format"],
        title: ["Link title too long"],
      },
      note: ["Note exceeds maximum length"],
      priorityValue: ["Priority value must be between 1 and 10"],
    },

    // Test nested object validation
    timestampInfo: {
      createdBy: ["Creator name is required"],
      createdAt: ["Invalid timestamp format"],
      updatedBy: ["Updater name invalid"],
      updatedAt: ["Update timestamp invalid"],
    },

    // Test nested complex objects
    statistics: {
      viewCount: ["View count must be non-negative"],
      editCount: ["Edit count must be non-negative"],
      completionTimeSeconds: ["Completion time must be positive"],
      difficultyRating: ["Difficulty rating must be between 1-5"],
      performanceMetrics: {
        focusTimeSeconds: ["Focus time must be positive"],
        interruptionCount: ["Interruption count must be non-negative"],
        efficiencyScore: ["Efficiency score must be between 0-1"],
        taskComplexity: ["Invalid complexity level"],
      },
    },

    userId: ["Invalid UUID format"],
  };

  return createTodoErrors;
}

function testUpdateTodoValidation() {
  const updateTodoErrors: UpdateTodoValidationErrors = {
    title: ["Title cannot be empty"],
    completed: ["Invalid boolean value"],

    // Test the same union handling for update
    content: {
      text: {
        text: ["Text content required"],
      },
      note: ["Note too short"],
    },
  };

  return updateTodoErrors;
}

// Test that we can create proper validation functions
function validateCreateTodoInput(
  input: CreateTodoInput,
): CreateTodoValidationErrors | null {
  const errors: CreateTodoValidationErrors = {};

  // Basic field validation
  if (!input.title?.trim()) {
    errors.title = ["Title is required"];
  }

  // Array validation
  if (input.tags?.some((tag) => !tag.trim())) {
    const tagErrors: string[][] = [];
    input.tags.forEach((tag, index) => {
      if (!tag.trim()) {
        tagErrors[index] = ["Tag cannot be empty"];
      }
    });
    errors.tags = tagErrors;
  }

  // Union validation - this is the key test
  if (input.content) {
    const contentErrors: NonNullable<CreateTodoValidationErrors["content"]> =
      {};

    if ("text" in input.content) {
      if (!input.content.text.text?.trim()) {
        contentErrors.text = {
          text: ["Text content is required"],
        };
      }
    }

    if ("note" in input.content) {
      if (input.content.note.length > 1000) {
        contentErrors.note = ["Note exceeds 1000 characters"];
      }
    }

    if ("priorityValue" in input.content) {
      if (input.content.priorityValue < 1 || input.content.priorityValue > 10) {
        contentErrors.priorityValue = ["Priority must be between 1 and 10"];
      }
    }

    if (Object.keys(contentErrors).length > 0) {
      errors.content = contentErrors;
    }
  }

  return Object.keys(errors).length > 0 ? errors : null;
}

// Export test functions for verification
export {
  testCreateTodoValidation,
  testUpdateTodoValidation,
  validateCreateTodoInput,
};

console.log(
  "Union validation error types with generated types work correctly!",
);
