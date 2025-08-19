// Operations Tests - shouldPass
// Tests for basic CRUD operations (create, list, get, update)

import {
  getTodo,
  listTodos,
  createTodo,
  searchTodos,
  getStatisticsTodo,
} from "../generated";

// Test 4: List operation with nested self calculations
export const listWithNestedSelf = await listTodos({
  input: {},
  fields: [
    "id",
    "title",
    "completed",
    {
      self: {
        args: { prefix: "list_" },
        fields: [
          "id",
          "title",
          "status",
          "priority",
          {
            self: {
              args: { prefix: "list_nested_" },
              fields: [
                "description",
                "tags",
                {
                  metadata: ["category", "priorityScore"],
                },
              ],
            },
          },
        ],
      },
    },
  ],
});

// Type validation for list results with nested calculations
if (listWithNestedSelf.success) {
  for (const todo of listWithNestedSelf.data.results) {
    // Each todo should have the basic fields
    const todoId: string = todo.id;
    const todoTitle: string = todo.title;
    const todoCompleted: boolean | null | undefined = todo.completed;

    // Each todo should have the self calculation
    if (todo.self) {
      const selfStatus: string | null | undefined = todo.self.status;
      const selfPriority: string | null | undefined = todo.self.priority;

      // Each self should have the nested self calculation
      if (todo.self.self) {
        const nestedDescription: string | null | undefined =
          todo.self.self.description;
        const nestedTags: string[] | null | undefined = todo.self.self.tags;
        const nestedMetadata: Record<string, any> | null | undefined =
          todo.self.self.metadata;
      }
    }
  }
}

// Test 5: Create operation with nested self calculations in response
export const createWithNestedSelf = await createTodo({
  input: {
    title: "Test Todo",
    status: "pending",
    userId: "user-id-123",
  },
  fields: [
    "id",
    "title",
    "createdAt",
    {
      self: {
        args: { prefix: "created_" },
        fields: [
          "id",
          "title",
          "status",
          "userId",
          {
            self: {
              args: { prefix: "created_nested_" },
              fields: ["completed", "priority", "dueDate"],
            },
          },
        ],
      },
    },
  ],
});

// Type validation for created result
if (createWithNestedSelf.success) {
  const createdId: string = createWithNestedSelf.data.id;
  const createdTitle: string = createWithNestedSelf.data.title;

  if (createWithNestedSelf.data.self?.self) {
    const nestedCompleted: boolean | null | undefined =
      createWithNestedSelf.data.self.self.completed;
    const nestedPriority: string | null | undefined =
      createWithNestedSelf.data.self.self.priority;
    const nestedDueDate: string | null | undefined =
      createWithNestedSelf.data.self.self.dueDate;
  }
}

// Test 6: Read operations with input parameters
export const listWithInputParams = await listTodos({
  input: {
    filterCompleted: true,
    priorityFilter: "high",
  },
  fields: ["id", "title", "completed", "priority"],
});

// Type validation for list with input parameters
if (listWithInputParams.success) {
  for (const todo of listWithInputParams.data.results) {
    const todoId: string = todo.id;
    const todoTitle: string = todo.title;
    const todoCompleted: boolean | null | undefined = todo.completed;
    const todoPriority: string | null | undefined = todo.priority;
  }
}

// Test 7: Read operations with partial input parameters (optional fields)
export const listWithPartialInput = await listTodos({
  input: {
    filterCompleted: false,
    // priorityFilter is optional and omitted
  },
  fields: ["id", "title", "status"],
});

// Test 8: Read operations with no input parameters (should still work)
export const listWithoutInput = await listTodos({
  input: {},
  fields: ["id", "title"],
});

const searchTodosResult = await searchTodos({
  input: {
    query: "example",
  },
  fields: [
    "id",
    "title",
    { comments: ["id", "content"], user: ["id", "email"] },
  ],
});

if (searchTodosResult.success) {
  const id: string = searchTodosResult.data[0].id;
  const userEmail: string = searchTodosResult.data[0].user.email;
}

const getStatisticsTodoResult = await getStatisticsTodo({
  input: {},
  fields: ["completed", "pending"],
});

if (getStatisticsTodoResult.success) {
  const completed: number = getStatisticsTodoResult.data.completed;
}
console.log("Operations tests should compile successfully!");
