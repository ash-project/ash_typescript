# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.ResultProcessorKeywordTest do
  use ExUnit.Case, async: true

  alias AshTypescript.Rpc.ResultProcessor

  describe "keyword list handling" do
    test "converts keyword list to JSON object" do
      keyword_list = [priority: 8, category: "work", notify: true]

      result = ResultProcessor.normalize_value_for_json(keyword_list)

      expected = %{
        "priority" => 8,
        "category" => "work",
        "notify" => true
      }

      assert result == expected
    end

    test "handles empty list - preserves as array" do
      empty_list = []
      result = ResultProcessor.normalize_value_for_json(empty_list)
      assert result == []
    end

    test "handles nested keyword values" do
      keyword_list = [
        priority: 5,
        metadata: %{created_by: "user", tags: ["urgent", "work"]},
        flags: [active: true, visible: false]
      ]

      result = ResultProcessor.normalize_value_for_json(keyword_list)

      expected = %{
        "priority" => 5,
        "metadata" => %{created_by: "user", tags: ["urgent", "work"]},
        "flags" => %{"active" => true, "visible" => false}
      }

      assert result == expected
    end

    test "distinguishes keyword lists from regular lists" do
      # Regular list (not keyword)
      regular_list = [1, 2, 3, "test"]
      result1 = ResultProcessor.normalize_value_for_json(regular_list)
      assert result1 == [1, 2, 3, "test"]

      # Mixed list (not keyword) - tuples inside regular lists are preserved as tuples
      mixed_list = [{:key, "value"}, "not_tuple", 42]
      result2 = ResultProcessor.normalize_value_for_json(mixed_list)
      assert result2 == [{:key, "value"}, "not_tuple", 42]

      # Keyword list
      keyword_list = [key1: "value1", key2: "value2"]
      result3 = ResultProcessor.normalize_value_for_json(keyword_list)
      assert result3 == %{"key1" => "value1", "key2" => "value2"}
    end

    test "handles single-item keyword list" do
      keyword_list = [priority: 10]

      result = ResultProcessor.normalize_value_for_json(keyword_list)

      expected = %{"priority" => 10}

      assert result == expected
    end

    test "processes keyword list in extraction template" do
      # Simulate data with keyword field
      data = %{
        id: "123",
        title: "Test Todo",
        options: [priority: 7, category: "test", notify: false]
      }

      extraction_template = [:id, :title, :options]

      result = ResultProcessor.process(data, extraction_template)

      expected = %{
        id: "123",
        title: "Test Todo",
        options: %{
          "priority" => 7,
          "category" => "test",
          "notify" => false
        }
      }

      assert result == expected
    end

    test "preserves empty array nested inside map" do
      # This is the actual scenario from the bug report - empty arrays in JSONB columns
      # were being converted to empty objects, breaking frontend expectations.
      data = %{
        id: "123",
        title: "Test",
        tags: [],
        metadata: %{items: [], config: %{flags: []}}
      }

      result = ResultProcessor.normalize_value_for_json(data)

      # Empty arrays must remain as [] not become {}
      assert result.tags == []
      assert result.metadata.items == []
      assert result.metadata.config.flags == []
    end

    test "preserves empty arrays inside regular arrays" do
      # Nested empty arrays should also be preserved
      data = [[], [1, 2], [], [3]]

      result = ResultProcessor.normalize_value_for_json(data)

      assert result == [[], [1, 2], [], [3]]
    end

    test "processes empty array field in extraction template" do
      # Ensure empty arrays are preserved when extracting fields
      data = %{
        id: "123",
        items: []
      }

      extraction_template = [:id, :items]

      result = ResultProcessor.process(data, extraction_template)

      assert result == %{id: "123", items: []}
    end
  end
end
