// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
//
// SPDX-License-Identifier: MIT

// Codegen without `output_file`: the routes and typed channels files import
// the shared types file, which holds only what they reach.

import { Socket } from "phoenix";
import { login, loginPath, searchPath } from "./generated_routes";
import {
  createContentFeedChannel,
  onContentFeedChannelMessages,
} from "./generated_typed_channels";
import type { AlertSentPayload, UUID } from "./ash_types";
// The schema files hold the route schemas and the custom types they can
// use, and no resource schemas.
import { loginZodSchema, MoneyZodSchema } from "./ash_zod";
import { loginValibotSchema, MoneyValibotSchema } from "./ash_valibot";

export const loginUrl: string = loginPath();
export const searchUrl: string = searchPath({ q: "x", tags: ["ab"] });
export const loggedIn = login({ code: "abc" });

export function subscribe(socket: Socket, id: UUID) {
  const channel = createContentFeedChannel(socket, id);
  return onContentFeedChannelMessages(channel, {});
}

export type Alert = AlertSentPayload;

// @ts-expect-error no RPC file is generated
import { listTodos } from "./generated";

// @ts-expect-error resource schemas stay out of the types file
import type { TodoResourceSchema } from "./ash_types";

// @ts-expect-error resource schemas stay out of the schema files
import { TaskNoteZodSchema } from "./ash_zod";

export const schemas = [loginZodSchema, MoneyZodSchema, loginValibotSchema, MoneyValibotSchema];

export type Unused = [typeof listTodos, TodoResourceSchema, typeof TaskNoteZodSchema];
