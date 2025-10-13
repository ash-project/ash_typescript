// SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
//
// SPDX-License-Identifier: MIT

// Channel Timeout Test - shouldPass
// Tests that timeout parameter works correctly with channel functions

import { Channel } from "phoenix";
import { listTodosChannel, validateListTodosChannel } from "../generated";

// Mock channel for testing
declare const mockChannel: Channel;

// Test 1: Channel function with timeout parameter
listTodosChannel({
  channel: mockChannel,
  input: {},
  fields: ["id", "title"],
  resultHandler: (result) => {
    if (result.success) {
      console.log("Success:", result.data);
    }
  },
  errorHandler: (error) => console.error("Error:", error),
  timeoutHandler: () => console.error("Timeout"),
  timeout: 10000, // 10 second timeout
});

// Test 2: Channel function without timeout parameter (should still work)
listTodosChannel({
  channel: mockChannel,
  input: {},
  fields: ["id", "title"],
  resultHandler: (result) => {
    if (result.success) {
      console.log("Success:", result.data);
    }
  },
  errorHandler: (error) => console.error("Error:", error),
  timeoutHandler: () => console.error("Timeout"),
  // timeout parameter is optional
});

// Test 3: Validation function with timeout parameter
validateListTodosChannel({
  channel: mockChannel,
  input: {},
  resultHandler: (result) => {
    if (result.success) {
      console.log("Validation success");
    }
  },
  errorHandler: (error) => console.error("Validation error:", error),
  timeoutHandler: () => console.error("Validation timeout"),
  timeout: 5000, // 5 second timeout
});

console.log("Channel timeout tests should compile successfully!");
