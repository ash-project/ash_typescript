# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.ErrorFormatterTest do
  use ExUnit.Case, async: true

  @moduletag :ash_typescript

  alias AshTypescript.ErrorFormatter

  doctest AshTypescript.ErrorFormatter

  describe "placeholder rewriting" do
    test "renames placeholders to match renamed vars keys" do
      error = %{
        message: "RPC action %{action_name} not found",
        short_message: "Action not found",
        vars: %{action_name: "list_todos"}
      }

      assert %{
               "message" => "RPC action %{actionName} not found",
               "shortMessage" => "Action not found",
               "vars" => %{"actionName" => "list_todos"}
             } = ErrorFormatter.format(error, :camel_case)
    end

    test "rewrites every placeholder in a message with several vars" do
      error = %{
        message: "%{field_type} %{field} requires field selection",
        vars: %{field_type: "Relationship", field: "user"}
      }

      assert %{"message" => "%{fieldType} %{field} requires field selection"} =
               ErrorFormatter.format(error, :camel_case)
    end

    test "rewrites placeholders inside details strings" do
      error = %{
        message: "Union input map does not contain any valid member key",
        vars: %{expected_members: "text, file"},
        details: %{
          suggestion: "Provide exactly one of the following keys: %{expected_members}",
          hint: "no placeholder here"
        }
      }

      assert %{
               "details" => %{
                 "suggestion" => "Provide exactly one of the following keys: %{expectedMembers}",
                 "hint" => "no placeholder here"
               }
             } = ErrorFormatter.format(error, :camel_case)
    end

    test "treats details keys as a dictionary too" do
      error = %{
        message: "boom",
        details: %{field_spec: "x", suggestion: "check %{field_spec}"}
      }

      assert %{"details" => %{"suggestion" => "check %{fieldSpec}", "fieldSpec" => "x"}} =
               ErrorFormatter.format(error, :camel_case)
    end

    test "leaves placeholders alone when they name no dictionary key" do
      error = %{message: "literally %{not_a_var} here", vars: %{field: "x"}}

      assert %{"message" => "literally %{not_a_var} here"} =
               ErrorFormatter.format(error, :camel_case)
    end

    test "does not rewrite values inside vars" do
      error = %{message: "%{action_name}", vars: %{action_name: "%{action_name}"}}

      assert %{"vars" => %{"actionName" => "%{action_name}"}} =
               ErrorFormatter.format(error, :camel_case)
    end

    test "single-pass rewrite cannot rewrite an already-renamed placeholder" do
      # `a_b` -> `aB`; if the rewrite chained, `aB` would then be matched again.
      error = %{message: "%{a_b} and %{aB}", vars: %{a_b: 1, aB: 2}}

      assert %{"message" => "%{aB} and %{aB}"} = ErrorFormatter.format(error, :camel_case)
    end
  end

  describe "formatter variants" do
    test "pascal_case renames keys and placeholders" do
      error = %{message: "RPC action %{action_name} not found", vars: %{action_name: "x"}}

      assert %{
               "Message" => "RPC action %{ActionName} not found",
               "Vars" => %{"ActionName" => "x"}
             } = ErrorFormatter.format(error, :pascal_case)
    end

    test "snake_case is a no-op for already snake_case errors" do
      error = %{message: "RPC action %{action_name} not found", vars: %{action_name: "x"}}

      assert %{
               "message" => "RPC action %{action_name} not found",
               "vars" => %{"action_name" => "x"}
             } = ErrorFormatter.format(error, :snake_case)
    end
  end

  describe "pass-through" do
    test "errors with no dictionaries are only key-formatted" do
      assert %{"message" => "is required", "shortMessage" => "Required field"} =
               ErrorFormatter.format(
                 %{message: "is required", short_message: "Required field"},
                 :camel_case
               )
    end

    test "non-maps are returned unchanged" do
      assert ErrorFormatter.format("boom", :camel_case) == "boom"
      assert ErrorFormatter.format(nil, :camel_case) == nil
    end

    test "vars values that are not strings survive" do
      error = %{message: "at least %{min_length}", vars: %{min_length: 3, allowed: ["a", "b"]}}

      assert %{
               "message" => "at least %{minLength}",
               "vars" => %{"minLength" => 3, "allowed" => ["a", "b"]}
             } = ErrorFormatter.format(error, :camel_case)
    end
  end
end
