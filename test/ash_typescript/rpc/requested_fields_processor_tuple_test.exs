# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.RequestedFieldsProcessorTupleTest do
  use ExUnit.Case, async: true

  alias AshTypescript.Rpc.RequestedFieldsProcessor
  alias AshTypescript.Test.Todo

  describe "tuple type processing" do
    test "processes tuple field in requested fields" do
      # Test that tuple fields are properly handled in field requests
      # Tuple fields require field selection syntax
      fields = ["id", "title", %{"coordinates" => ["latitude", "longitude"]}]

      result = RequestedFieldsProcessor.process(Todo, :read, fields)

      assert match?({:ok, _}, result)
      {:ok, {select, _load, template}} = result

      # Check if coordinates field is present in the select fields
      assert "coordinates" in select

      # Check if coordinates field is properly templated
      coordinates_template =
        Enum.find(template, fn
          {"coordinates", _} -> true
          _ -> false
        end)

      assert coordinates_template ==
               {"coordinates",
                [
                  %{index: 0, field_name: :latitude},
                  %{index: 1, field_name: :longitude}
                ]}
    end

    test "processes nested fields with tuple types" do
      # Test complex field selection including tuple types
      fields = [
        "id",
        "title",
        %{"coordinates" => ["latitude", "longitude"]},
        %{"user" => ["id", "name"]}
      ]

      result = RequestedFieldsProcessor.process(Todo, :read, fields)

      assert match?({:ok, _}, result)
      {:ok, {select, load, template}} = result

      # Verify all fields are processed correctly in select
      assert :id in select
      assert :title in select
      assert "coordinates" in select

      # Verify user relationship is in load
      user_load =
        Enum.find(load, fn
          {"user", _} -> true
          _ -> false
        end)

      assert user_load == {"user", [:id, :name]}

      # Verify templates are correct
      coordinates_template =
        Enum.find(template, fn
          {"coordinates", _} -> true
          _ -> false
        end)

      user_template =
        Enum.find(template, fn
          {"user", _} -> true
          _ -> false
        end)

      assert coordinates_template ==
               {"coordinates",
                [
                  %{index: 0, field_name: :latitude},
                  %{index: 1, field_name: :longitude}
                ]}

      assert user_template == {"user", [:id, :name]}
    end
  end

  describe "tuple field template generation" do
    test "generates correct template for tuple field" do
      # Test what template gets generated for tuple fields
      fields = [%{"coordinates" => ["latitude", "longitude"]}]

      {:ok, {select, load, template}} = RequestedFieldsProcessor.process(Todo, :read, fields)

      assert select == ["coordinates"]
      assert load == []

      assert template == [
               {"coordinates",
                [
                  %{index: 0, field_name: :latitude},
                  %{index: 1, field_name: :longitude}
                ]}
             ]
    end
  end
end
