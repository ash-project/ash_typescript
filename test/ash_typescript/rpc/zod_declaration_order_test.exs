# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.ZodDeclarationOrderTest do
  @moduledoc """
  Tests that Zod schemas are declared before they are referenced.

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

  alias AshTypescript.Codegen.{SchemaCore, ZodSchemaGenerator}

  alias AshTypescript.Test.ZodOrder.{NodeA, NodeB, NodeC, NodeD, NodeE}

  # The ZodOrder resources are outside the app's manifest; codegen names their
  # fields from the schema fixtures manifest.
  defp zod_schemas(resources, domains \\ []) do
    manifest = AshTypescript.Test.SchemaFixtures.Domain.manifest(domains)

    AshTypescript.with_manifest(manifest, fn ->
      SchemaCore.generate_schemas_for_resources(ZodSchemaGenerator, resources)
    end)
  end

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

    # Every use of a declared name other than its declaration is a reference
    # (`field: XZodSchema`, `z.array(XZodSchema)`, `z.union([XZodSchema, …])`).
    references = Regex.scan(~r/(?<!const )\b(\w+ZodSchema)\b/, output, return: :index)

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
      output = zod_schemas(resources)
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
      output = zod_schemas(resources)
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
        output = zod_schemas(resources)
        assert_all_references_after_declarations(output)
      end
    end

    test "array-wrapped dependencies are detected" do
      resources = [NodeD, NodeE]
      output = zod_schemas(resources)

      e_pos = declaration_position(output, "ZodOrderNodeEZodSchema")
      d_pos = declaration_position(output, "ZodOrderNodeDZodSchema")

      assert e_pos < d_pos,
             "NodeE (array-wrapped dep) must be declared before NodeD"
    end
  end

  describe "dependencies through nested types" do
    test "a resource reached through a union member or typed map field is declared first" do
      alias AshTypescript.Test.ZodOrder.{ANestedHolder, ZLeaf}

      output = zod_schemas([ANestedHolder, ZLeaf])

      assert declaration_position(output, "ZodOrderZLeafZodSchema") <
               declaration_position(output, "ZodOrderANestedHolderZodSchema")

      assert output =~ "ZodOrderZLeafZodSchema"
      assert_all_references_after_declarations(output)
    end

    test "a struct instance_of a resource references that resource's schema, fields or not" do
      # Ash's manifest turns a `:struct` whose `instance_of` is a resource into
      # that resource's node and drops `fields`, so the schema (and the
      # declaration order) follows the resource.
      alias AshTypescript.Test.ZodOrder.{AStructHolder, ZLeaf, ZWrapped}

      output = zod_schemas([AStructHolder, ZLeaf, ZWrapped])

      assert output =~ "  wrapped: ZodOrderZWrappedZodSchema.nullable().optional(),"

      assert declaration_position(output, "ZodOrderZWrappedZodSchema") <
               declaration_position(output, "ZodOrderAStructHolderZodSchema")

      assert_all_references_after_declarations(output)
    end
  end

  describe "simple dependency (NestedProfile → Profile)" do
    test "dependency is declared first even when passed in reverse order" do
      resources = [
        AshTypescript.Test.InputParsing.NestedProfile,
        AshTypescript.Test.InputParsing.Profile
      ]

      output = SchemaCore.generate_schemas_for_resources(ZodSchemaGenerator, resources)

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

      output = SchemaCore.generate_schemas_for_resources(ZodSchemaGenerator, resources)

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

      output = zod_schemas(resources, [AshTypescript.Test.Domain])
      assert_all_references_after_declarations(output)
    end
  end

  describe "subset of dependency chain" do
    test "partial chain still orders correctly" do
      resources = [NodeB, NodeD]
      output = zod_schemas(resources)

      d_pos = declaration_position(output, "ZodOrderNodeDZodSchema")
      b_pos = declaration_position(output, "ZodOrderNodeBZodSchema")

      assert d_pos < b_pos
    end

    test "missing dependencies in resource list does not break generation" do
      resources = [NodeB, NodeD]
      output = zod_schemas(resources)

      assert output =~ "ZodOrderNodeDZodSchema = z.object"
      assert output =~ "ZodOrderNodeBZodSchema = z.object"
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
        SchemaCore.generate_schemas_for_resources(ZodSchemaGenerator, resources)
      end)
    end

    test "a named type with its own schema, or a map entry's, adds no dependency" do
      output = type_ref_schemas([ZRefLeaf, ANamedRefHolder])

      assert output =~ "  aliasedBox: ZodOrderAliasedLeafBoxZodSchema.nullable().optional(),"
      assert output =~ "  entryBox: CustomZodSchemas.leafBox.nullable().optional(),"

      assert declaration_position(output, "ZodOrderANamedRefHolderZodSchema") <
               declaration_position(output, "ZodOrderZRefLeafZodSchema")
    end

    test "a named type rendered inline adds its fields' dependencies" do
      output = type_ref_schemas([AInlineRefHolder, ZRefLeaf])

      assert output =~
               "  inlineBox: z.object({ leaf: ZodOrderZRefLeafZodSchema.nullable().optional() }).nullable().optional(),"

      assert declaration_position(output, "ZodOrderZRefLeafZodSchema") <
               declaration_position(output, "ZodOrderAInlineRefHolderZodSchema")

      assert_all_references_after_declarations(output)
    end
  end
end
