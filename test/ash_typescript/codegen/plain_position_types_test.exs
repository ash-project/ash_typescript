# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.PlainPositionTypesTest do
  # Action metadata and alias bodies are plain data: embedded resources and
  # unions in them take the shape ash_rpc sends, never the field-selection
  # schemas with `__type` markers. Filter values are read as input, so they
  # take the input shape.
  use ExUnit.Case, async: false

  alias AshTypescript.Test.CodegenTestHelper

  setup_all do
    {:ok, content} = CodegenTestHelper.generate_all_content()
    %{content: content}
  end

  defp filter_field(content, filter_type, field) do
    [_, rest] = String.split(content, "export type #{filter_type} = {", parts: 2)
    [_, rest] = String.split(rest, "\n  #{field}?: {", parts: 2)
    rest |> String.split("\n  };", parts: 2) |> hd()
  end

  describe "filter values" do
    # A record sent over the wire gets its own generated keys and defaults, so
    # it never equals a stored one (AshRpc.Introspection.filter_value_kind/2).
    test "an embedded resource value, or an array of them, only has isNil", %{content: content} do
      assert filter_field(content, "TaskFilterInput", "metadata") == "\n    isNil?: boolean;"
      assert filter_field(content, "TodoFilterInput", "metadata") == "\n    isNil?: boolean;"

      assert filter_field(content, "TodoFilterInput", "metadataHistory") ==
               "\n    isNil?: boolean;"
    end

    test "a typed map reaching an embedded resource only has isNil", %{content: content} do
      assert filter_field(content, "TodoFilterInput", "metadataReport") ==
               "\n    isNil?: boolean;"
    end

    test "a union value is a { member: input } object per member that isn't a record", %{
      content: content
    } do
      union = filter_field(content, "TodoFilterInput", "content")

      assert union =~ "    eq?: { note: string } | { priorityValue: number };"
      assert union =~ "    in?: Array<{ note: string } | { priorityValue: number }>;"
      refute union =~ "text:"
      refute union =~ "checklist:"
      refute union =~ "__type"
    end

    test "an array of unions keeps its members that aren't records", %{content: content} do
      attachments = filter_field(content, "TodoFilterInput", "attachments")
      assert attachments =~ "    has?: { file: {filename: string, "
      assert attachments =~ " | { url: string };"
    end

    test "structured values have no ordering operators", %{content: content} do
      for {filter_type, field} <- [
            {"TaskFilterInput", "stats"},
            {"TodoFilterInput", "content"},
            {"TodoFilterInput", "options"},
            {"TodoFilterInput", "coordinates"}
          ] do
        block = filter_field(content, filter_type, field)

        assert block =~ "    eq?: "
        refute block =~ "lessThan", "#{filter_type}.#{field} has ordering operators"
        refute block =~ "greaterThan", "#{filter_type}.#{field} has ordering operators"
      end
    end

    test "declared custom types and scalars keep ordering operators", %{content: content} do
      assert filter_field(content, "TaskFilterInput", "price") =~ "    greaterThan?: Money;"
      assert filter_field(content, "TaskFilterInput", "id") =~ "    greaterThan?: UUID;"
    end

    test "a value that reaches a non-embedded resource only has isNil", %{content: content} do
      assert filter_field(content, "TodoFilterInput", "self") == "\n    isNil?: boolean;"
    end
  end

  test "alias bodies expand embedded resources plainly", %{content: content} do
    assert content =~
             "export type LineItem = {label: string, price: Money, meta: {createdBy: string, " <>
               "id: UUID, isPublic: boolean, notes: string | null, priorityLevel: number | null} | null};"

    [_, todo_ref] = String.split(content, "export type AshTypescriptTestTodoRef = ", parts: 2)
    todo_ref = todo_ref |> String.split("\n", parts: 2) |> hd()

    refute todo_ref =~ "ResourceSchema"
    refute todo_ref =~ "__type"
  end
end
