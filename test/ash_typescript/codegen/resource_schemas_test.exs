# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.ResourceSchemasTest do
  use ExUnit.Case, async: true

  alias Ash.Info.Manifest.Type
  alias AshTypescript.Codegen.ResourceSchemas
  alias AshTypescript.Test.{NotExposed, Todo}

  describe "classify_by_type/1 on a struct" do
    test "with fields and no instance_of is a typed map" do
      type = %Type{kind: :struct, fields: [%{name: :x, type: %Type{kind: :string}}]}
      assert ResourceSchemas.classify_by_type(type) == :typed_map
    end

    test "without fields is a primitive" do
      assert ResourceSchemas.classify_by_type(%Type{kind: :struct}) == :primitive
    end
  end

  describe "generate_all_schemas_for_resources" do
    test "needs no input-schema resources" do
      assert ResourceSchemas.generate_all_schemas_for_resources([Todo], [Todo]) ==
               ResourceSchemas.generate_all_schemas_for_resources([Todo], [Todo], [])
    end

    test "renders nothing for an unexposed resource that needs no input schema" do
      assert ResourceSchemas.generate_all_schemas_for_resources([NotExposed], [], []) == ""
    end

    test "renders an unexposed resource's input schema when asked" do
      assert ResourceSchemas.generate_all_schemas_for_resources([NotExposed], [], [NotExposed]) =~
               "export type AshTypescriptTestNotExposedInputSchema = {"
    end
  end
end
