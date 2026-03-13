defmodule AshApiSpec.Generator.TypeResolverTest do
  use ExUnit.Case, async: true

  alias AshApiSpec.Generator.TypeResolver
  alias AshApiSpec.Type

  describe "resolve/2 primitives" do
    test "resolves Ash.Type.String" do
      result = TypeResolver.resolve(Ash.Type.String, [])
      assert %Type{kind: :string, name: "String"} = result
    end

    test "resolves Ash.Type.Integer" do
      result = TypeResolver.resolve(Ash.Type.Integer, [])
      assert %Type{kind: :integer, name: "Integer"} = result
    end

    test "resolves Ash.Type.Boolean" do
      result = TypeResolver.resolve(Ash.Type.Boolean, [])
      assert %Type{kind: :boolean, name: "Boolean"} = result
    end

    test "resolves Ash.Type.UUID" do
      result = TypeResolver.resolve(Ash.Type.UUID, [])
      assert %Type{kind: :uuid, name: "UUID"} = result
    end

    test "resolves Ash.Type.Date" do
      result = TypeResolver.resolve(Ash.Type.Date, [])
      assert %Type{kind: :date, name: "Date"} = result
    end

    test "resolves Ash.Type.UtcDatetime" do
      result = TypeResolver.resolve(Ash.Type.UtcDatetime, [])
      assert %Type{kind: :utc_datetime, name: "UtcDateTime"} = result
    end

    test "resolves Ash.Type.Decimal" do
      result = TypeResolver.resolve(Ash.Type.Decimal, [])
      assert %Type{kind: :decimal, name: "Decimal"} = result
    end

    test "resolves Ash.Type.Float" do
      result = TypeResolver.resolve(Ash.Type.Float, [])
      assert %Type{kind: :float, name: "Float"} = result
    end
  end

  describe "resolve/2 atom shorthands" do
    test "resolves :string" do
      assert %Type{kind: :string} = TypeResolver.resolve(:string, [])
    end

    test "resolves :integer" do
      assert %Type{kind: :integer} = TypeResolver.resolve(:integer, [])
    end

    test "resolves :boolean" do
      assert %Type{kind: :boolean} = TypeResolver.resolve(:boolean, [])
    end

    test "resolves :uuid" do
      assert %Type{kind: :uuid} = TypeResolver.resolve(:uuid, [])
    end
  end

  describe "resolve/2 arrays" do
    test "resolves {:array, :string}" do
      result = TypeResolver.resolve({:array, :string}, [])
      assert %Type{kind: :array, item_type: %Type{kind: :string}} = result
    end

    test "resolves {:array, Ash.Type.Integer}" do
      result = TypeResolver.resolve({:array, Ash.Type.Integer}, [])
      assert %Type{kind: :array, item_type: %Type{kind: :integer}} = result
    end

    test "passes items constraints to inner type" do
      result =
        TypeResolver.resolve({:array, Ash.Type.Integer}, items: [min: 0])

      assert %Type{kind: :array, item_type: %Type{kind: :integer, constraints: [min: 0]}} =
               result
    end
  end

  describe "resolve/2 enums" do
    test "resolves enum type with values" do
      result = TypeResolver.resolve(AshTypescript.Test.Todo.Status, [])
      assert %Type{kind: :enum, values: values} = result
      assert is_list(values)
      assert :pending in values
    end

    test "resolves atom with one_of constraint as enum" do
      result = TypeResolver.resolve(Ash.Type.Atom, one_of: [:low, :medium, :high])
      assert %Type{kind: :enum, values: [:low, :medium, :high]} = result
    end
  end

  describe "resolve/2 unions" do
    test "resolves union type" do
      constraints = [
        types: [
          text: [type: :string],
          number: [type: :integer]
        ]
      ]

      result = TypeResolver.resolve(Ash.Type.Union, constraints)
      assert %Type{kind: :union, members: members} = result
      assert length(members) == 2
      assert Enum.any?(members, &(&1.name == :text))
      assert Enum.any?(members, &(&1.name == :number))
    end
  end

  describe "resolve/2 maps" do
    test "resolves map with fields" do
      constraints = [
        fields: [
          name: [type: :string, allow_nil?: false],
          age: [type: :integer, allow_nil?: true]
        ]
      ]

      result = TypeResolver.resolve(Ash.Type.Map, constraints)
      assert %Type{kind: :map, fields: fields} = result
      assert length(fields) == 2
      name_field = Enum.find(fields, &(&1.name == :name))
      assert name_field.allow_nil? == false
      assert %Type{kind: :string} = name_field.type
    end

    test "resolves map without fields" do
      result = TypeResolver.resolve(Ash.Type.Map, [])
      assert %Type{kind: :map, fields: nil} = result
    end
  end

  describe "resolve/2 keyword" do
    test "resolves keyword with fields" do
      constraints = [
        fields: [
          priority: [type: :integer, allow_nil?: false],
          category: [type: :string, allow_nil?: true]
        ]
      ]

      result = TypeResolver.resolve(Ash.Type.Keyword, constraints)
      assert %Type{kind: :keyword, fields: fields} = result
      assert length(fields) == 2
    end
  end

  describe "resolve/2 tuple" do
    test "resolves tuple with fields" do
      constraints = [
        fields: [
          latitude: [type: :float, allow_nil?: false],
          longitude: [type: :float, allow_nil?: false]
        ]
      ]

      result = TypeResolver.resolve(Ash.Type.Tuple, constraints)
      assert %Type{kind: :tuple, element_types: elements} = result
      assert length(elements) == 2
    end
  end

  describe "resolve/2 struct" do
    test "resolves struct with resource instance_of" do
      constraints = [instance_of: AshTypescript.Test.User]
      result = TypeResolver.resolve(Ash.Type.Struct, constraints)
      assert %Type{kind: :resource, resource_module: AshTypescript.Test.User} = result
    end

    test "resolves struct with embedded resource instance_of" do
      constraints = [instance_of: AshTypescript.Test.TodoMetadata]
      result = TypeResolver.resolve(Ash.Type.Struct, constraints)
      assert %Type{resource_module: AshTypescript.Test.TodoMetadata} = result
      assert result.kind in [:resource, :embedded_resource]
    end
  end

  describe "resolve/2 embedded resources" do
    test "resolves embedded resource directly" do
      result = TypeResolver.resolve(AshTypescript.Test.TodoMetadata, [])
      assert %Type{resource_module: AshTypescript.Test.TodoMetadata} = result
    end
  end

  describe "resolve/2 nil and unknown" do
    test "resolves nil as unknown" do
      result = TypeResolver.resolve(nil, [])
      assert %Type{kind: :unknown} = result
    end
  end

  describe "unwrap_new_type/2" do
    test "unwraps NewType to subtype" do
      # Todo.Status is a NewType of Ash.Type.Atom
      {unwrapped, _constraints} =
        TypeResolver.unwrap_new_type(AshTypescript.Test.Todo.Status, [])

      # Should unwrap to the underlying type
      assert is_atom(unwrapped)
    end

    test "non-NewType returns unchanged" do
      {unwrapped, constraints} = TypeResolver.unwrap_new_type(Ash.Type.String, [])
      assert unwrapped == Ash.Type.String
      assert constraints == []
    end
  end
end
