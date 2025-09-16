// Channel Operations Tests - shouldPass
// Tests for channel-based CRUD operations

import { Channel } from "phoenix";
import {
  getTodoChannel,
  listTodosChannel,
  createTodoChannel,
  updateTodoChannel,
  destroyTodoChannel,
} from "../generated";

// Mock channel for testing
declare const mockChannel: Channel;

// Test 1: Channel-based read operation (get)
getTodoChannel({
  channel: mockChannel,
  input: {},
  fields: ["id", "title", "completed"],
  resultHandler: (result) => {
    if (result.success && result.data) {
      const todoId: string = result.data.id;
      const todoTitle: string = result.data.title;
      const todoCompleted: boolean | null | undefined = result.data.completed;
    } else if (!result.success) {
      console.error("Error:", result.errors);
    }
  },
  errorHandler: (error) => console.error("Channel error:", error),
  timeoutHandler: () => console.error("Timeout"),
});

// Test 2: Channel-based read operation (list)
listTodosChannel({
  channel: mockChannel,
  input: {
    filterCompleted: true,
    priorityFilter: "high",
  },
  fields: ["id", "title", "status", { user: ["id", "name", "email"] }],
  resultHandler: (result) => {
    if (result.success) {
      for (const todo of result.data.results) {
        const todoId: string = todo.id;
        const todoTitle: string = todo.title;
        const todoStatus:
          | "pending"
          | "ongoing"
          | "finished"
          | "cancelled"
          | null
          | undefined = todo.status;
        const userId: string = todo.user.id;
        const userName: string = todo.user.name;
        const userEmail: string = todo.user.email;
      }
    }
  },
  errorHandler: (error) => console.error("List error:", error),
  timeoutHandler: () => console.error("List timeout"),
});

// Test 3: Channel-based create operation
createTodoChannel({
  channel: mockChannel,
  input: {
    title: "Channel Todo",
    status: "pending",
    userId: "user-123",
  },
  fields: ["id", "title", "status", "createdAt", { user: ["id", "name"] }],
  resultHandler: (result) => {
    if (result.success) {
      const createdId: string = result.data.id;
      const createdTitle: string = result.data.title;
      const createdStatus:
        | "pending"
        | "ongoing"
        | "finished"
        | "cancelled"
        | null
        | undefined = result.data.status;
      const createdAt: string = result.data.createdAt;
      const userName: string = result.data.user.name;
    } else {
      console.error("Create error:", result.errors);
    }
  },
  errorHandler: (error) => console.error("Create channel error:", error),
  timeoutHandler: () => console.error("Create timeout"),
});

// Test 4: Channel-based update operation
updateTodoChannel({
  channel: mockChannel,
  primaryKey: "todo-123",
  input: {
    title: "Updated Channel Todo",
    completed: true,
  },
  fields: [
    "id",
    "title",
    "completed",
    "status",
    {
      self: {
        args: { prefix: "updated_" },
        fields: ["id", "title", "priority"],
      },
    },
  ],
  resultHandler: (result) => {
    if (result.success) {
      const updatedId: string = result.data.id;
      const updatedTitle: string = result.data.title;
      const updatedCompleted: boolean | null | undefined =
        result.data.completed;
      if (result.data.self) {
        const selfPriority:
          | "low"
          | "medium"
          | "high"
          | "urgent"
          | null
          | undefined = result.data.self.priority;
      }
    }
  },
  errorHandler: (error) => console.error("Update error:", error),
  timeoutHandler: () => console.error("Update timeout"),
});

// Test 5: Channel-based destroy operation
destroyTodoChannel({
  channel: mockChannel,
  primaryKey: "todo-to-delete",
  resultHandler: (result) => {
    if (result.success) {
      console.log("Todo deleted successfully");
    }
  },
  errorHandler: (error) => console.error("Delete channel error:", error),
  timeoutHandler: () => console.error("Delete timeout"),
});

console.log("Channel operations tests should compile successfully!");
