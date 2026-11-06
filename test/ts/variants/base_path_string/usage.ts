// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
//
// SPDX-License-Identifier: MIT

// `typed_controller_base_path: "https://api.example.com"`.

import { login, loginPath, searchPath } from "./generated_routes";

export const loginUrl: string = loginPath();
export const searchUrl: string = searchPath({ q: "x" });
export const loggedIn = login({ code: "abc" });

// @ts-expect-error the base path is not a parameter
export const withBase = loginPath("https://other.example.com");
