// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Tests for createContent RPC action with typed map field constraints

import { createContent } from "../generated";

// Test 1: Basic createContent with required item typed map
export const basicCreate = await createContent({
  input: {
    title: "Getting Started with Fitness",
    thumbnailUrl: "thumb.jpg",
    thumbnailAlt: "Fitness thumbnail",
    userId: "00000000-0000-0000-0000-000000000001",
    item: {
      heroImageUrl: "hero.jpg",
      heroImageAlt: "Hero image",
      summary: "A guide to getting started",
      body: "Full article body content here..."
    }
  },
  fields: ["id", "title", "category"]
});

// Test 2: With minimal item typed map fields
export const createWithMinimalItem = await createContent({
  input: {
    title: "Nutrition Basics",
    thumbnailUrl: "nutrition.jpg",
    thumbnailAlt: "Nutrition thumbnail",
    category: "nutrition",
    userId: "00000000-0000-0000-0000-000000000001",
    item: {
      heroImageUrl: "nutrition-hero.jpg",
      heroImageAlt: "Nutrition hero",
      summary: "Quick nutrition tips",
      body: "Nutrition content"
    }
  },
  fields: ["id", "title", "thumbnailUrl", "category"]
});

// Test 3: With all optional input fields
export const createWithAllOptionals = await createContent({
  input: {
    type: "article",
    title: "Mindset for Success",
    thumbnailUrl: "mindset.jpg",
    thumbnailAlt: "Mindset thumbnail",
    publishedAt: "2025-01-15T10:00:00Z",
    category: "mindset",
    authorId: "00000000-0000-0000-0000-000000000002",
    userId: "00000000-0000-0000-0000-000000000001",
    item: {
      heroImageUrl: "mindset-hero.jpg",
      heroImageAlt: "Mindset hero",
      summary: "Building a winning mindset",
      body: "Detailed content about mindset..."
    }
  },
  fields: ["id", "title", "type", "publishedAt", "authorId"]
});

// Test 4: Request relationship fields
export const createWithRelationships = await createContent({
  input: {
    title: "Progress Tracking",
    thumbnailUrl: "progress.jpg",
    thumbnailAlt: "Progress thumbnail",
    category: "progress",
    authorId: "00000000-0000-0000-0000-000000000002",
    userId: "00000000-0000-0000-0000-000000000001",
    item: {
      heroImageUrl: "progress-hero.jpg",
      heroImageAlt: "Progress hero",
      summary: "Track your progress",
      body: "How to measure success..."
    }
  },
  fields: ["id", "title", "category", { author: ["id", "name", "email"] }]
});

// Type validation for results
if (basicCreate.success) {
  const id: string = basicCreate.data.id;
  const title: string = basicCreate.data.title;
  const category: "fitness" | "nutrition" | "mindset" | "progress" =
    basicCreate.data.category;
}

if (createWithRelationships.success) {
  const id: string = createWithRelationships.data.id;
  const author = createWithRelationships.data.author;
  if (author) {
    const authorName: string = author.name;
    const authorEmail: string = author.email;
  }
}

console.log("createContent tests should compile successfully!");
