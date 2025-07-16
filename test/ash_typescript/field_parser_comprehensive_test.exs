defmodule AshTypescript.FieldParserComprehensiveTest do
  use ExUnit.Case
  alias AshTypescript.Test.{Todo, TodoMetadata}

  @moduledoc """
  Comprehensive test for the new tree traversal field processing approach.

  This test covers all field types and scenarios for the new parse_requested_fields/3 function.
  According to the design document, we will focus EXCLUSIVELY on making this test pass
  throughout the implementation process, ignoring all other tests until core implementation
  is complete.
  """

  describe "Comprehensive Field Selection with New Parse Requested Fields Approach" do
    test "parse_requested_fields separates select and load correctly" do
      # Test the core function directly once it's implemented
      formatter = :camel_case

      # Test field specification that requires proper separation
      fields = [
        # Simple attribute -> select
        "id",
        # Simple attribute -> select
        "title",
        # Simple calculation -> load
        "isOverdue",
        # Relationship -> load
        %{"user" => ["name", "email"]},
        # Embedded -> load
        %{"metadata" => ["category", "displayCategory"]}
      ]

      # Call the new function
      {select_fields, load_statements, calculation_specs} =
        AshTypescript.Rpc.FieldParser.parse_requested_fields(fields, Todo, formatter)

      # Verify correct separation
      assert :id in select_fields
      assert :title in select_fields
      assert :metadata in select_fields
      assert :is_overdue in load_statements
      assert {:user, [:name, :email]} in load_statements
      assert {:metadata, [:display_category]} in load_statements

      # Verify simple attributes are NOT in load
      refute :id in Enum.flat_map(load_statements, fn
               {_key, nested} when is_list(nested) -> nested
               item -> [item]
             end)

      # Verify calculation specs are returned (should be empty for now since no complex calculations)
      assert is_map(calculation_specs)
    end

    test "embedded resource field classification works correctly" do
      # Test that metadata field is correctly classified as embedded resource
      classification = AshTypescript.Rpc.FieldParser.classify_field(:metadata, Todo)
      assert classification == :embedded_resource

      # Test that regular attributes are classified correctly
      classification = AshTypescript.Rpc.FieldParser.classify_field(:title, Todo)
      assert classification == :simple_attribute

      # Test that relationships are classified correctly
      classification = AshTypescript.Rpc.FieldParser.classify_field(:user, Todo)
      assert classification == :relationship

      # Test that calculations are classified correctly
      classification = AshTypescript.Rpc.FieldParser.classify_field(:is_overdue, Todo)
      assert classification == :simple_calculation
    end

    test "recursive processing handles nested embedded calculations" do
      # Test that nested embedded calculations are processed correctly
      formatter = :camel_case

      # Complex nested specification
      nested_fields = ["category", "displayCategory", "priorityScore"]

      context = AshTypescript.Rpc.FieldParser.Context.new(Todo, formatter)

      result =
        AshTypescript.Rpc.FieldParser.process_embedded_fields(
          TodoMetadata,
          nested_fields,
          context
        )

      # Should return load statements for embedded calculations
      assert is_list(result)
      assert :display_category in result

      # Simple attributes should be included for embedded resources
      # (embedded resources load complete objects, then field selection is applied)
    end
  end

  describe "Field Type Detection Validation" do
    test "simple attributes are detected correctly" do
      # Verify that Todo simple attributes are detected
      assert AshTypescript.Rpc.FieldParser.is_simple_attribute?(:id, Todo)
      assert AshTypescript.Rpc.FieldParser.is_simple_attribute?(:title, Todo)
      assert AshTypescript.Rpc.FieldParser.is_simple_attribute?(:completed, Todo)

      # Verify that non-attributes are NOT detected as simple attributes
      refute AshTypescript.Rpc.FieldParser.is_simple_attribute?(:user, Todo)
      refute AshTypescript.Rpc.FieldParser.is_simple_attribute?(:is_overdue, Todo)

      # Note: :metadata IS a simple attribute (it's an embedded resource attribute)
      # but it gets classified as :embedded_resource due to our classification order
      assert AshTypescript.Rpc.FieldParser.is_simple_attribute?(:metadata, Todo)
    end

    test "relationships are detected correctly" do
      assert AshTypescript.Rpc.FieldParser.is_relationship?(:user, Todo)

      # Verify that non-relationships are NOT detected as relationships
      refute AshTypescript.Rpc.FieldParser.is_relationship?(:title, Todo)
      refute AshTypescript.Rpc.FieldParser.is_relationship?(:is_overdue, Todo)
      refute AshTypescript.Rpc.FieldParser.is_relationship?(:metadata, Todo)
    end

    test "embedded resources are detected correctly" do
      assert AshTypescript.Rpc.FieldParser.is_embedded_resource_field?(:metadata, Todo)

      # Verify that non-embedded fields are NOT detected as embedded resources
      refute AshTypescript.Rpc.FieldParser.is_embedded_resource_field?(:title, Todo)
      refute AshTypescript.Rpc.FieldParser.is_embedded_resource_field?(:user, Todo)
      refute AshTypescript.Rpc.FieldParser.is_embedded_resource_field?(:is_overdue, Todo)
    end

    test "calculations are detected correctly" do
      assert AshTypescript.Rpc.FieldParser.is_calculation?(:is_overdue, Todo)

      # Test embedded resource calculations
      assert AshTypescript.Rpc.FieldParser.is_calculation?(:display_category, TodoMetadata)
      assert AshTypescript.Rpc.FieldParser.is_calculation?(:is_overdue, TodoMetadata)

      # Verify that non-calculations are NOT detected as calculations
      refute AshTypescript.Rpc.FieldParser.is_calculation?(:title, Todo)
      refute AshTypescript.Rpc.FieldParser.is_calculation?(:user, Todo)
      refute AshTypescript.Rpc.FieldParser.is_calculation?(:metadata, Todo)
    end
  end

  describe "Load Statement Building Validation" do
    test "load statements are built in correct Ash format" do
      # Test simple calculation load
      result =
        AshTypescript.Rpc.FieldParser.build_load_statement(
          :simple_calculation,
          :display_name,
          nil,
          Todo
        )

      assert result == :display_name

      # Test relationship load
      result =
        AshTypescript.Rpc.FieldParser.build_load_statement(
          :relationship,
          :user,
          [:name, :email],
          Todo
        )

      assert result == {:user, [:name, :email]}

      # Test embedded resource load
      result =
        AshTypescript.Rpc.FieldParser.build_load_statement(
          :embedded_resource,
          :metadata,
          [:display_category, :is_overdue],
          Todo
        )

      assert result == {:metadata, [:display_category, :is_overdue]}
    end
  end
end
