// SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
//
// SPDX-License-Identifier: MIT

export type ColorPalette = {
  primary: string;
  secondary: string;
  accent: string;
};

export type ColorPaletteValidationErrors = {
  primary?: string[];
  secondary?: string[];
  accent?: string[];
};

export type PriorityScore = number;

export type PriorityScoreValidationErrors = string[];
