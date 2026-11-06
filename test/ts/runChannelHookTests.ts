// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Runtime tests for the generated channel push helpers: the push uses the
// timeout and handlers from the config the beforeChannelPush hook returns
// (see channelHooks.ts), and the payload stays as the caller built it.

import {
  executeActionChannelPush,
  executeValidationChannelPush,
  validateCreateTodoChannel,
  validateGetUserByEmailChannel,
} from "./generated";

type Status = "ok" | "error" | "timeout";

class FakeChannel {
  pushes: Array<{ event: string; payload: any; timeout: number | undefined }> = [];
  callbacks: Partial<Record<Status, (arg?: any) => Promise<void>>> = {};

  push(event: string, payload: any, timeout: number | undefined) {
    this.pushes.push({ event, payload, timeout });
    const push = {
      receive: (status: Status, callback: (arg?: any) => Promise<void>) => {
        this.callbacks[status] = callback;
        return push;
      },
    };
    return push;
  }

  async reply(status: Status, arg?: any) {
    const callback = this.callbacks[status];
    if (!callback) throw new Error(`no ${status} callback registered`);
    await callback(arg);
  }
}

let failures = 0;

async function runTest(name: string, fn: () => Promise<void>) {
  try {
    await fn();
    console.log(`✓ ${name}`);
  } catch (error) {
    failures++;
    console.error(`✗ ${name}: ${error instanceof Error ? error.message : error}`);
  }
}

// Generated channel functions don't await the push: it happens once the
// beforeChannelPush hook has resolved.
const settled = () => new Promise((resolve) => setTimeout(resolve, 0));

function assertEqual(actual: unknown, expected: unknown, what: string) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a !== e) throw new Error(`${what}: expected ${e}, got ${a}`);
}

async function main() {
  await runTest("action push uses the hook's default timeout", async () => {
    const channel = new FakeChannel();
    await executeActionChannelPush(channel, { action: "list_todos" }, undefined, {
      channel,
      resultHandler: () => {},
    });
    assertEqual(channel.pushes[0]?.timeout, 10000, "timeout");
  });

  await runTest("action push keeps the caller's timeout", async () => {
    const channel = new FakeChannel();
    await executeActionChannelPush(channel, { action: "list_todos" }, 3000, {
      channel,
      timeout: 3000,
      resultHandler: () => {},
    });
    assertEqual(channel.pushes[0]?.timeout, 3000, "timeout");
  });

  await runTest("action push keeps the caller's payload", async () => {
    const channel = new FakeChannel();
    const payload = { action: "list_todos", fields: ["id"] };
    await executeActionChannelPush(channel, payload, undefined, {
      channel,
      fields: ["title"],
      resultHandler: () => {},
    });
    assertEqual(channel.pushes[0]?.payload, payload, "payload");
  });

  await runTest("action push calls the hook's handlers", async () => {
    const channel = new FakeChannel();
    const handled: Status[] = [];
    const called: Status[] = [];
    await executeActionChannelPush(channel, { action: "list_todos" }, undefined, {
      channel,
      hookCtx: { hookHandled: handled },
      resultHandler: () => called.push("ok"),
      errorHandler: () => called.push("error"),
      timeoutHandler: () => called.push("timeout"),
    });
    await channel.reply("ok", { success: true });
    await channel.reply("error", { reason: "boom" });
    await channel.reply("timeout");
    assertEqual(handled, ["ok", "error", "timeout"], "hook handlers");
    assertEqual(called, ["ok", "error", "timeout"], "caller handlers");
  });

  await runTest("validation push uses the hook's default timeout", async () => {
    const channel = new FakeChannel();
    await executeValidationChannelPush(channel, { action: "create_todo" }, undefined, {
      channel,
      resultHandler: () => {},
    });
    assertEqual(channel.pushes[0]?.timeout, 5000, "timeout");
  });

  await runTest("validation push keeps the caller's timeout", async () => {
    const channel = new FakeChannel();
    await executeValidationChannelPush(channel, { action: "create_todo" }, 2000, {
      channel,
      timeout: 2000,
      resultHandler: () => {},
    });
    assertEqual(channel.pushes[0]?.timeout, 2000, "timeout");
  });

  await runTest("validation function passes ok replies to its result handler", async () => {
    const channel = new FakeChannel();
    const results: unknown[] = [];
    validateCreateTodoChannel({
      channel: channel as any,
      input: { title: "Valid", userId: "123e4567-e89b-12d3-a456-426614174000" },
      resultHandler: (result) => results.push(result),
    });
    await settled();
    assertEqual(channel.pushes[0]?.event, "validate", "event");
    assertEqual(channel.pushes[0]?.payload.action, "create_todo", "action");

    const errors = [{ type: "required", message: "is required", fields: ["title"] }];
    await channel.reply("ok", { success: true });
    await channel.reply("ok", { success: false, errors });
    assertEqual(results, [{ success: true }, { success: false, errors }], "results");
  });

  await runTest("validation function passes error replies to its error handler", async () => {
    const channel = new FakeChannel();
    const errors: unknown[] = [];
    validateCreateTodoChannel({
      channel: channel as any,
      input: { title: "Valid", userId: "123e4567-e89b-12d3-a456-426614174000" },
      resultHandler: () => {
        throw new Error("resultHandler called for an error reply");
      },
      errorHandler: (error) => errors.push(error),
    });
    await settled();
    await channel.reply("error", { reason: "unauthorized" });
    assertEqual(errors, [{ reason: "unauthorized" }], "errors");
  });

  await runTest("validation function with getBy sends it in the payload", async () => {
    const channel = new FakeChannel();
    validateGetUserByEmailChannel({
      channel: channel as any,
      getBy: { email: "a@example.com" },
      resultHandler: () => {},
    });
    await settled();
    assertEqual(
      channel.pushes[0]?.payload,
      { action: "get_user_by_email", getBy: { email: "a@example.com" } },
      "payload",
    );
    assertEqual(channel.pushes[0]?.timeout, 5000, "timeout");
  });

  if (failures > 0) {
    // An unhandled rejection exits node with a non-zero status
    throw new Error(`${failures} channel hook test(s) failed`);
  }
  console.log("\nAll channel hook tests passed");
}

main();
