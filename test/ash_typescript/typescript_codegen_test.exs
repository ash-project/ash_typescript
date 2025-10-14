# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.CodegenTest do
  use ExUnit.Case, async: false
  alias AshTypescript.Codegen

  alias AshTypescript.Test.{Todo, TodoComment}

  describe "get_ts_type/2 - basic types" do
    test "converts nil type" do
      assert Codegen.get_ts_type(%{type: nil}) == "null"
    end

    test "converts aggregate types" do
      assert Codegen.get_ts_type(%{type: :count}) == "number"
      assert Codegen.get_ts_type(%{type: :sum}) == "number"
    end

    test "converts string types" do
      assert Codegen.get_ts_type(%{type: Ash.Type.String}) == "string"
      assert Codegen.get_ts_type(%{type: Ash.Type.CiString}) == "string"
    end

    test "converts number types" do
      assert Codegen.get_ts_type(%{type: Ash.Type.Integer}) == "number"
      assert Codegen.get_ts_type(%{type: Ash.Type.Float}) == "number"
      assert Codegen.get_ts_type(%{type: Ash.Type.Decimal}) == "Decimal"
    end

    test "converts boolean type" do
      assert Codegen.get_ts_type(%{type: Ash.Type.Boolean}) == "boolean"
    end

    test "converts UUID types" do
      assert Codegen.get_ts_type(%{type: Ash.Type.UUID}) == "UUID"
      assert Codegen.get_ts_type(%{type: Ash.Type.UUIDv7}) == "UUIDv7"
    end

    test "converts date/time types" do
      assert Codegen.get_ts_type(%{type: Ash.Type.Date}) == "AshDate"
      assert Codegen.get_ts_type(%{type: Ash.Type.Time}) == "Time"
      assert Codegen.get_ts_type(%{type: Ash.Type.DateTime}) == "DateTime"
      assert Codegen.get_ts_type(%{type: Ash.Type.UtcDatetime}) == "UtcDateTime"
      assert Codegen.get_ts_type(%{type: Ash.Type.UtcDatetimeUsec}) == "UtcDateTimeUsec"
      assert Codegen.get_ts_type(%{type: Ash.Type.NaiveDatetime}) == "NaiveDateTime"
    end

    test "converts other basic types" do
      assert Codegen.get_ts_type(%{type: Ash.Type.Binary}) == "Binary"
      assert Codegen.get_ts_type(%{type: Ash.Type.UrlEncodedBinary}) == "UrlEncodedBinary"
      assert Codegen.get_ts_type(%{type: Ash.Type.Term}) == "any"
      assert Codegen.get_ts_type(%{type: Ash.Type.Vector}) == "number[]"
      assert Codegen.get_ts_type(%{type: Ash.Type.Module}) == "ModuleName"
    end
  end

  describe "get_ts_type/2 - constrained types" do
    test "converts unconstrained atom to string" do
      assert Codegen.get_ts_type(%{type: Ash.Type.Atom, constraints: []}) == "string"
    end

    test "converts constrained atom with one_of to union type" do
      constraints = [one_of: [:pending, :completed]]
      result = Codegen.get_ts_type(%{type: Ash.Type.Atom, constraints: constraints})
      assert result == "\"pending\" | \"completed\""
    end

    test "converts Ash.Type.Enum to union type" do
      result = Codegen.get_ts_type(%{type: AshTypescript.Test.Todo.Status, constraints: []})
      assert result == "\"pending\" | \"ongoing\" | \"finished\" | \"cancelled\""
    end

    test "converts unconstrained map to generic record" do
      result = Codegen.get_ts_type(%{type: Ash.Type.Map, constraints: []})
      assert result == "Record<string, any>"
    end

    test "converts constrained map with fields to typed object" do
      constraints = [
        fields: [
          name: [type: :string, allow_nil?: false],
          age: [type: :integer, allow_nil?: true]
        ]
      ]

      result = Codegen.get_ts_type(%{type: Ash.Type.Map, constraints: constraints})

      assert result ==
               "{name: string, age: number | null, __type: \"TypedMap\", __primitiveFields: \"name\" | \"age\"}"
    end

    test "converts keyword type with fields" do
      constraints = [
        fields: [
          key1: [type: :string, allow_nil?: false],
          key2: [type: :boolean, allow_nil?: true]
        ]
      ]

      result = Codegen.get_ts_type(%{type: Ash.Type.Keyword, constraints: constraints})

      assert result ==
               "{key1: string, key2: boolean | null, __type: \"TypedMap\", __primitiveFields: \"key1\" | \"key2\"}"
    end

    test "converts tuple type with fields" do
      constraints = [
        fields: [
          first: [type: :string, allow_nil?: false],
          second: [type: :integer, allow_nil?: false]
        ]
      ]

      result = Codegen.get_ts_type(%{type: Ash.Type.Tuple, constraints: constraints})

      assert result ==
               "{first: string, second: number, __type: \"TypedMap\", __primitiveFields: \"first\" | \"second\"}"
    end
  end

  describe "get_ts_type/2 - array types" do
    test "converts array of basic types" do
      result = Codegen.get_ts_type(%{type: {:array, Ash.Type.String}, constraints: []})
      assert result == "Array<string>"
    end

    test "converts array with item constraints" do
      result = Codegen.get_ts_type(%{type: {:array, Ash.Type.Integer}, constraints: []})
      assert result == "Array<number>"
    end
  end

  describe "get_ts_type/2 - union types" do
    test "converts empty union to any" do
      constraints = [types: []]
      result = Codegen.get_ts_type(%{type: Ash.Type.Union, constraints: constraints})
      assert result == "{ __type: \"Union\"; __primitiveFields: never; }"
    end

    test "converts union with multiple types" do
      constraints = [
        types: [
          string: [type: :string, constraints: []],
          integer: [type: :integer, constraints: []]
        ]
      ]

      result = Codegen.get_ts_type(%{type: Ash.Type.Union, constraints: constraints})

      assert result ==
               "{ __type: \"Union\"; __primitiveFields: \"string\" | \"integer\"; string?: string; integer?: number; }"
    end

    test "removes duplicate types in union" do
      constraints = [
        types: [
          string1: [type: :string, constraints: []],
          string2: [type: :string, constraints: []],
          integer: [type: :integer, constraints: []]
        ]
      ]

      result = Codegen.get_ts_type(%{type: Ash.Type.Union, constraints: constraints})

      assert result ==
               "{ __type: \"Union\"; __primitiveFields: \"string1\" | \"string2\" | \"integer\"; string1?: string; string2?: string; integer?: number; }"
    end
  end

  describe "get_ts_type/2 - struct types" do
    test "converts struct with fields to typed object" do
      constraints = [
        fields: [
          name: [type: :string, allow_nil?: false],
          active: [type: :boolean, allow_nil?: true]
        ]
      ]

      result = Codegen.get_ts_type(%{type: Ash.Type.Struct, constraints: constraints})

      assert result ==
               "{name: string, active: boolean | null, __type: \"TypedMap\", __primitiveFields: \"name\" | \"active\"}"
    end

    test "converts struct with instance_of to resource type" do
      constraints = [instance_of: Todo]
      result = Codegen.get_ts_type(%{type: Ash.Type.Struct, constraints: constraints})
      assert String.contains?(result, "TodoResourceSchema")
    end

    test "converts unconstrained struct to generic record" do
      result = Codegen.get_ts_type(%{type: Ash.Type.Struct, constraints: []})
      assert result == "Record<string, any>"
    end
  end

  describe "get_ts_type/2 - enum types" do
    test "converts Ash.Type.Enum to union type via behaviour check" do
      result = Codegen.get_ts_type(%{type: AshTypescript.Test.Todo.Status, constraints: []})
      assert result == "\"pending\" | \"ongoing\" | \"finished\" | \"cancelled\""
    end

    test "converts enum in array to array of union types" do
      result =
        Codegen.get_ts_type(%{type: {:array, AshTypescript.Test.Todo.Status}, constraints: []})

      assert result == "Array<\"pending\" | \"ongoing\" | \"finished\" | \"cancelled\">"
    end

    test "handles enum in map field constraints" do
      constraints = [
        fields: [
          status: [type: AshTypescript.Test.Todo.Status, allow_nil?: false]
        ]
      ]

      result = Codegen.get_ts_type(%{type: Ash.Type.Map, constraints: constraints})

      assert result ==
               "{status: \"pending\" | \"ongoing\" | \"finished\" | \"cancelled\", __type: \"TypedMap\", __primitiveFields: \"status\"}"
    end

    test "handles enum in union type" do
      constraints = [
        types: [
          status: [type: AshTypescript.Test.Todo.Status, constraints: []],
          string: [type: :string, constraints: []]
        ]
      ]

      result = Codegen.get_ts_type(%{type: Ash.Type.Union, constraints: constraints})
      assert String.contains?(result, "pending")
      assert String.contains?(result, "string")
    end

    test "handles enum in struct fields" do
      constraints = [
        fields: [
          status: [type: AshTypescript.Test.Todo.Status, allow_nil?: false],
          name: [type: :string, allow_nil?: false]
        ]
      ]

      result = Codegen.get_ts_type(%{type: Ash.Type.Struct, constraints: constraints})
      assert String.contains?(result, "pending")
      assert String.contains?(result, "name: string")
    end
  end

  describe "build_map_type/2" do
    test "builds map type with all fields" do
      fields = [
        name: [type: :string, allow_nil?: false],
        age: [type: :integer, allow_nil?: true]
      ]

      result = Codegen.build_map_type(fields)

      assert result ==
               "{name: string, age: number | null, __type: \"TypedMap\", __primitiveFields: \"name\" | \"age\"}"
    end

    test "builds map type with selected fields only" do
      fields = [
        name: [type: :string, allow_nil?: false],
        age: [type: :integer, allow_nil?: true],
        email: [type: :string, allow_nil?: false]
      ]

      result = Codegen.build_map_type(fields, ["name", "age"])

      assert result ==
               "{name: string, age: number | null, __type: \"TypedMap\", __primitiveFields: \"name\" | \"age\"}"
    end

    test "handles empty field list" do
      result = Codegen.build_map_type([])
      assert result == "{, __type: \"TypedMap\", __primitiveFields: never}"
    end
  end

  describe "build_union_type/1" do
    test "builds union from type configurations" do
      types = [
        string: [type: :string, constraints: []],
        integer: [type: :integer, constraints: []]
      ]

      result = Codegen.build_union_type(types)

      assert result ==
               "{ __type: \"Union\"; __primitiveFields: \"string\" | \"integer\"; string?: string; integer?: number; }"
    end

    test "handles empty types list" do
      result = Codegen.build_union_type([])
      assert result == "{ __type: \"Union\"; __primitiveFields: never; }"
    end
  end

  describe "build_resource_type/2" do
    test "builds resource type with all public attributes" do
      result = Codegen.build_resource_type(Todo)

      assert String.contains?(result, "id: UUID;")
      assert String.contains?(result, "title: string;")
      assert String.contains?(result, "description: string | null;")
      assert String.contains?(result, "completed: boolean | null;")

      assert String.contains?(
               result,
               "status: \"pending\" | \"ongoing\" | \"finished\" | \"cancelled\" | null;"
             )
    end

    test "builds resource type with selected fields" do
      result = Codegen.build_resource_type(Todo, [:id, :title, :completed, :status])

      assert String.contains?(result, "id: UUID;")
      assert String.contains?(result, "title: string;")
      assert String.contains?(result, "completed: boolean | null;")

      assert String.contains?(
               result,
               "status: \"pending\" | \"ongoing\" | \"finished\" | \"cancelled\" | null;"
             )
    end
  end

  describe "get_resource_field_spec/2 - attributes" do
    test "generates field spec for required string attribute" do
      result = Codegen.get_resource_field_spec(:title, Todo)
      assert result == "  title: string;"
    end

    test "generates field spec for optional attribute" do
      result = Codegen.get_resource_field_spec(:description, Todo)
      assert result == "  description: string | null;"
    end

    test "generates field spec for boolean attribute with default" do
      result = Codegen.get_resource_field_spec(:completed, Todo)
      assert result == "  completed: boolean | null;"
    end

    test "generates field spec for constrained atom attribute" do
      result = Codegen.get_resource_field_spec(:status, Todo)

      assert result ==
               "  status: \"pending\" | \"ongoing\" | \"finished\" | \"cancelled\" | null;"
    end

    test "generates field spec for array attribute" do
      result = Codegen.get_resource_field_spec(:tags, Todo)
      assert result == "  tags: Array<string> | null;"
    end

    test "generates field spec for enum attribute" do
      result = Codegen.get_resource_field_spec(:priority, Todo)
      assert result == "  priority: \"low\" | \"medium\" | \"high\" | \"urgent\" | null;"
    end

    test "generates field spec for embedded resource attribute" do
      result = Codegen.get_resource_field_spec(:metadata, Todo)
      assert result == "  metadata: TodoMetadataResourceSchema | null;"
    end
  end

  describe "get_resource_field_spec/2 - calculations" do
    test "generates field spec for boolean calculation" do
      result = Codegen.get_resource_field_spec(:is_overdue, Todo)
      assert result == "  isOverdue: boolean | null;"
    end

    test "generates field spec for integer calculation" do
      result = Codegen.get_resource_field_spec(:days_until_due, Todo)
      assert result == "  daysUntilDue: number | null;"
    end
  end

  describe "get_resource_field_spec/2 - aggregates" do
    test "generates field spec for count aggregate" do
      result = Codegen.get_resource_field_spec(:comment_count, Todo)
      assert result == "  commentCount: number;"
    end
  end

  describe "get_resource_field_spec/2 - relationships" do
    test "throws error for non-public relationships" do
      assert catch_throw(Codegen.get_resource_field_spec({:private_items, [:id, :content]}, Todo)) ==
               "Relationship not found on AshTypescript.Test.Todo: private_items"
    end
  end

  describe "lookup_aggregate_type/3" do
    test "looks up field type on current resource" do
      result = Codegen.lookup_aggregate_type(Todo, [], :title)
      assert result.type == Ash.Type.String
    end

    test "looks up field type through relationship path" do
      result = Codegen.lookup_aggregate_type(Todo, [:comments], :content)
      assert result.type == Ash.Type.String
    end

    test "looks up field type through multiple relationship levels" do
      result = Codegen.lookup_aggregate_type(Todo, [:comments], :rating)
      assert result.type == Ash.Type.Integer
    end
  end

  describe "error handling" do
    test "raises error for unsupported type" do
      unsupported_type = MyApp.CustomUnsupportedType

      assert_raise RuntimeError, ~r/unsupported type/, fn ->
        Codegen.get_ts_type(%{type: unsupported_type, constraints: []})
      end
    end

    test "throws error for unknown field" do
      assert catch_throw(Codegen.get_resource_field_spec(:unknown_field, Todo)) ==
               "Field not found: AshTypescript.Test.Todo.unknown_field"
    end

    test "throws error for unknown relationship" do
      assert catch_throw(Codegen.get_resource_field_spec({:unknown_rel, [:id]}, Todo)) ==
               "Relationship not found on AshTypescript.Test.Todo: unknown_rel"
    end
  end

  describe "integration tests with real resources" do
    test "generates complete Todo resource type" do
      result = Codegen.build_resource_type(Todo)

      assert String.contains?(result, "id: UUID;")
      assert String.contains?(result, "title: string;")
      assert String.contains?(result, "description: string | null;")
      assert String.contains?(result, "completed: boolean | null;")

      assert String.contains?(
               result,
               "status: \"pending\" | \"ongoing\" | \"finished\" | \"cancelled\" | null;"
             )

      assert String.contains?(
               result,
               "priority: \"low\" | \"medium\" | \"high\" | \"urgent\" | null;"
             )

      assert String.contains?(result, "dueDate: AshDate | null;")
      assert String.contains?(result, "tags: Array<string> | null;")
      assert String.contains?(result, "metadata: TodoMetadataResourceSchema | null;")

      assert String.contains?(
               result,
               "metadataHistory: Array<TodoMetadataResourceSchema> | null;"
             )

      assert String.contains?(result, "userId: UUID;")
    end

    test "generates complete TodoComment resource type" do
      result = Codegen.build_resource_type(TodoComment)

      assert String.contains?(result, "id: UUID;")
      assert String.contains?(result, "content: string;")
      assert String.contains?(result, "authorName: string;")
      assert String.contains?(result, "rating: number | null;")
      assert String.contains?(result, "isHelpful: boolean | null;")
      assert String.contains?(result, "todoId: UUID;")
      assert String.contains?(result, "userId: UUID;")
    end

    test "generates resource type with loaded aggregates" do
      result = Codegen.build_resource_type(Todo, [:id, :title, :status])

      assert String.contains?(result, "id: UUID;")
      assert String.contains?(result, "title: string;")

      assert String.contains?(
               result,
               "status: \"pending\" | \"ongoing\" | \"finished\" | \"cancelled\" | null;"
             )
    end
  end
end
