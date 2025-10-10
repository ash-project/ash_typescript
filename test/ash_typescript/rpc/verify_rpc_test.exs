defmodule AshTypescript.Rpc.VerifyRpcTest do
  use ExUnit.Case, async: true

  describe "invalid_name?/1" do
    test "returns true for names with underscores followed by digits" do
      invalid_names = [
        "field_1",
        "address_line_2",
        "item__3",
        "data___4"
      ]

      for name <- invalid_names do
        assert AshTypescript.Rpc.VerifyRpc.invalid_name?(name), "#{name} should be invalid"
      end
    end

    test "returns true for names with question marks" do
      invalid_names = [
        "field?",
        "cloaked?",
        "is_valid?"
      ]

      for name <- invalid_names do
        assert AshTypescript.Rpc.VerifyRpc.invalid_name?(name), "#{name} should be invalid"
      end
    end

    test "returns true for names with both patterns" do
      invalid_names = [
        "field_1?",
        "item_2?data",
        "test__5?"
      ]

      for name <- invalid_names do
        assert AshTypescript.Rpc.VerifyRpc.invalid_name?(name), "#{name} should be invalid"
      end
    end

    test "returns false for valid names" do
      valid_names = [
        "normal_field",
        "camelCase",
        "snake_case",
        "field1",
        "item2",
        "under_score_field",
        "field_name_without_digits"
      ]

      for name <- valid_names do
        refute AshTypescript.Rpc.VerifyRpc.invalid_name?(name), "#{name} should be valid"
      end
    end
  end

  describe "make_name_better/1" do
    test "removes underscores before digits" do
      test_cases = [
        {"field_1", "field1"},
        {"address_line_2", "address_line2"},
        {"item__3", "item3"},
        {"data___4", "data4"}
      ]

      for {input, expected} <- test_cases do
        assert AshTypescript.Rpc.VerifyRpc.make_name_better(input) == expected
      end
    end

    test "removes question marks" do
      test_cases = [
        {"field?", "field"},
        {"cloaked?", "cloaked"},
        {"is_valid?", "is_valid"}
      ]

      for {input, expected} <- test_cases do
        assert AshTypescript.Rpc.VerifyRpc.make_name_better(input) == expected
      end
    end

    test "handles combined patterns" do
      test_cases = [
        {"field_1?", "field1"},
        {"item_2?data", "item2data"},
        {"test__5?", "test5"}
      ]

      for {input, expected} <- test_cases do
        assert AshTypescript.Rpc.VerifyRpc.make_name_better(input) == expected
      end
    end

    test "leaves valid names unchanged" do
      valid_names = [
        "normal_field",
        "camelCase",
        "snake_case",
        "field1",
        "item2"
      ]

      for name <- valid_names do
        assert AshTypescript.Rpc.VerifyRpc.make_name_better(name) == name
      end
    end
  end
end
