// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
//
// SPDX-License-Identifier: MIT

// RPC output under `output_field_formatter: :pascal_case` (the manifest
// redecorated): function names and request and response keys are
// PascalCase, and so are the keys its hooks (`rpcHooks.ts`,
// `channelHooks.ts`) read and set.

import { Channel } from "phoenix";
import { ListTodos, ListTodosChannel } from "./generated";

export async function pascalKeys() {
  const result = await ListTodos({ Fields: ["Id", "Title"], HookCtx: { customHeaders: {} } });
  if (result.Success) {
    const ids: string[] = result.Data.map((todo) => todo.Id);
    return ids;
  }
  return result.Errors.map((error) => error.Message);
}

// A page narrows the result to the page shape.
export async function paged() {
  const result = await ListTodos({ Fields: ["Id"], Page: { Limit: 10, Offset: 0 } });
  if (result.Success) {
    const hasMore: boolean = result.Data.HasMore;
    const ids: string[] = result.Data.Results.map((todo) => todo.Id);
    return { hasMore, ids };
  }
  return null;
}

// A calculation's selected fields type its result.
export async function calculationFields() {
  const result = await ListTodos({
    Fields: ["Id", { Self: { Args: { Prefix: "p" }, Fields: ["Title"] } }],
  });
  if (result.Success) {
    const titles: Array<string | undefined> = result.Data.map((todo) => todo.Self?.Title);
    return titles;
  }
  return null;
}

export function overChannel(channel: Channel) {
  ListTodosChannel({
    Channel: channel,
    Fields: ["Id"],
    Page: { Limit: 5, After: "cursor" },
    ResultHandler: (result) => {
      if (result.Success) {
        const next: string | null = result.Data.NextPage;
        console.log(next);
      }
    },
  });
}

// @ts-expect-error camelCase request keys are not accepted
export const camel = ListTodos({ fields: ["id"] });

// @ts-expect-error the camelCase function name is not generated
import { listTodos } from "./generated";

export const unused = listTodos;
