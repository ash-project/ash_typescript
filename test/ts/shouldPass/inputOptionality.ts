// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Input Optionality Tests - shouldPass
// Tests for input type optionality based on allow_nil_input and require_attributes

import {
  createArticleWithOptionalHeroImage,
  updateArticleWithRequiredHeroImageAlt,
  CreateArticleWithOptionalHeroImageInput,
  UpdateArticleWithRequiredHeroImageAltInput,
} from "../generated";

// =============================================================================
// Test: Create action with allow_nil_input
// The create_with_optional_hero_image action has allow_nil_input: [:hero_image_url]
// This means heroImageUrl should be optional even though the attribute has allow_nil?: false
// =============================================================================

const createInputWithoutHeroImageUrl: CreateArticleWithOptionalHeroImageInput =
  {
    contentId: "content-123",
    heroImageAlt: "Alt text for hero image",
    summary: "Article summary",
    body: "Article body content",
  };

const createInputWithAllFields: CreateArticleWithOptionalHeroImageInput = {
  contentId: "content-456",
  heroImageUrl: "https://example.com/image.jpg",
  heroImageAlt: "Alt text for hero image",
  summary: "Article summary",
  body: "Article body content",
};

export const createWithoutHeroImageUrl =
  await createArticleWithOptionalHeroImage({
    input: createInputWithoutHeroImageUrl,
    fields: ["id", "heroImageUrl", "heroImageAlt"],
  });

export const createWithAllFields = await createArticleWithOptionalHeroImage({
  input: createInputWithAllFields,
  fields: ["id", "heroImageUrl", "heroImageAlt"],
});

// =============================================================================
// Test: Update action with require_attributes
// The update_with_required_hero_image_alt action has require_attributes: [:hero_image_alt]
// This means heroImageAlt is required, but other attributes are optional for updates
// =============================================================================

const updateInputWithOnlyRequired: UpdateArticleWithRequiredHeroImageAltInput =
  {
    heroImageAlt: "Updated alt text",
  };

const updateInputWithAllFields: UpdateArticleWithRequiredHeroImageAltInput = {
  heroImageUrl: "https://example.com/new-image.jpg",
  heroImageAlt: "Updated alt text",
  summary: "Updated summary",
  body: "Updated body content",
};

const updateInputWithSomeOptional: UpdateArticleWithRequiredHeroImageAltInput =
  {
    heroImageAlt: "Updated alt text",
    summary: "Updated summary",
  };

export const updateWithOnlyRequired =
  await updateArticleWithRequiredHeroImageAlt({
    primaryKey: "article-123",
    input: updateInputWithOnlyRequired,
    fields: ["id", "heroImageAlt"],
  });

export const updateWithAllFields = await updateArticleWithRequiredHeroImageAlt({
  primaryKey: "article-456",
  input: updateInputWithAllFields,
  fields: ["id", "heroImageUrl", "heroImageAlt", "summary", "body"],
});

export const updateWithSomeOptional =
  await updateArticleWithRequiredHeroImageAlt({
    primaryKey: "article-789",
    input: updateInputWithSomeOptional,
    fields: ["id", "heroImageAlt", "summary"],
  });

if (createWithoutHeroImageUrl.success) {
  const id: string = createWithoutHeroImageUrl.data.id;
  const heroImageUrl: string | null | undefined =
    createWithoutHeroImageUrl.data.heroImageUrl;
  const heroImageAlt: string | null | undefined =
    createWithoutHeroImageUrl.data.heroImageAlt;
}

if (updateWithOnlyRequired.success) {
  const id: string = updateWithOnlyRequired.data.id;
  const heroImageAlt: string | null | undefined =
    updateWithOnlyRequired.data.heroImageAlt;
}

console.log("Input optionality tests should compile successfully!");
