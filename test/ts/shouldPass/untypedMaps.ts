// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Test TypeScript compilation and type safety for untyped map features
import {
  updateTodoWithUntypedData,
  updateTodoWithUntypedDataChannel,
  createTodo,
  updateTodo,
  buildCSRFHeaders
} from "../generated";
import { Channel } from "phoenix";

// Test that untyped map arguments accept various data types
async function testUntypedMapArguments() {
  const todoId = "550e8400-e29b-41d4-a716-446655440000";

  // Test basic untyped map data
  const basicResult = await updateTodoWithUntypedData({
    identity: todoId,
    input: {
      additionalData: {
        stringValue: "test",
        numberValue: 42,
        booleanValue: true,
        nullValue: null
      }
    },
    fields: ["id", "customData"],
    headers: buildCSRFHeaders()
  });

  // Test nested structures
  const nestedResult = await updateTodoWithUntypedData({
    identity: todoId,
    input: {
      additionalData: {
        nested: {
          level2: {
            level3: "deep value"
          }
        },
        arrayOfObjects: [
          { id: 1, name: "Item 1" },
          { id: 2, name: "Item 2" }
        ]
      },
      metadataUpdate: {
        version: "2.0",
        timestamp: Date.now()
      }
    },
    fields: ["id", "title", "customData"]
  });

  // Test with optional metadata_update omitted
  const withoutMetadataResult = await updateTodoWithUntypedData({
    identity: todoId,
    input: {
      additionalData: {
        simpleKey: "simpleValue"
      }
    },
    fields: ["id", "customData"]
  });

  // Test that the customData field in response is properly typed as Record<string, any> | null
  if (basicResult.success && basicResult.data.customData) {
    const customData: Record<string, any> = basicResult.data.customData;
    const stringValue: any = customData.stringValue;
    const numberValue: any = customData.numberValue;
    console.log("Custom data accessed:", stringValue, numberValue);
  }

  return { basicResult, nestedResult, withoutMetadataResult };
}

// Test channel-based operations with untyped maps
function testUntypedMapChannelOperations(channel: Channel) {
  const todoId = "550e8400-e29b-41d4-a716-446655440000";

  updateTodoWithUntypedDataChannel({
    channel,
    identity: todoId,
    input: {
      additionalData: {
        channelData: "test",
        complexObject: {
          settings: {
            theme: "dark",
            notifications: true
          }
        }
      },
      metadataUpdate: {
        updatedVia: "channel",
        timestamp: new Date().toISOString()
      }
    },
    fields: ["id", "title", "customData"],
    resultHandler: (result) => {
      if (result.success) {
        // Type should be properly inferred
        const customData = result.data.customData;
        if (customData) {
          const channelData: any = customData.channelData;
          console.log("Channel update successful:", channelData);
        }
      } else {
        console.error("Channel update failed:", result.errors);
      }
    },
    errorHandler: (error) => console.error("Channel error:", error),
    timeoutHandler: () => console.error("Channel timeout")
  });
}

// Test creating todos with untyped custom data
async function testCreateWithUntypedData() {
  const createResult = await createTodo({
    input: {
      title: "Todo with Custom Data",
      userId: "550e8400-e29b-41d4-a716-446655440000",
      customData: {
        priority: "high",
        tags: ["work", "urgent"],
        metadata: {
          createdBy: "test-user",
          source: "api"
        },
        settings: {
          reminders: true,
          color: "#ff0000"
        }
      }
    },
    fields: ["id", "title", "customData"]
  });

  if (createResult.success && createResult.data.customData) {
    // Verify the custom data is accessible with proper typing
    const customData: Record<string, any> = createResult.data.customData;
    const priority: any = customData.priority;
    const tags: any = customData.tags;
    const metadata: any = customData.metadata;

    console.log("Created todo with custom data:", { priority, tags, metadata });
  }

  return createResult;
}

// Test updating the custom_data attribute directly (not through arguments)
async function testDirectCustomDataUpdate() {
  const todoId = "550e8400-e29b-41d4-a716-446655440000";

  const updateResult = await updateTodo({
    identity: todoId,
    input: {
      title: "Updated Todo with Custom Data",
      customData: {
        directUpdate: true,
        newStructure: {
          settings: {
            theme: "light",
            layout: "compact"
          },
          preferences: {
            language: "en",
            timezone: "UTC"
          }
        }
      }
    },
    fields: ["id", "title", "customData"]
  });

  if (updateResult.success && updateResult.data.customData) {
    const customData: Record<string, any> = updateResult.data.customData;
    const directUpdate: any = customData.directUpdate;
    const newStructure: any = customData.newStructure;

    console.log("Direct update successful:", { directUpdate, newStructure });
  }

  return updateResult;
}

// Test that TypeScript allows any value types in untyped maps
function testUntypedMapTypeFlexibility() {
  // These should all compile without type errors
  const untypedData: Record<string, any> = {
    stringValue: "text",
    numberValue: 42,
    floatValue: 3.14,
    booleanValue: true,
    nullValue: null,
    undefinedValue: undefined,
    arrayValue: [1, "two", 3, true, null],
    objectValue: {
      nested: {
        deeply: {
          nested: "value"
        }
      }
    },
    functionValue: () => "function",
    dateValue: new Date(),
    regexValue: /pattern/g,
    symbolValue: Symbol("test")
  };

  return untypedData;
}

// Export functions for potential testing
export {
  testUntypedMapArguments,
  testUntypedMapChannelOperations,
  testCreateWithUntypedData,
  testDirectCustomDataUpdate,
  testUntypedMapTypeFlexibility
};
