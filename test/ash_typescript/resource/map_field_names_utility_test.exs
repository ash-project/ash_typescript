# SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Resource.MapFieldNamesUtilityTest do
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
        assert AshTypescript.Resource.VerifyMapFieldNames.invalid_name?(name),
               "#{name} should be invalid"
      end
    end

    test "returns true for names with question marks" do
      invalid_names = [
        "field?",
        "is_active?",
        "enabled?"
      ]

      for name <- invalid_names do
        assert AshTypescript.Resource.VerifyMapFieldNames.invalid_name?(name),
               "#{name} should be invalid"
      end
    end

    test "returns false for valid names" do
      valid_names = [
        "normal_field",
        "camelCase",
        "snake_case",
        "field1",
        "item2",
        "field_name"
      ]

      for name <- valid_names do
        refute AshTypescript.Resource.VerifyMapFieldNames.invalid_name?(name),
               "#{name} should be valid"
      end
    end
  end

  describe "make_name_better/1" do
    test "removes underscores before digits" do
      test_cases = [
        {"field_1", "field1"},
        {"address_line_2", "address_line2"},
        {"item__3", "item3"}
      ]

      for {input, expected} <- test_cases do
        assert AshTypescript.Resource.VerifyMapFieldNames.make_name_better(input) == expected
      end
    end

    test "removes question marks" do
      test_cases = [
        {"field?", "field"},
        {"is_active?", "is_active"}
      ]

      for {input, expected} <- test_cases do
        assert AshTypescript.Resource.VerifyMapFieldNames.make_name_better(input) == expected
      end
    end
  end
end
