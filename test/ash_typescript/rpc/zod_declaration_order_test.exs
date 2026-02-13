# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.ZodDeclarationOrderTest do
  @moduledoc """
  Tests that Zod schemas are declared before they are referenced.

  JavaScript `const` declarations are not hoisted, so referencing a schema
  variable before its declaration causes a runtime error. This test ensures
  the topological sort in `generate_zod_schemas_for_resources/1` orders
  resource schemas so dependencies come first.

  Uses the ZodOrder test resources which form a diamond dependency graph:

        NodeA
       /     \\
    NodeB   NodeC
       \\     /
        NodeD (also has {:array, NodeE})
          |
        NodeE (leaf)
  """
  use ExUnit.Case, async: true

  alias AshTypescript.Rpc.ZodSchemaGenerator

  alias AshTypescript.Test.ZodOrder.{NodeA, NodeB, NodeC, NodeD, NodeE}

  defp declaration_order(output) do
    ~r/export const (\w+ZodSchema) = z\.object/
    |> Regex.scan(output)
    |> Enum.map(fn [_, name] -> name end)
  end

  defp declaration_position(output, schema_name) do
    {pos, _} = :binary.match(output, "#{schema_name} = z.object")
    pos
  end

  defp assert_all_references_after_declarations(output) do
    declared_names = declaration_order(output)

    declaration_positions =
      Map.new(declared_names, fn name -> {name, declaration_position(output, name)} end)

    references = Regex.scan(~r/: (\w+ZodSchema)/, output)

    for [full_match, ref_name] <- references,
        Map.has_key?(declaration_positions, ref_name) do
      case :binary.match(output, full_match) do
        {ref_pos, _} ->
          decl_pos = Map.get(declaration_positions, ref_name)

          assert decl_pos < ref_pos,
                 "#{ref_name} is referenced at position #{ref_pos} but declared at position #{decl_pos}"

        :nomatch ->
          :ok
      end
    end
  end

  describe "diamond dependency graph (A→B→D→E, A→C→D→E)" do
    test "leaf nodes are declared before nodes that reference them" do
      resources = [NodeA, NodeB, NodeC, NodeD, NodeE]
      output = ZodSchemaGenerator.generate_zod_schemas_for_resources(resources)
      order = declaration_order(output)

      assert Enum.find_index(order, &(&1 == "ZodOrderNodeEZodSchema")) <
               Enum.find_index(order, &(&1 == "ZodOrderNodeDZodSchema"))

      d_idx = Enum.find_index(order, &(&1 == "ZodOrderNodeDZodSchema"))
      b_idx = Enum.find_index(order, &(&1 == "ZodOrderNodeBZodSchema"))
      c_idx = Enum.find_index(order, &(&1 == "ZodOrderNodeCZodSchema"))
      assert d_idx < b_idx
      assert d_idx < c_idx

      a_idx = Enum.find_index(order, &(&1 == "ZodOrderNodeAZodSchema"))
      assert b_idx < a_idx
      assert c_idx < a_idx
    end

    test "all references appear after their declarations" do
      resources = [NodeA, NodeB, NodeC, NodeD, NodeE]
      output = ZodSchemaGenerator.generate_zod_schemas_for_resources(resources)
      assert_all_references_after_declarations(output)
    end

    test "order is correct regardless of input order" do
      permutations = [
        [NodeA, NodeB, NodeC, NodeD, NodeE],
        [NodeE, NodeD, NodeC, NodeB, NodeA],
        [NodeC, NodeA, NodeE, NodeB, NodeD],
        [NodeD, NodeE, NodeA, NodeC, NodeB]
      ]

      for resources <- permutations do
        output = ZodSchemaGenerator.generate_zod_schemas_for_resources(resources)
        assert_all_references_after_declarations(output)
      end
    end

    test "array-wrapped dependencies are detected" do
      resources = [NodeD, NodeE]
      output = ZodSchemaGenerator.generate_zod_schemas_for_resources(resources)

      e_pos = declaration_position(output, "ZodOrderNodeEZodSchema")
      d_pos = declaration_position(output, "ZodOrderNodeDZodSchema")

      assert e_pos < d_pos,
             "NodeE (array-wrapped dep) must be declared before NodeD"
    end
  end

  describe "simple dependency (NestedProfile → Profile)" do
    test "dependency is declared first even when passed in reverse order" do
      resources = [
        AshTypescript.Test.InputParsing.NestedProfile,
        AshTypescript.Test.InputParsing.Profile
      ]

      output = ZodSchemaGenerator.generate_zod_schemas_for_resources(resources)

      profile_pos = declaration_position(output, "InputParsingProfileZodSchema")
      nested_pos = declaration_position(output, "InputParsingNestedProfileZodSchema")

      assert profile_pos < nested_pos
    end
  end

  describe "independent resources" do
    test "all schemas are generated" do
      resources = [
        AshTypescript.Test.TaskMetadata,
        AshTypescript.Test.TodoMetadata
      ]

      output = ZodSchemaGenerator.generate_zod_schemas_for_resources(resources)

      assert output =~ "TaskMetadataZodSchema = z.object"
      assert output =~ "TodoMetadataZodSchema = z.object"
    end
  end

  describe "mixed dependent and independent resources" do
    test "all references appear after declarations in a large mixed set" do
      resources = [
        NodeA,
        NodeB,
        NodeC,
        NodeD,
        NodeE,
        AshTypescript.Test.InputParsing.NestedProfile,
        AshTypescript.Test.InputParsing.Profile,
        AshTypescript.Test.TodoMetadata,
        AshTypescript.Test.TaskMetadata,
        AshTypescript.Test.TodoContent.ChecklistContent,
        AshTypescript.Test.TodoContent.LinkContent,
        AshTypescript.Test.TodoContent.TextContent
      ]

      output = ZodSchemaGenerator.generate_zod_schemas_for_resources(resources)
      assert_all_references_after_declarations(output)
    end
  end

  describe "subset of dependency chain" do
    test "partial chain still orders correctly" do
      resources = [NodeB, NodeD]
      output = ZodSchemaGenerator.generate_zod_schemas_for_resources(resources)

      d_pos = declaration_position(output, "ZodOrderNodeDZodSchema")
      b_pos = declaration_position(output, "ZodOrderNodeBZodSchema")

      assert d_pos < b_pos
    end

    test "missing dependencies in resource list does not break generation" do
      resources = [NodeB, NodeD]
      output = ZodSchemaGenerator.generate_zod_schemas_for_resources(resources)

      assert output =~ "ZodOrderNodeDZodSchema = z.object"
      assert output =~ "ZodOrderNodeBZodSchema = z.object"
    end
  end
end
