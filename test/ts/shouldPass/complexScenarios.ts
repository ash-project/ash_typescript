// Complex Scenarios Tests - shouldPass
// Tests that combine multiple features and complex usage patterns

import {
  getTodo,
} from "../generated";

// Test 7: Complex scenario combining multiple patterns
export const complexScenario = await getTodo({
  fields: [
    "id",
    "title",
    "status",
    "isOverdue", // calculation via fields
    "commentCount", // aggregate via fields
    "helpfulCommentCount",
    "colorPalette", // custom type in complex scenario
    {
      user: ["id", "email"],
      comments: ["id", "content", { user: ["id", "name"] }],
    },
    {
      self: {
        calcArgs: { prefix: "complex_" },
        fields: [
          "id",
          "description",
          "priority",
          "daysUntilDue", // calculation in nested self
          "helpfulCommentCount", // aggregate in nested self
          "colorPalette", // custom type in nested self
          {
            user: ["id", "name", "email"],
            comments: ["id", "authorName", "rating"],
          },
          {
            self: {
              calcArgs: { prefix: "complex_nested_" },
              fields: [
                "tags",
                "createdAt",
                "colorPalette", // custom type in deeply nested self
                {
                  metadata: ["category", "isUrgent"],
                  comments: ["id", "isHelpful", { user: ["id"] }],
                },
              ],
            },
          },
        ],
      },
    },
  ],
});

// Validate complex type inference
if (complexScenario) {
  // Top level
  const topIsOverdue: boolean | null | undefined = complexScenario.isOverdue;
  const topCommentCount: number = complexScenario.commentCount;

  // Top level colorPalette custom type
  if (complexScenario.colorPalette) {
    const topColorPalette: { primary: string; secondary: string; accent: string } = complexScenario.colorPalette;
    const topPrimary: string = topColorPalette.primary;
    const topSecondary: string = topColorPalette.secondary;
    const topAccent: string = topColorPalette.accent;
  }

  // First level self
  if (complexScenario.self) {
    const selfDaysUntilDue: number | null | undefined =
      complexScenario.self.daysUntilDue;
    const selfHelpfulCount: number = complexScenario.self.helpfulCommentCount;

    // First level self colorPalette custom type
    if (complexScenario.self.colorPalette) {
      const selfColorPalette: { primary: string; secondary: string; accent: string } = complexScenario.self.colorPalette;
      const selfPrimary: string = selfColorPalette.primary;
      const selfSecondary: string = selfColorPalette.secondary;
      const selfAccent: string = selfColorPalette.accent;
    }

    // Second level self
    if (complexScenario.self.self) {
      const nestedTags: string[] | null | undefined =
        complexScenario.self.self.tags;

      // Second level self colorPalette custom type
      if (complexScenario.self.self.colorPalette) {
        const nestedColorPalette: { primary: string; secondary: string; accent: string } = complexScenario.self.self.colorPalette;
        const nestedPrimary: string = nestedColorPalette.primary;
        const nestedSecondary: string = nestedColorPalette.secondary;
        const nestedAccent: string = nestedColorPalette.accent;
      }

      // Nested relationships should be properly typed
      const nestedComments = complexScenario.self.self.comments;
      if (nestedComments.length > 0) {
        const nestedComment = nestedComments[0];
        const isHelpful: boolean | null | undefined = nestedComment.isHelpful;
        const commentUser = nestedComment.user;
        const commentUserId: string = commentUser.id;
      }
    }
  }
}

console.log("Complex scenarios tests should compile successfully!");