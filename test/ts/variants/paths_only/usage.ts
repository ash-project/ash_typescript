// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
//
// SPDX-License-Identifier: MIT

// `typed_controller_mode: :paths_only`: path helpers, no fetch functions.

import { loginPath, providerPagePath, searchPath } from "./generated_routes";

export const searchUrl: string = searchPath({ q: "x" });
export const loginUrl: string = loginPath();
export const providerUrl: string = providerPagePath({ provider: "github" }, { tab: "keys" });

// @ts-expect-error mutation fetch functions are not generated
import { login } from "./generated_routes";

// @ts-expect-error GET fetch functions are not generated either
import { search } from "./generated_routes";

export const unused = [login, search];
