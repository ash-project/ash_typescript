defmodule AshTypescript.Rpc.KeywordFieldValidationTest do
  use ExUnit.Case, async: true

  alias AshTypescript.Rpc.RequestedFieldsProcessor
  alias AshTypescript.Test.Todo

  describe "keyword field selection validation" do
    test "rejects keyword field without field selection" do
      # This should fail because keyword fields require field selection
      fields = ["id", "title", "options"]

      result = RequestedFieldsProcessor.process(Todo, :read, fields)

      assert {:error, {:requires_field_selection, :typed_struct, "options"}} = result
    end

    test "rejects empty keyword field selection" do
      # This should fail because empty field selection is not allowed
      fields = ["id", "title", %{"options" => []}]

      result = RequestedFieldsProcessor.process(Todo, :read, fields)

      assert {:error, _error} = result
      # The exact error might be about empty fields
    end

    test "accepts valid keyword field selection" do
      # This should succeed because we're requesting specific keyword fields
      fields = ["id", "title", %{"options" => ["priority", "category", "notify"]}]

      result = RequestedFieldsProcessor.process(Todo, :read, fields)

      assert {:ok, {select, load, template}} = result
      assert :id in select
      assert :title in select
      assert "options" in select

      # Verify that the options field has proper template structure
      options_template =
        Enum.find(template, fn
          {"options", _} -> true
          _ -> false
        end)

      assert options_template == {"options", [:priority, :category, :notify]}
    end

    test "accepts partial keyword field selection" do
      # This should succeed with only some keyword fields requested
      fields = ["id", "title", %{"options" => ["priority"]}]

      result = RequestedFieldsProcessor.process(Todo, :read, fields)

      assert {:ok, {select, _load, template}} = result
      assert :id in select
      assert :title in select
      assert "options" in select

      # Verify template only includes requested field
      options_template =
        Enum.find(template, fn
          {"options", _} -> true
          _ -> false
        end)

      assert options_template == {"options", [:priority]}
    end

    test "rejects invalid keyword field names" do
      # This should fail because 'invalid_field' doesn't exist in the options keyword definition
      fields = ["id", "title", %{"options" => ["priority", "invalid_field"]}]

      result = RequestedFieldsProcessor.process(Todo, :read, fields)

      assert {:error, {:unknown_field, :invalid_field, "typed_struct", "options.invalidField"}} =
               result
    end

    test "accepts mixed valid and validates keyword fields with other field types" do
      # This should succeed with keyword fields combined with regular fields and relationships
      fields = [
        "id",
        "title",
        %{"options" => ["priority", "category"]},
        %{"user" => ["id", "name"]},
        # tuple field
        %{"coordinates" => ["latitude", "longitude"]}
      ]

      result = RequestedFieldsProcessor.process(Todo, :read, fields)

      assert {:ok, {select, load, template}} = result

      # Verify regular fields
      assert :id in select
      assert :title in select
      assert "options" in select
      assert "coordinates" in select

      # Verify relationship is in load
      user_load =
        Enum.find(load, fn
          {"user", _} -> true
          _ -> false
        end)

      assert user_load == {"user", [:id, :name]}

      # Verify templates
      options_template =
        Enum.find(template, fn
          {"options", _} -> true
          _ -> false
        end)

      assert options_template == {"options", [:priority, :category]}

      coordinates_template =
        Enum.find(template, fn
          {"coordinates", _} -> true
          _ -> false
        end)

      assert coordinates_template == {"coordinates", [:latitude, :longitude]}

      user_template =
        Enum.find(template, fn
          {"user", _} -> true
          _ -> false
        end)

      assert user_template == {"user", [:id, :name]}
    end
  end

  describe "tuple field selection validation" do
    test "rejects tuple field without field selection" do
      # This should also fail because tuple fields require field selection
      fields = ["id", "title", "coordinates"]

      result = RequestedFieldsProcessor.process(Todo, :read, fields)

      assert {:error, {:requires_field_selection, :typed_struct, "coordinates"}} = result
    end

    test "accepts valid tuple field selection" do
      # This should succeed
      fields = ["id", "title", %{"coordinates" => ["latitude", "longitude"]}]

      result = RequestedFieldsProcessor.process(Todo, :read, fields)

      assert {:ok, {select, _load, template}} = result
      assert :id in select
      assert :title in select
      assert "coordinates" in select

      coordinates_template =
        Enum.find(template, fn
          {"coordinates", _} -> true
          _ -> false
        end)

      assert coordinates_template == {"coordinates", [:latitude, :longitude]}
    end
  end
end
