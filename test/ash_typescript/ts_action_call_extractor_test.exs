# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.TsActionCallExtractorTest do
  use ExUnit.Case, async: true
  alias AshTypescript.Test.TsActionCallExtractor

  describe "extract_calls/1" do
    test "extracts simple function call with basic config" do
      ts_code = """
      await createTodo({
        input: {title: "Test"},
        fields: ["id", "title"]
      });
      """

      result = TsActionCallExtractor.extract_calls(ts_code)

      assert [call] = result
      assert call.function_name == "createTodo"
      assert call.action_name == "create_todo"
      assert call.config["input"]["title"] == "Test"
      assert call.config["fields"] == ["id", "title"]
    end

    test "converts camelCase function names to snake_case action names" do
      ts_code = """
      await getTodoById({fields: ["id"]});
      await readTasksWithMetadata({fields: ["id"]});
      await listTodos({fields: ["id"]});
      """

      result = TsActionCallExtractor.extract_calls(ts_code)

      assert length(result) == 3
      assert Enum.at(result, 0).action_name == "get_todo_by_id"
      assert Enum.at(result, 1).action_name == "read_tasks_with_metadata"
      assert Enum.at(result, 2).action_name == "list_todos"
    end

    test "handles nested objects" do
      ts_code = """
      await createTodo({
        input: {
          title: "Test",
          content: {
            text: {
              id: "1",
              text: "Hello"
            }
          }
        },
        fields: ["id"]
      });
      """

      result = TsActionCallExtractor.extract_calls(ts_code)

      assert [call] = result
      assert call.config["input"]["content"]["text"]["id"] == "1"
      assert call.config["input"]["content"]["text"]["text"] == "Hello"
    end

    test "handles arrays with objects" do
      ts_code = """
      await getTodo({
        fields: [
          "id",
          "title",
          {
            self: {
              args: {prefix: "test_"},
              fields: ["id", "title"]
            }
          }
        ]
      });
      """

      result = TsActionCallExtractor.extract_calls(ts_code)

      assert [call] = result
      fields = call.config["fields"]
      assert "id" in fields
      assert "title" in fields
      assert is_map(Enum.at(fields, 2))
      self_config = Enum.at(fields, 2)["self"]
      assert self_config["args"]["prefix"] == "test_"
    end

    test "handles null values" do
      ts_code = """
      await getTodo({
        input: {},
        fields: [
          "id",
          {
            self: {
              args: {prefix: null},
              fields: ["id"]
            }
          }
        ]
      });
      """

      result = TsActionCallExtractor.extract_calls(ts_code)

      assert [call] = result
      self_config = Enum.at(call.config["fields"], 1)["self"]
      assert self_config["args"]["prefix"] == nil
    end

    test "handles undefined values (converts to null)" do
      ts_code = """
      await getTodo({
        fields: [
          "id",
          {
            self: {
              args: {prefix: undefined},
              fields: ["id"]
            }
          }
        ]
      });
      """

      result = TsActionCallExtractor.extract_calls(ts_code)

      assert [call] = result
      self_config = Enum.at(call.config["fields"], 1)["self"]
      assert self_config["args"]["prefix"] == nil
    end

    test "strips single-line comments" do
      ts_code = """
      await createTodo({
        // This is a comment
        input: {
          title: "Test" // inline comment
        },
        fields: ["id"] // end comment
      });
      """

      result = TsActionCallExtractor.extract_calls(ts_code)

      assert [call] = result
      assert call.config["input"]["title"] == "Test"
      assert call.config["fields"] == ["id"]
    end

    test "strips multi-line comments" do
      ts_code = """
      await createTodo({
        /* This is a
           multi-line comment */
        input: {
          title: "Test" /* inline block comment */
        },
        fields: ["id"]
      });
      """

      result = TsActionCallExtractor.extract_calls(ts_code)

      assert [call] = result
      assert call.config["input"]["title"] == "Test"
    end

    test "removes trailing commas" do
      ts_code = """
      await createTodo({
        input: {
          title: "Test",
          status: "pending",
        },
        fields: ["id", "title",],
      });
      """

      result = TsActionCallExtractor.extract_calls(ts_code)

      assert [call] = result
      assert call.config["input"]["title"] == "Test"
      assert call.config["fields"] == ["id", "title"]
    end

    test "removes 'as const' assertions" do
      ts_code = """
      await getTodo({
        fields: ["id", "title"] as const
      });
      """

      result = TsActionCallExtractor.extract_calls(ts_code)

      assert [call] = result
      assert call.config["fields"] == ["id", "title"]
    end

    test "handles strings with special characters" do
      ts_code = """
      await createTodo({
        input: {
          title: "Title with: colon",
          description: "Description with, comma and (parens)",
          notes: "Line 1\\nLine 2"
        },
        fields: ["id"]
      });
      """

      result = TsActionCallExtractor.extract_calls(ts_code)

      assert [call] = result
      assert call.config["input"]["title"] == "Title with: colon"
      assert call.config["input"]["description"] == "Description with, comma and (parens)"
      # JSON parsing converts \n to actual newline
      assert call.config["input"]["notes"] == "Line 1\nLine 2"
    end

    test "handles escaped quotes in strings" do
      ts_code = """
      await createTodo({
        input: {
          title: "Title with \\"escaped\\" quotes"
        },
        fields: ["id"]
      });
      """

      result = TsActionCallExtractor.extract_calls(ts_code)

      assert [call] = result
      assert call.config["input"]["title"] == "Title with \"escaped\" quotes"
    end

    test "handles empty objects and arrays" do
      ts_code = """
      await createTodo({
        input: {},
        fields: []
      });
      """

      result = TsActionCallExtractor.extract_calls(ts_code)

      assert [call] = result
      assert call.config["input"] == %{}
      assert call.config["fields"] == []
    end

    test "handles numbers and booleans" do
      ts_code = """
      await createTodo({
        input: {
          title: "Test",
          count: 42,
          enabled: true,
          disabled: false,
          rating: 3.14
        },
        fields: ["id"]
      });
      """

      result = TsActionCallExtractor.extract_calls(ts_code)

      assert [call] = result
      assert call.config["input"]["count"] == 42
      assert call.config["input"]["enabled"] == true
      assert call.config["input"]["disabled"] == false
      assert call.config["input"]["rating"] == 3.14
    end

    test "extracts multiple calls from same file" do
      ts_code = """
      export const call1 = await createTodo({fields: ["id"]});
      export const call2 = await updateTodo({primaryKey: "123", fields: ["id"]});
      export const call3 = await listTodos({fields: ["id", "title"]});
      """

      result = TsActionCallExtractor.extract_calls(ts_code)

      assert length(result) == 3
      assert Enum.at(result, 0).function_name == "createTodo"
      assert Enum.at(result, 1).function_name == "updateTodo"
      assert Enum.at(result, 2).function_name == "listTodos"
    end

    test "handles metadataFields parameter" do
      ts_code = """
      await readTasksWithMetadata({
        fields: ["id", "title"],
        metadataFields: ["someString", "someNumber"]
      });
      """

      result = TsActionCallExtractor.extract_calls(ts_code)

      assert [call] = result
      assert call.config["fields"] == ["id", "title"]
      assert call.config["metadataFields"] == ["someString", "someNumber"]
    end

    test "handles primaryKey parameter" do
      ts_code = """
      await updateTodo({
        primaryKey: "todo-123",
        input: {title: "Updated"},
        fields: ["id", "title"]
      });
      """

      result = TsActionCallExtractor.extract_calls(ts_code)

      assert [call] = result
      assert call.config["primaryKey"] == "todo-123"
      assert call.config["input"]["title"] == "Updated"
    end

    test "handles deeply nested calculations" do
      ts_code = """
      await getTodo({
        fields: [
          "id",
          {
            self: {
              args: {prefix: "level1_"},
              fields: [
                "title",
                {
                  self: {
                    args: {prefix: "level2_"},
                    fields: [
                      "status",
                      {
                        self: {
                          args: {prefix: "level3_"},
                          fields: ["priority"]
                        }
                      }
                    ]
                  }
                }
              ]
            }
          }
        ]
      });
      """

      result = TsActionCallExtractor.extract_calls(ts_code)

      assert [call] = result
      fields = call.config["fields"]
      level1 = Enum.at(fields, 1)["self"]
      level2 = Enum.at(level1["fields"], 1)["self"]
      level3 = Enum.at(level2["fields"], 1)["self"]

      assert level1["args"]["prefix"] == "level1_"
      assert level2["args"]["prefix"] == "level2_"
      assert level3["args"]["prefix"] == "level3_"
      assert level3["fields"] == ["priority"]
    end

    test "handles union type field selection" do
      ts_code = """
      await getTodo({
        fields: [
          "id",
          {
            content: [
              "note",
              {
                text: ["id", "text", "wordCount"]
              }
            ]
          }
        ]
      });
      """

      result = TsActionCallExtractor.extract_calls(ts_code)

      assert [call] = result
      content_fields = Enum.at(call.config["fields"], 1)["content"]
      assert "note" in content_fields
      text_fields = Enum.find(content_fields, &is_map/1)["text"]
      assert text_fields == ["id", "text", "wordCount"]
    end

    test "extracts all await calls" do
      ts_code = """
      const result1 = await createTodo({fields: ["id"]});
      await updateTodo({primaryKey: "123", fields: ["id"]});
      """

      result = TsActionCallExtractor.extract_calls(ts_code)

      assert length(result) == 2
      assert Enum.at(result, 0).function_name == "createTodo"
      assert Enum.at(result, 1).function_name == "updateTodo"
    end

    test "handles multi-line formatting with various spacing" do
      ts_code = """
      await createTodo(  {
        input:   {
          title:    "Test"  ,
          status  :  "pending"
        }  ,
        fields  :  [  "id"  ,  "title"  ]
      }  )  ;
      """

      result = TsActionCallExtractor.extract_calls(ts_code)

      assert [call] = result
      assert call.config["input"]["title"] == "Test"
      assert call.config["input"]["status"] == "pending"
      assert call.config["fields"] == ["id", "title"]
    end
  end
end
