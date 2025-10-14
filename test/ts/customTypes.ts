// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
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
