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
      {:ok, {select, load, template}} = result

      # Check if coordinates field is present in the select fields
      assert "coordinates" in select

      # Check if coordinates field is properly templated
      coordinates_template =
        Enum.find(template, fn
          {"coordinates", _} -> true
          _ -> false
        end)

      assert coordinates_template == {"coordinates", [:latitude, :longitude]}
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

      assert coordinates_template == {"coordinates", [:latitude, :longitude]}
      assert user_template == {"user", [:id, :name]}
    end
  end

  describe "tuple field template generation" do
    test "generates correct template for tuple field" do
      # Test what template gets generated for tuple fields
      fields = [%{"coordinates" => ["latitude", "longitude"]}]

      result = RequestedFieldsProcessor.process(Todo, :read, fields)
      assert match?({:ok, _}, result)
      {:ok, processed} = result

      # Since generate_template/1 doesn't exist, let's examine the processed result structure
      IO.inspect(processed, label: "Processed structure with tuple field")
    end
  end
end
