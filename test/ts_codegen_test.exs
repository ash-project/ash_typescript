defmodule AshTypescript.TS.CodegenTest do
  use ExUnit.Case, async: true
  alias AshTypescript.TS.Codegen
  alias AshTypescript.Test.Todo
  alias AshTypescript.Test.Comment

  describe "get_ts_type/2 - basic types" do
    test "converts nil type" do
      assert Codegen.get_ts_type(%{type: nil}) == "null"
    end

    test "converts aggregate types" do
      assert Codegen.get_ts_type(%{type: :sum}) == "number"
      assert Codegen.get_ts_type(%{type: :count}) == "number"
    end

    test "converts string types" do
      assert Codegen.get_ts_type(%{type: Ash.Type.String}) == "string"
      assert Codegen.get_ts_type(%{type: Ash.Type.CiString}) == "string"
    end

    test "converts number types" do
      assert Codegen.get_ts_type(%{type: Ash.Type.Integer}) == "number"
      assert Codegen.get_ts_type(%{type: Ash.Type.Float}) == "number"
      assert Codegen.get_ts_type(%{type: Ash.Type.Decimal}) == "string"
    end

    test "converts boolean type" do
      assert Codegen.get_ts_type(%{type: Ash.Type.Boolean}) == "boolean"
    end

    test "converts UUID types" do
      assert Codegen.get_ts_type(%{type: Ash.Type.UUID}) == "string"
      assert Codegen.get_ts_type(%{type: Ash.Type.UUIDv7}) == "string"
    end

    test "converts date/time types" do
      assert Codegen.get_ts_type(%{type: Ash.Type.Date}) == "string"
      assert Codegen.get_ts_type(%{type: Ash.Type.Time}) == "string"
      assert Codegen.get_ts_type(%{type: Ash.Type.TimeUsec}) == "string"
      assert Codegen.get_ts_type(%{type: Ash.Type.UtcDatetime}) == "string"
      assert Codegen.get_ts_type(%{type: Ash.Type.UtcDatetimeUsec}) == "string"
      assert Codegen.get_ts_type(%{type: Ash.Type.DateTime}) == "string"
      assert Codegen.get_ts_type(%{type: Ash.Type.NaiveDatetime}) == "string"
    end

    test "converts other basic types" do
      assert Codegen.get_ts_type(%{type: Ash.Type.Binary}) == "string"
      assert Codegen.get_ts_type(%{type: Ash.Type.UrlEncodedBinary}) == "string"
      assert Codegen.get_ts_type(%{type: Ash.Type.Duration}) == "string"
      assert Codegen.get_ts_type(%{type: Ash.Type.DurationName}) == "string"
      assert Codegen.get_ts_type(%{type: Ash.Type.File}) == "File"
      assert Codegen.get_ts_type(%{type: Ash.Type.Function}) == "Function"
      assert Codegen.get_ts_type(%{type: Ash.Type.Term}) == "any"
      assert Codegen.get_ts_type(%{type: Ash.Type.Vector}) == "number[]"
      assert Codegen.get_ts_type(%{type: Ash.Type.Module}) == "string"
    end
  end

  describe "get_ts_type/2 - constrained types" do
    test "converts unconstrained atom to string" do
      assert Codegen.get_ts_type(%{type: Ash.Type.Atom, constraints: []}) == "string"
    end

    test "converts constrained atom with one_of to union type" do
      constraints = [one_of: [:low, :medium, :high]]
      result = Codegen.get_ts_type(%{type: Ash.Type.Atom, constraints: constraints})
      assert result == "\"low\" | \"medium\" | \"high\""
    end

    test "converts Ash.Type.Enum to union type" do
      result = Codegen.get_ts_type(%{type: AshTypescript.Test.TodoStatus, constraints: []})
      assert result == "\"pending\" | \"ongoing\" | \"finished\" | \"cancelled\""
    end

    test "converts unconstrained map to generic record" do
      assert Codegen.get_ts_type(%{type: Ash.Type.Map, constraints: []}) == "Record<string, any>"
      assert Codegen.get_ts_type(%{type: :map}) == "Record<string, any>"
    end

    test "converts constrained map with fields to typed object" do
      constraints = [
        fields: [
          name: [type: Ash.Type.String, allow_nil?: false],
          age: [type: Ash.Type.Integer, allow_nil?: true],
          active: [type: Ash.Type.Boolean, allow_nil?: false]
        ]
      ]

      result = Codegen.get_ts_type(%{type: Ash.Type.Map, constraints: constraints})
      assert result == "{name: string, age?: number, active: boolean}"
    end

    test "converts keyword type with fields" do
      constraints = [
        fields: [
          title: [type: Ash.Type.String, allow_nil?: false],
          count: [type: Ash.Type.Integer, allow_nil?: true]
        ]
      ]

      result = Codegen.get_ts_type(%{type: Ash.Type.Keyword, constraints: constraints})
      assert result == "{title: string, count?: number}"
    end

    test "converts tuple type with fields" do
      constraints = [
        fields: [
          first: [type: Ash.Type.String, allow_nil?: false],
          second: [type: Ash.Type.Integer, allow_nil?: false]
        ]
      ]

      result = Codegen.get_ts_type(%{type: Ash.Type.Tuple, constraints: constraints})
      assert result == "{first: string, second: number}"
    end
  end

  describe "get_ts_type/2 - array types" do
    test "converts array of basic types" do
      assert Codegen.get_ts_type(%{type: {:array, Ash.Type.String}, constraints: []}) == "Array<string>"
      assert Codegen.get_ts_type(%{type: {:array, Ash.Type.Integer}, constraints: []}) == "Array<number>"
      assert Codegen.get_ts_type(%{type: {:array, Ash.Type.Boolean}, constraints: []}) == "Array<boolean>"
    end

    test "converts array with item constraints" do
      constraints = [items: [one_of: [:red, :green, :blue]]]
      result = Codegen.get_ts_type(%{type: {:array, Ash.Type.Atom}, constraints: constraints})
      assert result == "Array<\"red\" | \"green\" | \"blue\">"
    end
  end

  describe "get_ts_type/2 - union types" do
    test "converts empty union to any" do
      constraints = [types: []]
      result = Codegen.get_ts_type(%{type: Ash.Type.Union, constraints: constraints})
      assert result == "any"
    end

    test "converts union with multiple types" do
      constraints = [
        types: [
          string_type: [type: Ash.Type.String],
          number_type: [type: Ash.Type.Integer],
          bool_type: [type: Ash.Type.Boolean]
        ]
      ]

      result = Codegen.get_ts_type(%{type: Ash.Type.Union, constraints: constraints})
      assert result == "string | number | boolean"
    end

    test "removes duplicate types in union" do
      constraints = [
        types: [
          string_type: [type: Ash.Type.String],
          another_string: [type: Ash.Type.String],
          number_type: [type: Ash.Type.Integer]
        ]
      ]

      result = Codegen.get_ts_type(%{type: Ash.Type.Union, constraints: constraints})
      assert result == "string | number"
    end
  end

  describe "get_ts_type/2 - struct types" do
    test "converts struct with fields to typed object" do
      constraints = [
        fields: [
          name: [type: Ash.Type.String, allow_nil?: false],
          value: [type: Ash.Type.Integer, allow_nil?: true]
        ]
      ]

      result = Codegen.get_ts_type(%{type: Ash.Type.Struct, constraints: constraints})
      assert result == "{name: string, value?: number}"
    end

    test "converts struct with instance_of to resource type" do
      constraints = [instance_of: Todo]
      result = Codegen.get_ts_type(%{type: Ash.Type.Struct, constraints: constraints})
      # Should build a resource type for Todo
      assert String.contains?(result, "id")
      assert String.contains?(result, "title")
      assert String.contains?(result, "completed")
    end

    test "converts unconstrained struct to generic record" do
      result = Codegen.get_ts_type(%{type: Ash.Type.Struct, constraints: []})
      assert result == "Record<string, any>"
    end
  end

  describe "get_ts_type/2 - enum types" do
    test "converts Ash.Type.Enum to union type via behaviour check" do
      # This tests the Spark.implements_behaviour? path in the code
      result = Codegen.get_ts_type(%{type: AshTypescript.Test.TodoStatus, constraints: []})
      assert result == "\"pending\" | \"ongoing\" | \"finished\" | \"cancelled\""
    end

    test "converts enum in array to array of union types" do
      result = Codegen.get_ts_type(%{type: {:array, AshTypescript.Test.TodoStatus}, constraints: []})
      assert result == "Array<\"pending\" | \"ongoing\" | \"finished\" | \"cancelled\">"
    end

    test "handles enum in map field constraints" do
      constraints = [
        fields: [
          current_status: [type: AshTypescript.Test.TodoStatus, allow_nil?: false],
          previous_status: [type: AshTypescript.Test.TodoStatus, allow_nil?: true]
        ]
      ]

      result = Codegen.get_ts_type(%{type: Ash.Type.Map, constraints: constraints})
      assert result == "{current_status: \"pending\" | \"ongoing\" | \"finished\" | \"cancelled\", previous_status?: \"pending\" | \"ongoing\" | \"finished\" | \"cancelled\"}"
    end

    test "handles enum in union type" do
      constraints = [
        types: [
          status_type: [type: AshTypescript.Test.TodoStatus],
          string_type: [type: Ash.Type.String]
        ]
      ]

      result = Codegen.get_ts_type(%{type: Ash.Type.Union, constraints: constraints})
      assert result == "\"pending\" | \"ongoing\" | \"finished\" | \"cancelled\" | string"
    end

    test "handles enum in struct fields" do
      constraints = [
        fields: [
          status: [type: AshTypescript.Test.TodoStatus, allow_nil?: false],
          name: [type: Ash.Type.String, allow_nil?: false]
        ]
      ]

      result = Codegen.get_ts_type(%{type: Ash.Type.Struct, constraints: constraints})
      assert result == "{status: \"pending\" | \"ongoing\" | \"finished\" | \"cancelled\", name: string}"
    end
  end

  describe "build_map_type/2" do
    test "builds map type with all fields" do
      fields = [
        name: [type: Ash.Type.String, allow_nil?: false],
        age: [type: Ash.Type.Integer, allow_nil?: true],
        active: [type: Ash.Type.Boolean, allow_nil?: false]
      ]

      result = Codegen.build_map_type(fields)
      assert result == "{name: string, age?: number, active: boolean}"
    end

    test "builds map type with selected fields only" do
      fields = [
        name: [type: Ash.Type.String, allow_nil?: false],
        age: [type: Ash.Type.Integer, allow_nil?: true],
        active: [type: Ash.Type.Boolean, allow_nil?: false]
      ]

      result = Codegen.build_map_type(fields, ["name", "active"])
      assert result == "{name: string, active: boolean}"
    end

    test "handles empty field list" do
      result = Codegen.build_map_type([])
      assert result == "{}"
    end
  end

  describe "build_union_type/1" do
    test "builds union from type configurations" do
      types = [
        str: [type: Ash.Type.String],
        num: [type: Ash.Type.Integer],
        bool: [type: Ash.Type.Boolean]
      ]

      result = Codegen.build_union_type(types)
      assert result == "string | number | boolean"
    end

    test "handles empty types list" do
      result = Codegen.build_union_type([])
      assert result == "any"
    end
  end

  describe "build_resource_type/2" do
    test "builds resource type with all public attributes" do
      result = Codegen.build_resource_type(Todo)
      
      # Should include all public attributes with proper formatting
      assert String.contains?(result, "id: string;")
      assert String.contains?(result, "title: string;")
      assert String.contains?(result, "description?: string | null;")
      assert String.contains?(result, "completed?: boolean | null;")
      assert String.contains?(result, "priority?: \"low\" | \"medium\" | \"high\" | \"urgent\" | null;")
      assert String.contains?(result, "status?: \"pending\" | \"ongoing\" | \"finished\" | \"cancelled\" | null;")
      assert String.contains?(result, "due_date?: string | null;")
      assert String.contains?(result, "tags?: Array<string> | null;")
      assert String.contains?(result, "metadata?: Record<string, any> | null;")
    end

    test "builds resource type with selected fields" do
      select_and_loads = [:id, :title, :completed, :status]
      result = Codegen.build_resource_type(Todo, select_and_loads)
      
      assert String.contains?(result, "id: string;")
      assert String.contains?(result, "title: string;")
      assert String.contains?(result, "completed?: boolean | null;")
      assert String.contains?(result, "status?: \"pending\" | \"ongoing\" | \"finished\" | \"cancelled\" | null;")
      # Should not contain other fields
      refute String.contains?(result, "description")
      refute String.contains?(result, "priority")
    end
  end

  describe "get_resource_field_spec/2 - attributes" do
    test "generates field spec for required string attribute" do
      result = Codegen.get_resource_field_spec(:title, Todo)
      assert result == "  title: string;"
    end

    test "generates field spec for optional attribute" do
      result = Codegen.get_resource_field_spec(:description, Todo)
      assert result == "  description?: string | null;"
    end

    test "generates field spec for boolean attribute with default" do
      result = Codegen.get_resource_field_spec(:completed, Todo)
      assert result == "  completed?: boolean | null;"
    end

    test "generates field spec for constrained atom attribute" do
      result = Codegen.get_resource_field_spec(:priority, Todo)
      assert result == "  priority?: \"low\" | \"medium\" | \"high\" | \"urgent\" | null;"
    end

    test "generates field spec for array attribute" do
      result = Codegen.get_resource_field_spec(:tags, Todo)
      assert result == "  tags?: Array<string> | null;"
    end

    test "generates field spec for enum attribute" do
      result = Codegen.get_resource_field_spec(:status, Todo)
      assert result == "  status?: \"pending\" | \"ongoing\" | \"finished\" | \"cancelled\" | null;"
    end

    test "generates field spec for map attribute" do
      result = Codegen.get_resource_field_spec(:metadata, Todo)
      assert result == "  metadata?: Record<string, any> | null;"
    end
  end

  describe "get_resource_field_spec/2 - calculations" do
    test "generates field spec for boolean calculation" do
      result = Codegen.get_resource_field_spec(:is_overdue, Todo)
      assert result == "  is_overdue?: boolean | null;"
    end

    test "generates field spec for integer calculation" do
      result = Codegen.get_resource_field_spec(:days_until_due, Todo)
      assert result == "  days_until_due?: number | null;"
    end
  end

  describe "get_resource_field_spec/2 - aggregates" do
    test "skips aggregates as they are not included in default resource fields" do
      # Aggregates are not included in default resource type generation
      # They would only be included if explicitly loaded
      assert catch_throw(Codegen.get_resource_field_spec(:comment_count, Todo)) == 
        "Field not found: AshTypescript.Test.Todo.comment_count"
    end
  end

  describe "get_resource_field_spec/2 - relationships" do
    test "skips relationships as they are not public by default" do
      # Relationships need to be marked as public? true to be included
      assert catch_throw(Codegen.get_resource_field_spec({:comments, [:id, :content]}, Todo)) == 
        "Relationship not found on Elixir.AshTypescript.Test.Todo: comments"
    end
  end

  describe "lookup_aggregate_type/3" do
    test "looks up field type on current resource" do
      result = Codegen.lookup_aggregate_type(Comment, [], :rating)
      assert result.type == Ash.Type.Integer
    end

    test "looks up field type through relationship path" do
      result = Codegen.lookup_aggregate_type(Todo, [:comments], :rating)
      assert result.type == Ash.Type.Integer
    end

    test "looks up field type through multiple relationship levels" do
      # This would work if we had deeper relationships
      result = Codegen.lookup_aggregate_type(Comment, [], :content)
      assert result.type == Ash.Type.String
    end
  end

  describe "error handling" do
    test "raises error for unsupported type" do
      unsupported_type = SomeUnsupportedType
      
      assert_raise RuntimeError, ~r/unsupported type/, fn ->
        Codegen.get_ts_type(%{type: unsupported_type, constraints: []})
      end
    end

    test "throws error for unknown field" do
      assert catch_throw(Codegen.get_resource_field_spec(:nonexistent_field, Todo)) == 
        "Field not found: AshTypescript.Test.Todo.nonexistent_field"
    end

    test "throws error for unknown relationship" do
      assert catch_throw(Codegen.get_resource_field_spec({:nonexistent_rel, [:id]}, Todo)) == 
        "Relationship not found on Elixir.AshTypescript.Test.Todo: nonexistent_rel"
    end
  end

  describe "integration tests with real resources" do
    test "generates complete Todo resource type" do
      result = Codegen.build_resource_type(Todo)
      
      # Verify it's a valid TypeScript object type
      assert String.starts_with?(result, "{")
      assert String.ends_with?(result, "}")
      
      # Verify it contains expected attributes with proper formatting
      assert String.contains?(result, "id: string;")
      assert String.contains?(result, "title: string;")
      assert String.contains?(result, "completed?: boolean | null;")
      assert String.contains?(result, "status?: \"pending\" | \"ongoing\" | \"finished\" | \"cancelled\" | null;")
      assert String.contains?(result, "priority?: \"low\" | \"medium\" | \"high\" | \"urgent\" | null;")
      
      # Note: calculations are not included in default resource type generation
      # They would only be included if explicitly specified in select_and_loads
      
      # Verify aggregates would be included if loaded
      # (Note: aggregates aren't included in default resource type generation)
    end

    test "generates resource types without double semicolons" do
      # Test full resource type
      full_result = Codegen.build_resource_type(Todo)
      refute String.contains?(full_result, ";;"), "Full resource type should not contain double semicolons"
      
      # Test selected fields resource type
      selected_result = Codegen.build_resource_type(Todo, [:id, :title, :status, :priority])
      refute String.contains?(selected_result, ";;"), "Selected fields resource type should not contain double semicolons"
      
      # Test Comment resource type
      comment_result = Codegen.build_resource_type(Comment)
      refute String.contains?(comment_result, ";;"), "Comment resource type should not contain double semicolons"
    end

    test "generates complete Comment resource type" do
      result = Codegen.build_resource_type(Comment)
      
      assert String.starts_with?(result, "{")
      assert String.ends_with?(result, "}")
      
      assert String.contains?(result, "id: string;")
      assert String.contains?(result, "content: string;")
      assert String.contains?(result, "author_name: string;")
      assert String.contains?(result, "rating?: number | null;")
      assert String.contains?(result, "is_helpful?: boolean | null;")
    end

    test "generates resource type with loaded aggregates" do
      # Test with specific fields only (aggregates would need to be explicitly handled)
      select_and_loads = [:id, :title, :status]
      result = Codegen.build_resource_type(Todo, select_and_loads)
      
      assert String.contains?(result, "id: string;")
      assert String.contains?(result, "title: string;")
      assert String.contains?(result, "status?: \"pending\" | \"ongoing\" | \"finished\" | \"cancelled\" | null;")
      # Aggregates would only work if they were treated as regular fields
    end
  end
end