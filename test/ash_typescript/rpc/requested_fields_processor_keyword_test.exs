# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.RequestedFieldsProcessorKeywordTest do
  use ExUnit.Case, async: true

  alias AshTypescript.Rpc.RequestedFieldsProcessor
  alias AshTypescript.Test.Todo

  describe "keyword type processing" do
    test "processes keyword field in requested fields" do
      # Test that keyword fields are properly handled in field requests
      # Keyword fields require field selection syntax
      fields = ["id", "title", %{"options" => ["priority", "category", "notify"]}]

      result = RequestedFieldsProcessor.process(Todo, :read, fields)

      # Verify that the options field is included and properly structured
      assert match?({:ok, _}, result)
      {:ok, {select, _load, template}} = result

      # Check if options field is present in the select fields (first element of tuple)
      assert :options in select

      # Check if options field is properly templated (third element of tuple)
      options_template = template[:options]

      assert options_template == [:priority, :category, :notify]
    end

    test "processes nested fields with keyword types" do
      # Test complex field selection including keyword types
      fields = [
        "id",
        "title",
        %{"options" => ["priority", "category"]},
        %{"user" => ["id", "name"]}
      ]

      result = RequestedFieldsProcessor.process(Todo, :read, fields)

      assert match?({:ok, _}, result)
      {:ok, {select, load, template}} = result

      # Verify all fields are processed correctly in select
      assert :id in select
      assert :title in select
      assert :options in select

      # Verify user relationship is in load
      user_load = load[:user]

      assert user_load == [:id, :name]

      # Verify templates are correct
      options_template = template[:options]

      user_template = template[:user]

      assert options_template == [:priority, :category]
      assert user_template == [:id, :name]
    end
  end

  describe "keyword field template generation" do
    test "generates correct template for keyword field" do
      # Test what template gets generated for keyword fields
      fields = [%{"options" => ["priority", "category", "notify"]}]

      {:ok, {select, load, template}} = RequestedFieldsProcessor.process(Todo, :read, fields)

      assert select == [:options]
      assert load == []
      assert template == [options: [:priority, :category, :notify]]
    end
  end
end
