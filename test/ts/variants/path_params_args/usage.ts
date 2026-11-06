// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
//
// SPDX-License-Identifier: MIT

// `typed_controller_path_params_style: :args`: path params are positional
// arguments; one named by a reserved word is bound as `<name>Param`.

import { itemPagePath, providerPagePath, updateProvider } from "./generated_routes";

export const providerUrl: string = providerPagePath("github", { tab: "keys" });
export const itemUrl: string = itemPagePath("abc");
export const updated = updateProvider("github", { enabled: true });

// @ts-expect-error the object style is not generated
export const objectStyle = providerPagePath({ provider: "github" });

// @ts-expect-error the path param is required
export const missing = itemPagePath();
