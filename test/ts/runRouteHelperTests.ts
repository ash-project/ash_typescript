// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
//
// SPDX-License-Identifier: MIT

// Runtime tests for the generated route helpers: a GET helper's query string
// (array arguments as repeated `tags[]` pairs) and the request its fetch
// function makes.

import { search, searchPath } from "./generated_routes";

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

function assertEqual(actual: unknown, expected: unknown, what: string) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a !== e) throw new Error(`${what}: expected ${e}, got ${a}`);
}

function queryPairs(url: string): Array<[string, string]> {
  const pairs: Array<[string, string]> = [];
  new URLSearchParams(url.split("?")[1] ?? "").forEach((value, key) => pairs.push([key, value]));
  return pairs;
}

async function main() {
  await runTest("GET path helper sends array arguments as tags[] pairs in order", async () => {
    const url = searchPath({ q: "x", tags: ["ab", "cd"] });
    assertEqual(url.split("?")[0], "/search", "path");
    assertEqual(url.includes("tags%5B%5D=ab&tags%5B%5D=cd"), true, `encoded pairs in ${url}`);
    assertEqual(queryPairs(url), [["q", "x"], ["tags[]", "ab"], ["tags[]", "cd"]], "query");
  });

  await runTest("GET path helper leaves out unset optional arguments", async () => {
    assertEqual(searchPath({ q: "x" }), "/search?q=x", "url");
    assertEqual(searchPath({ q: "x", page: null, tags: null }), "/search?q=x", "url with nulls");
  });

  await runTest("GET fetch function requests the helper's URL", async () => {
    const requests: Array<{ url: string; init: RequestInit | undefined }> = [];
    const customFetch = async (input: RequestInfo | URL, init?: RequestInit) => {
      requests.push({ url: String(input), init });
      return new Response("[]", { status: 200 });
    };

    const response = await search({ q: "x", page: 2, tags: ["ab"] }, { customFetch });
    assertEqual(response.ok, true, "ok");
    assertEqual(requests.length, 1, "requests");
    assertEqual(queryPairs(requests[0]!.url), [["q", "x"], ["page", "2"], ["tags[]", "ab"]], "query");
    assertEqual(requests[0]!.init?.method, "GET", "method");
    assertEqual(requests[0]!.init?.body, undefined, "body");
    assertEqual(
      (requests[0]!.init?.headers as Record<string, string>)["Accept"],
      "application/json",
      "Accept",
    );
  });

  if (failures > 0) {
    // An unhandled rejection exits node with a non-zero status
    throw new Error(`${failures} route helper test(s) failed`);
  }
  console.log("\nAll route helper tests passed");
}

main();
