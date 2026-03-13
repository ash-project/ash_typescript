defmodule AshApiSpec.CodegenTypeDispatchTest do
  @moduledoc """
  Tests that TypeMapper and ResourceSchemas correctly handle %AshApiSpec.Type{}
  dispatch heads, producing identical results to the existing {type, constraints} path.
  """
  use ExUnit.Case, async: true

  alias AshApiSpec.Type
  alias AshTypescript.Codegen.TypeMapper
  alias AshTypescript.Codegen.ResourceSchemas

  # ─────────────────────────────────────────────────────────────────
  # TypeMapper.map_type(%Type{}, _, direction)
  # ─────────────────────────────────────────────────────────────────

  describe "TypeMapper.map_type/3 with %Type{} - primitives" do
    test "string kind maps to string" do
      type = %Type{kind: :string, name: "String", module: Ash.Type.String, constraints: []}
      assert TypeMapper.map_type(type, [], :output) == "string"
    end

    test "integer kind maps to number" do
      type = %Type{kind: :integer, name: "Integer", module: Ash.Type.Integer, constraints: []}
      assert TypeMapper.map_type(type, [], :output) == "number"
    end

    test "float kind maps to number" do
      type = %Type{kind: :float, name: "Float", module: Ash.Type.Float, constraints: []}
      assert TypeMapper.map_type(type, [], :output) == "number"
    end

    test "decimal kind maps to Decimal" do
      type = %Type{kind: :decimal, name: "Decimal", module: Ash.Type.Decimal, constraints: []}
      assert TypeMapper.map_type(type, [], :output) == "Decimal"
    end

    test "boolean kind maps to boolean" do
      type = %Type{kind: :boolean, name: "Boolean", module: Ash.Type.Boolean, constraints: []}
      assert TypeMapper.map_type(type, [], :output) == "boolean"
    end

    test "uuid kind maps to UUID" do
      type = %Type{kind: :uuid, name: "UUID", module: Ash.Type.UUID, constraints: []}
      assert TypeMapper.map_type(type, [], :output) == "UUID"
    end

    test "uuid kind for UUIDv7 maps to UUIDv7" do
      type = %Type{kind: :uuid, name: "UUIDv7", module: Ash.Type.UUIDv7, constraints: []}
      assert TypeMapper.map_type(type, [], :output) == "UUIDv7"
    end

    test "date kind maps to AshDate" do
      type = %Type{kind: :date, name: "Date", module: Ash.Type.Date, constraints: []}
      assert TypeMapper.map_type(type, [], :output) == "AshDate"
    end

    test "utc_datetime kind maps to UtcDateTime" do
      type = %Type{
        kind: :utc_datetime,
        name: "UtcDateTime",
        module: Ash.Type.UtcDatetime,
        constraints: []
      }

      assert TypeMapper.map_type(type, [], :output) == "UtcDateTime"
    end

    test "utc_datetime_usec kind maps to UtcDateTimeUsec" do
      type = %Type{
        kind: :utc_datetime_usec,
        name: "UtcDateTimeUsec",
        module: Ash.Type.UtcDatetimeUsec,
        constraints: []
      }

      assert TypeMapper.map_type(type, [], :output) == "UtcDateTimeUsec"
    end

    test "duration kind maps to Duration" do
      type = %Type{kind: :duration, name: "Duration", module: Ash.Type.Duration, constraints: []}
      assert TypeMapper.map_type(type, [], :output) == "Duration"
    end

    test "binary kind maps to Binary" do
      type = %Type{kind: :binary, name: "Binary", module: Ash.Type.Binary, constraints: []}
      assert TypeMapper.map_type(type, [], :output) == "Binary"
    end

    test "term kind maps to any" do
      type = %Type{kind: :term, name: "Term", module: Ash.Type.Term, constraints: []}
      assert TypeMapper.map_type(type, [], :output) == "any"
    end
  end

  describe "TypeMapper.map_type/3 with %Type{} - NewType primitives (kind fallback)" do
    test "string kind with unknown module falls back to kind_to_ts" do
      type = %Type{
        kind: :string,
        name: "MyString",
        module: MyApp.Types.CustomString,
        constraints: []
      }

      assert TypeMapper.map_type(type, [], :output) == "string"
    end

    test "integer kind with unknown module falls back to kind_to_ts" do
      type = %Type{kind: :integer, name: "MyInt", module: MyApp.Types.CustomInt, constraints: []}
      assert TypeMapper.map_type(type, [], :output) == "number"
    end

    test "uuid kind with unknown module falls back to UUID" do
      type = %Type{kind: :uuid, name: "MyUUID", module: MyApp.Types.CustomUUID, constraints: []}
      assert TypeMapper.map_type(type, [], :output) == "UUID"
    end
  end

  describe "TypeMapper.map_type/3 with %Type{} - complex types" do
    test "array kind wraps inner type" do
      inner = %Type{kind: :string, name: "String", module: Ash.Type.String, constraints: []}
      type = %Type{kind: :array, name: "Array", module: nil, constraints: [], item_type: inner}
      assert TypeMapper.map_type(type, [], :output) == "Array<string>"
    end

    test "array of numbers" do
      inner = %Type{kind: :integer, name: "Integer", module: Ash.Type.Integer, constraints: []}
      type = %Type{kind: :array, name: "Array", module: nil, constraints: [], item_type: inner}
      assert TypeMapper.map_type(type, [], :output) == "Array<number>"
    end

    test "enum kind with values" do
      type = %Type{
        kind: :enum,
        name: "Status",
        module: nil,
        constraints: [],
        values: [:active, :inactive, :archived]
      }

      result = TypeMapper.map_type(type, [], :output)
      assert result == "\"active\" | \"inactive\" | \"archived\""
    end

    test "enum kind without values returns string" do
      type = %Type{kind: :enum, name: "Enum", module: nil, constraints: [], values: []}
      assert TypeMapper.map_type(type, [], :output) == "string"
    end

    test "embedded_resource kind maps to resource schema" do
      type = %Type{
        kind: :embedded_resource,
        name: "TodoMetadata",
        module: AshTypescript.Test.TodoMetadata,
        constraints: [],
        resource_module: AshTypescript.Test.TodoMetadata
      }

      result = TypeMapper.map_type(type, [], :output)
      assert result == "TodoMetadataResourceSchema"
    end

    test "embedded_resource kind maps to input schema for :input direction" do
      type = %Type{
        kind: :embedded_resource,
        name: "TodoMetadata",
        module: AshTypescript.Test.TodoMetadata,
        constraints: [],
        resource_module: AshTypescript.Test.TodoMetadata
      }

      result = TypeMapper.map_type(type, [], :input)
      assert result == "TodoMetadataInputSchema"
    end
  end

  describe "TypeMapper.map_type/3 with %Type{} matches existing behavior" do
    test "string type matches both paths" do
      old_result = TypeMapper.map_type(Ash.Type.String, [], :output)
      type = %Type{kind: :string, name: "String", module: Ash.Type.String, constraints: []}
      new_result = TypeMapper.map_type(type, [], :output)
      assert old_result == new_result
    end

    test "UUID type matches both paths" do
      old_result = TypeMapper.map_type(Ash.Type.UUID, [], :output)
      type = %Type{kind: :uuid, name: "UUID", module: Ash.Type.UUID, constraints: []}
      new_result = TypeMapper.map_type(type, [], :output)
      assert old_result == new_result
    end

    test "array of strings matches both paths" do
      old_result = TypeMapper.map_type({:array, Ash.Type.String}, [], :output)
      inner = %Type{kind: :string, name: "String", module: Ash.Type.String, constraints: []}
      type = %Type{kind: :array, name: "Array", module: nil, constraints: [], item_type: inner}
      new_result = TypeMapper.map_type(type, [], :output)
      assert old_result == new_result
    end

    test "embedded resource matches both paths" do
      old_result = TypeMapper.map_type(AshTypescript.Test.TodoMetadata, [], :output)

      type = %Type{
        kind: :embedded_resource,
        name: "TodoMetadata",
        module: AshTypescript.Test.TodoMetadata,
        constraints: [],
        resource_module: AshTypescript.Test.TodoMetadata
      }

      new_result = TypeMapper.map_type(type, [], :output)
      assert old_result == new_result
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # TypeMapper.is_primitive_union_member?(%Type{})
  # ─────────────────────────────────────────────────────────────────

  describe "TypeMapper.is_primitive_union_member?/1 with %Type{}" do
    test "string is primitive" do
      type = %Type{kind: :string, name: "String", module: Ash.Type.String, constraints: []}
      assert TypeMapper.is_primitive_union_member?(type) == true
    end

    test "integer is primitive" do
      type = %Type{kind: :integer, name: "Integer", module: Ash.Type.Integer, constraints: []}
      assert TypeMapper.is_primitive_union_member?(type) == true
    end

    test "embedded_resource is not primitive" do
      type = %Type{
        kind: :embedded_resource,
        name: "Metadata",
        module: nil,
        constraints: [],
        resource_module: AshTypescript.Test.TodoMetadata
      }

      assert TypeMapper.is_primitive_union_member?(type) == false
    end

    test "resource is not primitive" do
      type = %Type{
        kind: :resource,
        name: "Todo",
        module: nil,
        constraints: [],
        resource_module: AshTypescript.Test.Todo
      }

      assert TypeMapper.is_primitive_union_member?(type) == false
    end

    test "union is not primitive" do
      type = %Type{kind: :union, name: "Union", module: Ash.Type.Union, constraints: []}
      assert TypeMapper.is_primitive_union_member?(type) == false
    end

    test "struct with instance_of is not primitive" do
      type = %Type{
        kind: :struct,
        name: "Struct",
        module: Ash.Type.Struct,
        constraints: [],
        instance_of: SomeModule
      }

      assert TypeMapper.is_primitive_union_member?(type) == false
    end

    test "map without fields is primitive" do
      type = %Type{kind: :map, name: "Map", module: Ash.Type.Map, constraints: []}
      assert TypeMapper.is_primitive_union_member?(type) == true
    end

    test "map with fields constraint is not primitive" do
      type = %Type{
        kind: :map,
        name: "Map",
        module: Ash.Type.Map,
        constraints: [fields: [name: [type: :string]]]
      }

      assert TypeMapper.is_primitive_union_member?(type) == false
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # ResourceSchemas.classify_by_type(%Type{})
  # ─────────────────────────────────────────────────────────────────

  describe "ResourceSchemas.classify_by_type/1 with %Type{}" do
    test "string type is primitive" do
      type = %Type{kind: :string, name: "String", module: Ash.Type.String, constraints: []}
      assert ResourceSchemas.classify_by_type(type) == :primitive
    end

    test "integer type is primitive" do
      type = %Type{kind: :integer, name: "Integer", module: Ash.Type.Integer, constraints: []}
      assert ResourceSchemas.classify_by_type(type) == :primitive
    end

    test "embedded_resource type is embedded" do
      type = %Type{
        kind: :embedded_resource,
        name: "TodoMetadata",
        module: AshTypescript.Test.TodoMetadata,
        constraints: [],
        resource_module: AshTypescript.Test.TodoMetadata
      }

      assert ResourceSchemas.classify_by_type(type) == :embedded
    end

    test "resource type is embedded" do
      type = %Type{
        kind: :resource,
        name: "Todo",
        module: AshTypescript.Test.Todo,
        constraints: [],
        resource_module: AshTypescript.Test.Todo
      }

      assert ResourceSchemas.classify_by_type(type) == :embedded
    end

    test "union type is union" do
      type = %Type{kind: :union, name: "Union", module: Ash.Type.Union, constraints: []}
      assert ResourceSchemas.classify_by_type(type) == :union
    end

    test "map with fields is typed_map" do
      type = %Type{
        kind: :map,
        name: "Map",
        module: Ash.Type.Map,
        constraints: [fields: [name: [type: :string]]]
      }

      assert ResourceSchemas.classify_by_type(type) == :typed_map
    end

    test "map without fields is primitive" do
      type = %Type{kind: :map, name: "Map", module: Ash.Type.Map, constraints: []}
      assert ResourceSchemas.classify_by_type(type) == :primitive
    end

    test "array of strings is primitive" do
      inner = %Type{kind: :string, name: "String", module: Ash.Type.String, constraints: []}
      type = %Type{kind: :array, name: "Array", module: nil, constraints: [], item_type: inner}
      assert ResourceSchemas.classify_by_type(type) == :primitive
    end

    test "array of embedded resources is embedded" do
      inner = %Type{
        kind: :embedded_resource,
        name: "TodoMetadata",
        module: AshTypescript.Test.TodoMetadata,
        constraints: [],
        resource_module: AshTypescript.Test.TodoMetadata
      }

      type = %Type{kind: :array, name: "Array", module: nil, constraints: [], item_type: inner}
      assert ResourceSchemas.classify_by_type(type) == :embedded
    end

    test "array of unions is union" do
      inner = %Type{kind: :union, name: "Union", module: Ash.Type.Union, constraints: []}
      type = %Type{kind: :array, name: "Array", module: nil, constraints: [], item_type: inner}
      assert ResourceSchemas.classify_by_type(type) == :union
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # ResourceSchemas.classify_field(%AshApiSpec.Field{})
  # ─────────────────────────────────────────────────────────────────

  describe "ResourceSchemas.classify_field/1 with %AshApiSpec.Field{}" do
    test "attribute with string type is primitive" do
      field = %AshApiSpec.Field{
        name: :title,
        kind: :attribute,
        type: %Type{kind: :string, name: "String", module: Ash.Type.String, constraints: []},
        allow_nil?: false,
        writable?: true,
        has_default?: false,
        filterable?: true,
        sortable?: true,
        primary_key?: false,
        sensitive?: false,
        select_by_default?: true
      }

      assert ResourceSchemas.classify_field(field) == :primitive
    end

    test "attribute with embedded resource type is embedded" do
      field = %AshApiSpec.Field{
        name: :metadata,
        kind: :attribute,
        type: %Type{
          kind: :embedded_resource,
          name: "TodoMetadata",
          module: AshTypescript.Test.TodoMetadata,
          constraints: [],
          resource_module: AshTypescript.Test.TodoMetadata
        },
        allow_nil?: true,
        writable?: true,
        has_default?: false,
        filterable?: true,
        sortable?: true,
        primary_key?: false,
        sensitive?: false,
        select_by_default?: true
      }

      assert ResourceSchemas.classify_field(field) == :embedded
    end

    test "calculation with arguments is :calculation" do
      field = %AshApiSpec.Field{
        name: :complex_calc,
        kind: :calculation,
        type: %Type{kind: :string, name: "String", module: Ash.Type.String, constraints: []},
        allow_nil?: true,
        writable?: false,
        has_default?: false,
        filterable?: true,
        sortable?: true,
        primary_key?: false,
        sensitive?: false,
        select_by_default?: true,
        arguments: [
          %AshApiSpec.Argument{
            name: :arg1,
            type: %Type{kind: :string, name: "String", module: Ash.Type.String, constraints: []},
            allow_nil?: false,
            has_default?: false,
            sensitive?: false
          }
        ]
      }

      assert ResourceSchemas.classify_field(field) == :calculation
    end

    test "calculation without arguments classified by type" do
      field = %AshApiSpec.Field{
        name: :simple_calc,
        kind: :calculation,
        type: %Type{kind: :string, name: "String", module: Ash.Type.String, constraints: []},
        allow_nil?: true,
        writable?: false,
        has_default?: false,
        filterable?: true,
        sortable?: true,
        primary_key?: false,
        sensitive?: false,
        select_by_default?: true,
        arguments: []
      }

      assert ResourceSchemas.classify_field(field) == :primitive
    end
  end
end
