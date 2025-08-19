// Complex Scenarios Tests - shouldPass
// Tests that combine multiple features and complex usage patterns

import { getTodo } from "../generated";

// Test 7: Complex scenario combining multiple patterns
export const complexScenario = await getTodo({
  input: {},
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
        args: { prefix: "complex_" },
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
              args: { prefix: "complex_nested_" },
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
if (complexScenario.success && complexScenario.data) {
  // Top level
  const topIsOverdue: boolean | null | undefined =
    complexScenario.data.isOverdue;
  const topCommentCount: number = complexScenario.data.commentCount;

  // Top level colorPalette custom type
  if (complexScenario.data.colorPalette) {
    const topColorPalette: {
      primary: string;
      secondary: string;
      accent: string;
    } = complexScenario.data.colorPalette;
    const topPrimary: string = topColorPalette.primary;
    const topSecondary: string = topColorPalette.secondary;
    const topAccent: string = topColorPalette.accent;
  }

  // First level self
  if (complexScenario.data.self) {
    const selfDaysUntilDue: number | null | undefined =
      complexScenario.data.self.daysUntilDue;
    const selfHelpfulCount: number =
      complexScenario.data.self.helpfulCommentCount;

    // First level self colorPalette custom type
    if (complexScenario.data.self.colorPalette) {
      const selfColorPalette: {
        primary: string;
        secondary: string;
        accent: string;
      } = complexScenario.data.self.colorPalette;
      const selfPrimary: string = selfColorPalette.primary;
      const selfSecondary: string = selfColorPalette.secondary;
      const selfAccent: string = selfColorPalette.accent;
    }

    // Second level self
    if (complexScenario.data.self.self) {
      const nestedTags: string[] | null | undefined =
        complexScenario.data.self.self.tags;

      // Second level self colorPalette custom type
      if (complexScenario.data.self.self.colorPalette) {
        const nestedColorPalette: {
          primary: string;
          secondary: string;
          accent: string;
        } = complexScenario.data.self.self.colorPalette;
        const nestedPrimary: string = nestedColorPalette.primary;
        const nestedSecondary: string = nestedColorPalette.secondary;
        const nestedAccent: string = nestedColorPalette.accent;
      }

      // Nested relationships should be properly typed
      const nestedComments = complexScenario.data.self.self.comments;
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
