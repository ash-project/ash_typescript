# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.ManageRelationshipInputTest do
  @moduledoc """
  Verifies that `:map` (and `{:array, :map}`) arguments driven by a
  `manage_relationship` change are rendered as typed TypeScript objects
  instead of falling back to `Record<string, any>`.
  """
  use ExUnit.Case, async: false

  setup do
    Application.put_env(:ash_typescript, :enable_namespace_files, false)
    :ok
  end

  setup_all do
    {:ok, generated_content} = AshTypescript.Test.CodegenTestHelper.generate_all_content()
    {:ok, generated: generated_content}
  end

  describe "map argument backed by manage_relationship change" do
    test "update action's :item arg resolves to typed fields from destination actions", %{
      generated: generated
    } do
      input_type = extract_input_type(generated, "UpdateContentInput")

      assert input_type, "UpdateContentInput type should be defined"

      refute input_type =~ ~r/item\??: Record<string, any>/,
             "item should no longer fall back to Record<string, any>\nGot: #{input_type}"

      assert input_type =~ "heroImageUrl",
             "item should be a typed object including Article fields.\nGot: #{input_type}"

      assert input_type =~ "heroImageAlt"
      assert input_type =~ "summary"
      assert input_type =~ "body"
    end
  end

  describe "non-map argument backed by manage_relationship change" do
    test "uuid argument keeps its primitive type (no override)", %{generated: generated} do
      # TodoComment.create has `argument :user_id, :uuid` with a
      # `manage_relationship(:user_id, :user, type: :append)` change.
      input_type = extract_input_type(generated, "CreateTodoCommentInput")

      assert input_type, "CreateTodoCommentInput type should be defined"
      assert input_type =~ "userId: UUID;"
      refute input_type =~ ~r/userId\??: \{/
    end
  end

  # Extracts a TypeScript `export type Name = { ... };` block, handling nested
  # braces that naive `[^}]+` regexes stop short of.
  defp extract_input_type(generated, name) do
    prefix = "export type #{name} = "
    [_, tail] = String.split(generated, prefix, parts: 2)
    read_balanced_block(tail)
  rescue
    MatchError -> nil
  end

  defp read_balanced_block(string) do
    {acc, _depth} =
      Enum.reduce_while(String.graphemes(string), {"", 0}, fn
        "{", {acc, depth} -> {:cont, {acc <> "{", depth + 1}}
        "}", {acc, 1} -> {:halt, {acc <> "}", 0}}
        "}", {acc, depth} -> {:cont, {acc <> "}", depth - 1}}
        char, {acc, depth} -> {:cont, {acc <> char, depth}}
      end)

    acc
  end
end
