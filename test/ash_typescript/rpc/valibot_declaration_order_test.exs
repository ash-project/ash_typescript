# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.ValibotDeclarationOrderTest do
  @moduledoc """
  Tests that Valibot schemas are declared before they are referenced (the
  twin of `AshTypescript.Rpc.ZodDeclarationOrderTest`).

  JavaScript `const` declarations are not hoisted, so referencing a schema
  variable before its declaration causes a runtime error. This test ensures
  the topological sort in `SchemaCore.generate_schemas_for_resources/2` orders
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

  alias AshTypescript.Codegen.{SchemaCore, ValibotSchemaGenerator}

  alias AshTypescript.Test.ZodOrder.{NodeA, NodeB, NodeC, NodeD, NodeE}

  # The ZodOrder resources are outside the app's manifest; codegen names their
  # fields from the schema fixtures manifest.
  defp valibot_schemas(resources, domains \\ []) do
    manifest = AshTypescript.Test.SchemaFixtures.Domain.manifest(domains)

    AshTypescript.with_manifest(manifest, fn ->
      SchemaCore.generate_schemas_for_resources(ValibotSchemaGenerator, resources)
    end)
  end

  defp declaration_order(output) do
    ~r/export const (\w+ValibotSchema) = v\.object/
    |> Regex.scan(output)
    |> Enum.map(fn [_, name] -> name end)
  end

  defp declaration_position(output, schema_name) do
    {pos, _} = :binary.match(output, "#{schema_name} = v.object")
    pos
  end

  defp assert_all_references_after_declarations(output) do
    declared_names = declaration_order(output)

    declaration_positions =
      Map.new(declared_names, fn name -> {name, declaration_position(output, name)} end)

    # Valibot wraps references (`v.optional(v.nullable(XValibotSchema))`), so
    # every use of a declared name other than its declaration is a reference.
    references = Regex.scan(~r/(?<!const )\b(\w+ValibotSchema)\b/, output, return: :index)

    for [_, {ref_pos, len}] <- references,
        ref_name = binary_part(output, ref_pos, len),
        Map.has_key?(declaration_positions, ref_name) do
      decl_pos = Map.get(declaration_positions, ref_name)

      assert decl_pos < ref_pos,
             "#{ref_name} is referenced at position #{ref_pos} but declared at position #{decl_pos}"
    end
  end

  describe "diamond dependency graph (A→B→D→E, A→C→D→E)" do
    test "leaf nodes are declared before nodes that reference them" do
      resources = [NodeA, NodeB, NodeC, NodeD, NodeE]
      output = valibot_schemas(resources)
      order = declaration_order(output)

      assert Enum.find_index(order, &(&1 == "ZodOrderNodeEValibotSchema")) <
               Enum.find_index(order, &(&1 == "ZodOrderNodeDValibotSchema"))

      d_idx = Enum.find_index(order, &(&1 == "ZodOrderNodeDValibotSchema"))
      b_idx = Enum.find_index(order, &(&1 == "ZodOrderNodeBValibotSchema"))
      c_idx = Enum.find_index(order, &(&1 == "ZodOrderNodeCValibotSchema"))
      assert d_idx < b_idx
      assert d_idx < c_idx

      a_idx = Enum.find_index(order, &(&1 == "ZodOrderNodeAValibotSchema"))
      assert b_idx < a_idx
      assert c_idx < a_idx
    end

    test "all references appear after their declarations" do
      resources = [NodeA, NodeB, NodeC, NodeD, NodeE]
      output = valibot_schemas(resources)
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
        output = valibot_schemas(resources)
        assert_all_references_after_declarations(output)
      end
    end

    test "array-wrapped dependencies are detected" do
      resources = [NodeD, NodeE]
      output = valibot_schemas(resources)

      e_pos = declaration_position(output, "ZodOrderNodeEValibotSchema")
      d_pos = declaration_position(output, "ZodOrderNodeDValibotSchema")

      assert e_pos < d_pos,
             "NodeE (array-wrapped dep) must be declared before NodeD"
    end
  end

  describe "dependencies through nested types" do
    test "a resource reached through a union member or typed map field is declared first" do
      alias AshTypescript.Test.ZodOrder.{ANestedHolder, ZLeaf}

      output = valibot_schemas([ANestedHolder, ZLeaf])

      assert declaration_position(output, "ZodOrderZLeafValibotSchema") <
               declaration_position(output, "ZodOrderANestedHolderValibotSchema")

      assert output =~ "ZodOrderZLeafValibotSchema"
      assert_all_references_after_declarations(output)
    end

    test "a struct instance_of a resource references that resource's schema, fields or not" do
      # Ash's manifest turns a `:struct` whose `instance_of` is a resource into
      # that resource's node and drops `fields`, so the schema (and the
      # declaration order) follows the resource.
      alias AshTypescript.Test.ZodOrder.{AStructHolder, ZLeaf, ZWrapped}

      output = valibot_schemas([AStructHolder, ZLeaf, ZWrapped])

      assert output =~ "  wrapped: v.optional(v.nullable(ZodOrderZWrappedValibotSchema)),"

      assert declaration_position(output, "ZodOrderZWrappedValibotSchema") <
               declaration_position(output, "ZodOrderAStructHolderValibotSchema")

      assert_all_references_after_declarations(output)
    end
  end

  describe "simple dependency (NestedProfile → Profile)" do
    test "dependency is declared first even when passed in reverse order" do
      resources = [
        AshTypescript.Test.InputParsing.NestedProfile,
        AshTypescript.Test.InputParsing.Profile
      ]

      output = SchemaCore.generate_schemas_for_resources(ValibotSchemaGenerator, resources)

      profile_pos = declaration_position(output, "InputParsingProfileValibotSchema")
      nested_pos = declaration_position(output, "InputParsingNestedProfileValibotSchema")

      assert profile_pos < nested_pos
    end
  end

  describe "independent resources" do
    test "all schemas are generated" do
      resources = [
        AshTypescript.Test.TaskMetadata,
        AshTypescript.Test.TodoMetadata
      ]

      output = SchemaCore.generate_schemas_for_resources(ValibotSchemaGenerator, resources)

      assert output =~ "TaskMetadataValibotSchema = v.object"
      assert output =~ "TodoMetadataValibotSchema = v.object"
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

      output = valibot_schemas(resources, [AshTypescript.Test.Domain])
      assert_all_references_after_declarations(output)
    end
  end

  describe "subset of dependency chain" do
    test "partial chain still orders correctly" do
      resources = [NodeB, NodeD]
      output = valibot_schemas(resources)

      d_pos = declaration_position(output, "ZodOrderNodeDValibotSchema")
      b_pos = declaration_position(output, "ZodOrderNodeBValibotSchema")

      assert d_pos < b_pos
    end

    test "missing dependencies in resource list does not break generation" do
      resources = [NodeB, NodeD]
      output = valibot_schemas(resources)

      assert output =~ "ZodOrderNodeDValibotSchema = v.object"
      assert output =~ "ZodOrderNodeBValibotSchema = v.object"
    end
  end

  describe "dependencies through named types (:type_ref)" do
    alias AshTypescript.Test.InlineManifest
    alias AshTypescript.Test.ZodOrder.{AInlineRefHolder, ANamedRefHolder, ZRefLeaf}

    # EntryLeafBox's `map` entry replaces its schemas with authored ones,
    # which don't reference ZRefLeaf's.
    @entry_box_entry (quote do
                        map AshTypescript.Test.ZodOrder.EntryLeafBox do
                          field :leaf, AshTypescript.Test.ZodOrder.ZRefLeaf
                          zod "CustomZodSchemas.leafBox"
                          valibot "CustomValibotSchemas.leafBox"
                        end
                      end)

    defp type_ref_schemas(resources) do
      manifest =
        InlineManifest.build!(
          domains: [AshTypescript.Test.SchemaFixtures.Domain],
          body: InlineManifest.app_custom_types([@entry_box_entry])
        )

      AshTypescript.with_manifest(manifest, fn ->
        SchemaCore.generate_schemas_for_resources(ValibotSchemaGenerator, resources)
      end)
    end

    test "a named type with its own schema, or a map entry's, adds no dependency" do
      output = type_ref_schemas([ZRefLeaf, ANamedRefHolder])

      assert output =~
               "  aliasedBox: v.optional(v.nullable(ZodOrderAliasedLeafBoxValibotSchema)),"

      assert output =~ "  entryBox: v.optional(v.nullable(CustomValibotSchemas.leafBox)),"

      assert declaration_position(output, "ZodOrderANamedRefHolderValibotSchema") <
               declaration_position(output, "ZodOrderZRefLeafValibotSchema")
    end

    test "a named type rendered inline adds its fields' dependencies" do
      output = type_ref_schemas([AInlineRefHolder, ZRefLeaf])

      assert output =~
               "  inlineBox: v.optional(v.nullable(v.object({ leaf: v.optional(v.nullable(ZodOrderZRefLeafValibotSchema)) }))),"

      assert declaration_position(output, "ZodOrderZRefLeafValibotSchema") <
               declaration_position(output, "ZodOrderAInlineRefHolderValibotSchema")

      assert_all_references_after_declarations(output)
    end
  end
end
