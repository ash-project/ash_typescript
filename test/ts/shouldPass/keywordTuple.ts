// SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
//
// SPDX-License-Identifier: MIT

// Test file for keyword and tuple type handling in generated TypeScript
import { listTodos, getKeywordOptionsTodo, getCoordinatesInfoTodo } from "../generated";

async function testKeywordTupleFieldSelection() {
  // Test 1: Test the new keyword action with all fields
  const keywordResult = await getKeywordOptionsTodo({
    fields: ["priority", "category", "notify", "theme"],
  });
  
  if (keywordResult.success) {
    const { priority, category, notify, theme } = keywordResult.data;
    
    // Type assertions to verify correct types
    const priorityNum: number = priority;
    const categoryStr: string = category;
    const notifyBool: boolean = notify;
    const themeType: "light" | "dark" | "auto" = theme;
  }

  // Test 2: Test the new keyword action with partial fields
  const keywordPartial = await getKeywordOptionsTodo({
    fields: ["priority", "notify"],
  });
  
  if (keywordPartial.success) {
    const { priority, notify } = keywordPartial.data;
    
    // Type assertions to verify correct types
    const priorityNum: number = priority;
    const notifyBool: boolean = notify;
  }

  // Test 3: Test the new tuple action with field selection
  const tupleResult = await getCoordinatesInfoTodo({
    fields: ["latitude", "longitude", "altitude"],
  });

  if (tupleResult.success) {
    const { latitude, longitude, altitude } = tupleResult.data;

    // Type assertions to verify correct types
    const latNum: number = latitude;
    const lngNum: number = longitude;
    const altNum: number | null = altitude;
  }

  // Test 3b: Test tuple action with partial field selection
  const tuplePartial = await getCoordinatesInfoTodo({
    fields: ["latitude", "longitude"],
  });

  if (tuplePartial.success) {
    const { latitude, longitude } = tuplePartial.data;

    // Type assertions to verify correct types
    const latNum: number = latitude;
    const lngNum: number = longitude;
  }

  // Test 4: Try to request keyword field without field selection - should fail
  await listTodos({
    input: {},
    fields: ["id", "title", { options: ["category"] }],
  });

  // Test 5: Try to request tuple field without field selection - should fail
  await listTodos({
    input: {},
    fields: ["id", "title", { coordinates: ["latitude", "longitude"] }],
  });

  // Test 6: Try with field selection for keyword type
  const todosWithOptions = await listTodos({
    input: {},
    fields: [
      "id",
      "title",
      {
        options: ["priority", "category", "notify"],
      },
    ],
  });
  
  if (todosWithOptions.success) {
    const todos = todosWithOptions.data;
    
    // Check the first todo's options if it exists
    if (todos.length > 0 && todos[0].options) {
      const { priority, category, notify } = todos[0].options;
      
      // Type assertions for the first todo's fields
      const firstTodoId: string = todos[0].id;
      const firstTodoTitle: string = todos[0].title;
      const optionPriority: number = priority;
      const optionCategory: string | null = category;
      const optionNotify: boolean | null = notify;
    }
  }

  // Test 7: Try with field selection for tuple type
  const todosWithCoordinates = await listTodos({
    input: {},
    fields: [
      "id",
      "title",
      {
        coordinates: ["latitude", "longitude"],
      },
    ],
  });
  
  if (todosWithCoordinates.success) {
    const todos = todosWithCoordinates.data;
    
    // Check the first todo's coordinates if it exists
    if (todos.length > 0 && todos[0].coordinates) {
      const { latitude, longitude } = todos[0].coordinates;
      
      // Type assertions for the first todo's fields
      const firstTodoId: string = todos[0].id;
      const firstTodoTitle: string = todos[0].title;
      const coordLatitude: number = latitude;
      const coordLongitude: number = longitude;
    }
  }

  // Test 8: Try with partial field selection for keyword type
  const todosWithPartialOptions = await listTodos({
    input: {},
    fields: [
      "id",
      "title",
      {
        options: ["priority", "category"], // Only some fields
      },
    ],
  });
  
  if (todosWithPartialOptions.success) {
    const todos = todosWithPartialOptions.data;
    
    // Check the first todo's partial options if it exists
    if (todos.length > 0 && todos[0].options) {
      const { priority, category } = todos[0].options;
      
      // Type assertions for the first todo's fields
      const firstTodoId: string = todos[0].id;
      const firstTodoTitle: string = todos[0].title;
      const partialOptionPriority: number = priority;
      const partialOptionCategory: string | null = category;
    }
  }
}

// Export for potential use
export { testKeywordTupleFieldSelection };
