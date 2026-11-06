// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
//
// SPDX-License-Identifier: MIT

// `typed_controller_base_path: {:runtime_expr, "AppConfig.getBasePath()"}`:
// the routes file uses the expression, which the app declares globally.

import { login, loginPath, searchPath } from "./generated_routes";

declare global {
  const AppConfig: { getBasePath(): string };
}

export const loginUrl: string = loginPath();
export const searchUrl: string = searchPath({ q: "x" });
export const loggedIn = login({ code: "abc" });

// @ts-expect-error the path helper takes no base path
export const withBase = loginPath(AppConfig.getBasePath());
