# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.NamedCustomTypeSchemasTest do
  # Named zod and valibot schemas for declared custom types: one
  # `export const` per definition with a schema name, in a section before the
  # resource schemas, ordered so each follows the named schemas it references,
  # with lazy references to resource schemas. Uses reference the name. Types
  # whose fields reach a non-embedded resource get no named schema (nor an
  # input alias), and a declared type that contains itself fails codegen.
  use ExUnit.Case, async: false

  alias Ash.Info.Manifest.Type
  alias AshTypescript.Codegen.{CustomTypeAliases, SchemaCore, SharedSchemaGenerator}
  alias AshTypescript.Codegen.{ValibotSchemaGenerator, ZodSchemaGenerator}
  alias AshTypescript.CustomTypes.{Field, MapType}
  alias AshTypescript.Rpc.NamedCustomTypeSchemasTest, as: T
  alias AshTypescript.Test.CodegenTestHelper

  defmodule Coordinates do
    @moduledoc false
    use Ash.Type

    @impl true
    def storage_type(_), do: :map
    @impl true
    def cast_input(value, _), do: {:ok, value}
    @impl true
    def cast_stored(value, _), do: {:ok, value}
    @impl true
    def dump_to_native(value, _), do: {:ok, value}
  end

  # A generic RPC action taking Coordinates, so it reaches an action schema.
  defmodule Holder do
    @moduledoc false
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "NamedSchemasHolder"
    end

    attributes do
      uuid_primary_key :id
    end

    actions do
      action :locate, :boolean do
        argument :coords, AshTypescript.Rpc.NamedCustomTypeSchemasTest.Coordinates,
          allow_nil?: false

        run fn _input, _context -> {:ok, true} end
      end
    end
  end

  defmodule HolderDomain do
    @moduledoc false
    use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

    typescript_rpc do
      resource T.Holder do
        rpc_action :locate_coords, :locate
      end
    end

    resources do
      resource T.Holder
    end
  end

  defmodule Tree do
    @moduledoc false
    use Ash.Type

    @impl true
    def storage_type(_), do: :map
    @impl true
    def cast_input(value, _), do: {:ok, value}
    @impl true
    def cast_stored(value, _), do: {:ok, value}
    @impl true
    def dump_to_native(value, _), do: {:ok, value}
  end

  # Reads a recursive declared type through an RPC action.
  defmodule TreeHolder do
    @moduledoc false
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "TreeHolder"
    end

    attributes do
      uuid_primary_key :id
      attribute :tree, AshTypescript.Rpc.NamedCustomTypeSchemasTest.Tree, public?: true
    end

    actions do
      defaults [:read]
    end
  end

  defmodule TreeDomain do
    @moduledoc false
    use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

    typescript_rpc do
      resource T.TreeHolder do
        rpc_action :list_tree_holders, :read
      end
    end

    resources do
      resource T.TreeHolder
    end
  end

  setup_all do
    {:ok, files} = CodegenTestHelper.generate_files()

    %{
      zod: CodegenTestHelper.zod_content(files),
      valibot: CodegenTestHelper.valibot_content(files)
    }
  end

  defp index_of(content, text) do
    case :binary.match(content, text) do
      {index, _} -> index
      :nomatch -> flunk("#{inspect(text)} not found")
    end
  end

  # The `export const <name> = …;` line.
  defp export_line(content, name) do
    content
    |> String.split("\n")
    |> Enum.find(&String.starts_with?(&1, "export const #{name} = ")) ||
      flunk("no export of #{name}")
  end

  defp count(content, text), do: length(String.split(content, text)) - 1

  # The test manifest with `update` applied to its types, lookups rebuilt.
  defp with_types(update) do
    manifest = AshTypescript.manifest()

    %{manifest | types: update.(manifest.types)}
    |> AshRpc.Manifest.put_lookups()
  end

  describe "the named schemas" do
    test "a named schema per declared custom type", %{zod: zod, valibot: valibot} do
      assert zod =~
               "export const MoneyZodSchema = z.object({ currency: z.string(), amount: z.string() });"

      assert valibot =~
               "export const MoneyValibotSchema = v.object({ currency: v.string(), amount: v.string() });"

      for name <- ["ColorPalette", "Theme", "LineItem"] do
        assert zod =~ "export const #{name}ZodSchema = "
        assert valibot =~ "export const #{name}ValibotSchema = "
      end

      assert export_line(zod, "ColorPaletteZodSchema") ==
               "export const ColorPaletteZodSchema = z.object({ primary: z.string(), secondary: z.string(), accent: z.string() });"
    end

    test "a type reaching a non-embedded resource gets no named schema",
         %{zod: zod, valibot: valibot} do
      refute zod =~ "TodoRefZodSchema"
      refute valibot =~ "TodoRefValibotSchema"
    end

    test "a type with a replacement gets no named schema", %{zod: zod, valibot: valibot} do
      refute zod =~ "GeoPointZodSchema"
      refute valibot =~ "GeoPointValibotSchema"
      assert zod =~ "geoPoint: NestedZodSchemas.geoPoint"
      assert valibot =~ "NestedValibotSchemas.geoPoint"
    end

    test "uses reference the name", %{zod: zod, valibot: valibot} do
      assert count(zod, "price: MoneyZodSchema.nullable().optional(),") == 6
      assert count(valibot, "price: v.optional(v.nullable(MoneyValibotSchema)),") == 6
      refute zod =~ "price: z.object({ currency"
      refute valibot =~ "price: v.optional(v.nullable(v.object({ currency"

      assert zod =~ "colorPalette: ColorPaletteZodSchema.nullable().optional(),"
      assert valibot =~ "colorPalette: v.optional(v.nullable(ColorPaletteValibotSchema)),"
      assert zod =~ "theme: ThemeZodSchema.nullable().optional(),"
      assert valibot =~ "theme: v.optional(v.nullable(ThemeValibotSchema)),"

      assert zod =~
               "export const echoLineItemZodSchema = z.object({\n  lineItem: LineItemZodSchema,\n"

      assert valibot =~
               "export const echoLineItemValibotSchema = v.object({\n  lineItem: LineItemValibotSchema,\n"
    end

    test "a NewType over :map stays inline", %{zod: zod} do
      assert zod =~ "themeMap: z.object({ color: "
    end

    test "the section comes first", %{zod: zod, valibot: valibot} do
      assert index_of(zod, "// Zod Schemas for Custom Types") <
               index_of(zod, "// Zod Schemas for Input Resources")

      assert index_of(valibot, "// Valibot Schemas for Custom Types") <
               index_of(valibot, "// Valibot Schemas for Input Resources")
    end

    test "a schema follows the schemas it references", %{zod: zod, valibot: valibot} do
      assert index_of(zod, "export const MoneyZodSchema") <
               index_of(zod, "export const LineItemZodSchema")

      assert index_of(valibot, "export const MoneyValibotSchema") <
               index_of(valibot, "export const LineItemValibotSchema")

      assert export_line(zod, "LineItemZodSchema") =~ "price: MoneyZodSchema,"
      assert export_line(valibot, "LineItemValibotSchema") =~ "price: MoneyValibotSchema,"
    end

    test "references to resource schemas are lazy", %{zod: zod, valibot: valibot} do
      assert export_line(zod, "LineItemZodSchema") =~
               "meta: z.lazy(() => TaskMetadataZodSchema).nullable().optional()"

      assert export_line(valibot, "LineItemValibotSchema") =~
               "meta: v.optional(v.nullable(v.lazy(() => TaskMetadataValibotSchema)))"
    end

    test "references outside the section stay direct", %{zod: zod} do
      [_, rest] = String.split(zod, "// Zod Schemas for Input Resources")
      refute rest =~ "z.lazy("
      assert zod =~ "detailProfile: InputParsingProfileZodSchema.nullable().optional(),"
    end
  end

  describe "names" do
    setup do
      previous = Application.get_env(:ash_typescript, :zod_schema_suffix)

      on_exit(fn ->
        if previous,
          do: Application.put_env(:ash_typescript, :zod_schema_suffix, previous),
          else: Application.delete_env(:ash_typescript, :zod_schema_suffix)
      end)
    end

    test "the suffix config names them" do
      Application.put_env(:ash_typescript, :zod_schema_suffix, "Zod")

      {:ok, files} = CodegenTestHelper.generate_files()
      zod = CodegenTestHelper.zod_content(files)

      assert zod =~ "export const MoneyZod = "
      assert zod =~ "price: MoneyZod.nullable().optional(),"
      refute zod =~ "MoneyZodSchema"
    end

    # The section and the action schema for Coordinates declared by `entry`.
    defp render_coordinates(entry) do
      manifest =
        AshTypescript.Test.InlineManifest.build!(
          domains: [T.HolderDomain],
          body:
            quote do
              custom_types do
                unquote(entry)
              end
            end
        )

      # Full codegen needs the app's domains; the section and the action
      # schema are rendered from this manifest directly.
      AshTypescript.with_manifest(manifest, fn ->
        action = AshTypescript.Test.SpecHelpers.spec_action(T.Holder, :locate)

        render = fn formatter ->
          SchemaCore.generate_custom_type_schemas(formatter) <>
            SchemaCore.generate_action_schema(formatter, T.Holder, action, "locate_coords")
        end

        {render.(ZodSchemaGenerator), render.(ValibotSchemaGenerator)}
      end)
    end

    test "the schemas are named after the type_name" do
      {zod, valibot} =
        render_coordinates(
          quote do
            map AshTypescript.Rpc.NamedCustomTypeSchemasTest.Coordinates do
              type_name "GeoCoords"
              field :lat, :float, allow_nil?: false
            end
          end
        )

      assert zod =~ "export const GeoCoordsZodSchema = z.object({ lat: z.number() });"

      assert zod =~
               "export const locateCoordsZodSchema = z.object({\n  coords: GeoCoordsZodSchema,\n"

      assert valibot =~ "export const GeoCoordsValibotSchema = v.object({ lat: v.number() });"

      assert valibot =~
               "export const locateCoordsValibotSchema = v.object({\n  coords: GeoCoordsValibotSchema,\n"
    end

    test "without a type_name the schemas are named after the joined module name" do
      {zod, valibot} =
        render_coordinates(
          quote do
            map AshTypescript.Rpc.NamedCustomTypeSchemasTest.Coordinates do
              field :lat, :float, allow_nil?: false
            end
          end
        )

      name = "AshTypescriptRpcNamedCustomTypeSchemasTestCoordinates"
      assert zod =~ "export const #{name}ZodSchema = z.object({ lat: z.number() });"
      assert zod =~ "  coords: #{name}ZodSchema,\n"
      assert valibot =~ "export const #{name}ValibotSchema = v.object({ lat: v.number() });"
    end
  end

  describe "generate_custom_type_schemas/1" do
    test "the section is emitted without schema resources" do
      section =
        AshTypescript.with_manifest(AshTypescript.manifest(), fn ->
          SchemaCore.generate_custom_type_schemas(ZodSchemaGenerator)
        end)

      assert section =~ "// Zod Schemas for Custom Types"
      assert section =~ "export const MoneyZodSchema = "
      refute section =~ "Input Resources"

      content =
        SharedSchemaGenerator.generate(ZodSchemaGenerator,
          resource_schemas: "",
          custom_type_schemas: section,
          types_output_file: "out/ashTypes.ts",
          schema_output_file: "out/ashZod.ts"
        )

      assert content =~ section
    end

    test "valibot gets the same section" do
      section =
        AshTypescript.with_manifest(AshTypescript.manifest(), fn ->
          SchemaCore.generate_custom_type_schemas(ValibotSchemaGenerator)
        end)

      assert section =~ "// Valibot Schemas for Custom Types"
      assert section =~ "export const MoneyValibotSchema = "
    end

    # A hand-built definition of `fields` (`[name: type]`, every field
    # nullable), declared (named after `name`) unless `declared?` is false.
    defp definition(module, name, fields, declared? \\ true) do
      names = %{typescript: name, zod: :derive, valibot: :derive}

      custom = %{
        ash_rpc: %{
          custom_type: declared?,
          field_names: Map.new(fields, fn {field, _} -> {field, to_string(field)} end),
          client_field_names: Map.new(fields, fn {field, _} -> {to_string(field), field} end)
        }
      }

      %Type{
        kind: :map,
        name: name,
        module: module,
        constraints: [],
        fields:
          Enum.map(fields, fn {field, type} ->
            %{name: field, type: type, description: nil, allow_nil?: true}
          end),
        custom:
          if(declared?,
            do: Map.put(custom, :ash_typescript, %{custom_type_names: names}),
            else: custom
          )
      }
    end

    defp ref(module), do: %Type{kind: :type_ref, module: module, constraints: []}

    defp task_metadata,
      do: %Type{
        kind: :embedded_resource,
        module: AshTypescript.Test.TaskMetadata,
        resource_module: AshTypescript.Test.TaskMetadata,
        constraints: []
      }

    defp union_of(type),
      do: %Type{
        kind: :union,
        members: [%{name: :member, type: type}],
        constraints: [],
        custom: %{ash_rpc: %{client_member_names: %{"member" => :member}}}
      }

    defp section_with(definitions) do
      manifest = with_types(&(&1 ++ definitions))

      AshTypescript.with_manifest(manifest, fn ->
        SchemaCore.generate_custom_type_schemas(ZodSchemaGenerator)
      end)
    end

    test "lazy references follow arrays, unions and inline named types" do
      section =
        section_with([
          definition(T.Bag, "Bag",
            list: %Type{kind: :array, item_type: task_metadata(), constraints: []},
            choice: union_of(task_metadata()),
            inner: ref(T.Wrapper)
          ),
          definition(T.Wrapper, "Wrapper", [meta: task_metadata()], false)
        ])

      bag = export_line(section, "BagZodSchema")
      assert count(bag, "z.lazy(() => TaskMetadataZodSchema)") == 3
      refute section =~ "WrapperZodSchema"
    end

    test "a schema follows named schemas reached through arrays, unions and inline types" do
      money = ref(AshMoney.Types.Money)

      section =
        section_with([
          definition(T.AArray, "AArray",
            list: %Type{kind: :array, item_type: money, constraints: []}
          ),
          definition(T.AUnion, "AUnion", choice: union_of(money)),
          definition(T.AInline, "AInline", inner: ref(T.MoneyWrapper)),
          definition(T.MoneyWrapper, "MoneyWrapper", [price: money], false)
        ])

      money_index = index_of(section, "export const MoneyZodSchema")

      for name <- ["AArray", "AUnion", "AInline"] do
        assert index_of(section, "export const #{name}ZodSchema") > money_index
      end

      assert export_line(section, "AInlineZodSchema") =~
               "inner: z.object({ price: MoneyZodSchema.nullable().optional() })"
    end

    test "a derived name uses the TypeScript name" do
      renamed =
        put_in(
          definition(T.Orig, "Orig", other: ref(AshMoney.Types.Money)).custom.ash_typescript.custom_type_names.typescript,
          "Renamed"
        )

      section = section_with([renamed])

      assert section =~ "export const RenamedZodSchema = "
      refute section =~ "OrigZodSchema"
    end

    test "a type with a replacement is not walked for dependencies" do
      # Replaced references X, which references Replaced; Replaced's `zod`
      # replaces its schema, so there is no cycle.
      replaced =
        put_in(
          definition(T.Replaced, "Replaced", other: ref(T.X)).custom.ash_typescript.custom_type_names.zod,
          nil
        )

      manifest =
        [definition(T.X, "X", other: ref(T.Replaced)), replaced]
        |> then(&with_types(fn types -> types ++ &1 end))
        |> update_in(
          [Access.key!(:custom), :ash_typescript, :custom_types, :declared],
          fn declared ->
            # A field-less entry declares nothing, so the entry carries a field.
            Map.put(declared, T.Replaced, %MapType{
              module: T.Replaced,
              fields: [%Field{name: :x, type: Ash.Type.String}],
              zod: "Own.replaced"
            })
          end
        )

      section =
        AshTypescript.with_manifest(manifest, fn ->
          SchemaCore.generate_custom_type_schemas(ZodSchemaGenerator)
        end)

      assert export_line(section, "XZodSchema") =~ "other: Own.replaced.nullable().optional()"
    end

    test "a cycle among named schemas is a codegen error" do
      manifest =
        with_types(fn types ->
          types ++
            [
              definition(T.CycleA, "CycleA", other: ref(T.CycleB)),
              definition(T.CycleB, "CycleB", other: ref(T.CycleA))
            ]
        end)

      assert {:error, message} =
               catch_throw(
                 AshTypescript.with_manifest(manifest, fn ->
                   SchemaCore.generate_custom_type_schemas(ZodSchemaGenerator)
                 end)
               )

      assert message =~ "AshTypescript.Rpc.NamedCustomTypeSchemasTest.CycleA"
      assert message =~ "AshTypescript.Rpc.NamedCustomTypeSchemasTest.CycleB"
      refute message =~ "AshMoney.Types.Money"
      refute message =~ "_schema_name"
      assert message =~ "expand the type to a fixed depth"
    end

    test "the duplicate-name check names the custom type" do
      manifest =
        with_types(fn types ->
          Enum.map(types, fn
            %Type{module: AshMoney.Types.Money} = money ->
              put_in(money.custom.ash_typescript.custom_type_names.typescript, "User")

            type ->
              type
          end)
        end)

      assert {:error, message} =
               CodegenTestHelper.generate_files(:ash_typescript, manifest: manifest)

      assert message =~ "Duplicate Zod schema names detected"
      assert message =~ "UserZodSchema"
      assert message =~ "AshMoney.Types.Money"

      assert message =~
               "`UserZodSchema` is the generated schema of the custom type " <>
                 "AshMoney.Types.Money, named after its alias: rename the alias with " <>
                 "`type_name \"…\"` on its `map` entry (or `typescript_alias_name/0` on a type " <>
                 "without one)."

      refute message =~ "_schema_name"
      refute message =~ "typed controller route"
    end
  end

  describe "types reaching a non-embedded resource" do
    defp todo,
      do: %Type{
        kind: :resource,
        module: AshTypescript.Test.Todo,
        resource_module: AshTypescript.Test.Todo,
        constraints: []
      }

    # An inline typed map (no module, no name) of `fields`.
    defp inline_map(fields), do: %{definition(nil, nil, fields, false) | module: nil}

    defp array_of(type), do: %Type{kind: :array, item_type: type, constraints: []}

    test "get no input alias and no named schemas" do
      reaching = [
        definition(T.RDirect, "RDirect", todo: todo()),
        definition(T.RArray, "RArray", list: array_of(todo())),
        definition(T.RUnion, "RUnion", choice: union_of(todo())),
        definition(T.RContainer, "RContainer", inner: inline_map(todo: todo())),
        definition(T.RInline, "RInline", inner: ref(T.RWrapper)),
        definition(T.RNested, "RNested", inner: array_of(ref(T.RDirect)))
      ]

      wrapper = definition(T.RWrapper, "RWrapper", [todo: todo()], false)
      manifest = with_types(&(&1 ++ [wrapper | reaching]))

      AshTypescript.with_manifest(manifest, fn ->
        for definition <- reaching do
          assert CustomTypeAliases.plain_name(definition) == definition.name
          assert CustomTypeAliases.input_name(definition) == nil, definition.name

          for formatter <- [ZodSchemaGenerator, ValibotSchemaGenerator] do
            assert SchemaCore.custom_type_schema_name(formatter, definition) == nil,
                   "#{definition.name} has a #{formatter.library()} schema"
          end
        end
      end)
    end

    test "an embedded resource keeps the input alias and the named schemas" do
      embedded = definition(T.REmbedded, "REmbedded", meta: task_metadata())
      manifest = with_types(&(&1 ++ [embedded]))

      AshTypescript.with_manifest(manifest, fn ->
        assert CustomTypeAliases.input_name(embedded) == "REmbeddedInput"

        assert SchemaCore.custom_type_schema_name(ZodSchemaGenerator, embedded) ==
                 "REmbeddedZodSchema"

        assert SchemaCore.custom_type_schema_name(ValibotSchemaGenerator, embedded) ==
                 "REmbeddedValibotSchema"
      end)
    end
  end

  describe "recursive declared custom types" do
    defp recursion_error(definitions) do
      manifest = with_types(&(&1 ++ definitions))

      # A walk that doesn't terminate fails the test instead of hanging it.
      task =
        Task.async(fn ->
          AshTypescript.with_manifest(manifest, fn ->
            catch_throw(CustomTypeAliases.check_recursive_types!())
          end)
        end)

      case Task.yield(task, 5_000) || Task.shutdown(task, :brutal_kill) do
        {:ok, thrown} -> thrown
        nil -> flunk("the recursion check didn't terminate")
      end
    end

    test "codegen fails on a map entry that contains itself" do
      tree_manifest =
        AshTypescript.Test.InlineManifest.build!(
          domains: [T.TreeDomain],
          body:
            quote do
              custom_types do
                map AshTypescript.Rpc.NamedCustomTypeSchemasTest.Tree do
                  field :children, {:array, AshTypescript.Rpc.NamedCustomTypeSchemasTest.Tree}
                end
              end
            end
        )

      tree = Enum.find(tree_manifest.types, &(&1.module == T.Tree))
      manifest = with_types(&(&1 ++ [tree]))

      # Rendering a recursive type doesn't terminate: bound the wait.
      task =
        Task.async(fn ->
          CodegenTestHelper.generate_files(:ash_typescript, manifest: manifest)
        end)

      result = Task.yield(task, 30_000) || Task.shutdown(task, :brutal_kill)

      assert {:ok, {:error, message}} = result
      assert message =~ "contain themselves"
      assert message =~ inspect(T.Tree)
    end

    test "a type containing itself through arrays, unions, containers and named types" do
      for {definitions, recursive} <- [
            {[definition(T.SelfArray, "SelfArray", list: array_of(ref(T.SelfArray)))],
             [T.SelfArray]},
            {[definition(T.SelfUnion, "SelfUnion", choice: union_of(ref(T.SelfUnion)))],
             [T.SelfUnion]},
            {[definition(T.SelfMap, "SelfMap", inner: inline_map(me: ref(T.SelfMap)))],
             [T.SelfMap]},
            {[
               definition(T.SelfInline, "SelfInline", inner: ref(T.SelfWrapper)),
               definition(T.SelfWrapper, "SelfWrapper", [outer: ref(T.SelfInline)], false)
             ], [T.SelfInline]},
            {[
               definition(T.PairA, "PairA", b: ref(T.PairB)),
               definition(T.PairB, "PairB", a: ref(T.PairA))
             ], [T.PairA, T.PairB]},
            # Only the type that contains itself, not the one holding it.
            {[
               definition(T.HoldsSelf, "HoldsSelf", inner: ref(T.SelfB)),
               definition(T.SelfB, "SelfB", me: ref(T.SelfB))
             ], [T.SelfB]}
          ] do
        assert {:error, message} = recursion_error(definitions)

        assert message =~
                 "These declared custom types contain themselves, directly or through " <>
                   "other named types: #{Enum.map_join(recursive, ", ", &inspect/1)}."

        assert message =~ "Recursive declared custom types aren't supported"

        refute message =~ "type_name"
        refute message =~ "_schema_name"

        assert message =~ "expand the type to a fixed depth"
      end
    end

    test "a named type used twice, or behind an embedded resource, is no recursion" do
      money = ref(AshMoney.Types.Money)

      manifest =
        with_types(
          &(&1 ++
              [
                definition(T.TwoMoneys, "TwoMoneys", left: money, right: array_of(money)),
                definition(T.WithMeta, "WithMeta", meta: task_metadata())
              ])
        )

      AshTypescript.with_manifest(manifest, fn ->
        assert CustomTypeAliases.check_recursive_types!() == :ok
      end)
    end
  end

  describe "wrap_lazy/1" do
    test "defers a reference" do
      assert ZodSchemaGenerator.wrap_lazy("X") == "z.lazy(() => X)"
      assert ValibotSchemaGenerator.wrap_lazy("X") == "v.lazy(() => X)"
    end
  end
end
