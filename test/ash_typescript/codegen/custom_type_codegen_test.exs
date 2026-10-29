# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.CustomTypeCodegenTest do
  # Declared custom types (manifest entries, type callbacks, built-ins) are
  # generated from their fields, through the existing typed-map codegen.
  use ExUnit.Case, async: false

  alias Ash.Info.Manifest.Type
  alias AshTypescript.Codegen
  alias AshTypescript.Codegen.TypeMapper
  alias AshTypescript.CustomTypes.Scalar
  alias AshTypescript.Test.{CustomIdentifier, ExternalCode}
  alias AshTypescript.Test.Todo.PriorityScore
  alias AshTypescript.TypeSystem.Introspection

  setup_all do
    {:ok, content} = AshTypescript.Test.CodegenTestHelper.generate_all_content()
    %{content: content}
  end

  @doc false
  # A `ts_type` MFA target: echoes the constraints it receives.
  def echo_typescript(constraints, tag), do: "#{tag}:#{inspect(constraints)}"

  @doc false
  def non_string_typescript(_constraints), do: :not_a_string

  # Runs `fun` against a copy of the test manifest whose `custom_types`
  # `kind` (`:declared` or `:builtin`) entries are updated by `update`.
  defp with_entries(kind, update, fun) do
    manifest = AshTypescript.manifest()

    manifest =
      update_in(manifest.custom.ash_typescript.custom_types, fn custom_types ->
        Map.update!(custom_types, kind, update)
      end)

    AshTypescript.with_manifest(manifest, fun)
  end

  defp ts(type, constraints \\ []),
    do: Codegen.get_ts_type(%{type: type, constraints: constraints})

  describe "scalar entries" do
    test "CustomIdentifier's manifest scalar is aliased as its base type", %{content: content} do
      assert content =~ "export type CustomIdentifier = string;"
      assert content =~ "customId: CustomIdentifier | null;"
      assert ts(CustomIdentifier) == "CustomIdentifier"
      assert ts({:array, CustomIdentifier}) == "Array<CustomIdentifier>"
    end

    test "a ts_type MFA is called with the use's constraints" do
      entry = %Scalar{
        module: CustomIdentifier,
        type: Ash.Type.String,
        ts_type: {__MODULE__, :echo_typescript, ["id"]}
      }

      with_entries(:declared, &Map.put(&1, CustomIdentifier, entry), fn ->
        assert ts(CustomIdentifier, foo: 1) == "id:[foo: 1]"
      end)
    end

    test "the test manifest's MFA scalar (ExternalCode)", %{content: content} do
      assert content =~ "export type ExternalCode = `code-${string}`;"
      assert ts(ExternalCode) == "ExternalCode"
    end

    test "a ts_type MFA returning a non-string raises, naming the module and MFA" do
      entry = %Scalar{
        module: CustomIdentifier,
        type: Ash.Type.String,
        ts_type: {__MODULE__, :non_string_typescript, []}
      }

      with_entries(:declared, &Map.put(&1, CustomIdentifier, entry), fn ->
        error = assert_raise ArgumentError, fn -> ts(CustomIdentifier) end
        message = Exception.message(error)
        assert message =~ "AshTypescript.Test.CustomIdentifier"
        assert message =~ "AshTypescript.Codegen.CustomTypeCodegenTest.non_string_typescript/1"
        assert message =~ ":not_a_string"
      end)
    end
  end

  describe "the order of TypeScript mappings for a scalar" do
    test "a manifest scalar's ts_type beats typescript_type/0" do
      entry = %Scalar{module: PriorityScore, type: Ash.Type.Integer, ts_type: "number"}

      with_entries(:declared, &Map.put(&1, PriorityScore, entry), fn ->
        assert ts(PriorityScore) == "number"
      end)
    end

    test "a manifest scalar without ts_type maps as its base type" do
      # CustomIdentifier has no typescript_type/0.
      entry = %Scalar{module: CustomIdentifier, type: Ash.Type.Boolean}

      with_entries(:declared, &Map.put(&1, CustomIdentifier, entry), fn ->
        assert ts(CustomIdentifier) == "boolean"
      end)
    end

    test "typescript_type/0 beats a manifest scalar without ts_type" do
      entry = %Scalar{module: PriorityScore, type: Ash.Type.Boolean, zod: "z.boolean()"}

      with_entries(:declared, &Map.put(&1, PriorityScore, entry), fn ->
        assert ts(PriorityScore) == "CustomTypes.PriorityScore"
      end)
    end

    test "a manifest scalar without ts_type replaces a built-in's ts_type" do
      builtin = %Scalar{module: CustomIdentifier, type: Ash.Type.String, ts_type: "BuiltinId"}
      declared = %Scalar{module: CustomIdentifier, type: Ash.Type.Boolean}

      with_entries(:builtin, &Map.put(&1, CustomIdentifier, builtin), fn ->
        with_entries(:declared, &Map.put(&1, CustomIdentifier, declared), fn ->
          assert ts(CustomIdentifier) == "boolean"
        end)
      end)
    end

    test "typescript_type/0 beats a built-in scalar's ts_type" do
      entry = %Scalar{module: PriorityScore, type: Ash.Type.Integer, ts_type: "Builtin"}

      with_entries(:builtin, &Map.put(&1, PriorityScore, entry), fn ->
        assert ts(PriorityScore) == "CustomTypes.PriorityScore"
      end)
    end

    test "a built-in scalar applies to a type without a callback or manifest entry" do
      entry = %Scalar{module: CustomIdentifier, type: Ash.Type.String, ts_type: "BuiltinId"}

      with_entries(:builtin, &Map.put(&1, CustomIdentifier, entry), fn ->
        with_entries(:declared, &Map.delete(&1, CustomIdentifier), fn ->
          assert ts(CustomIdentifier) == "BuiltinId"
        end)
      end)
    end
  end

  describe "constraints of a scalar's base mapping" do
    setup do
      entry = %Scalar{
        module: CustomIdentifier,
        type: Ash.Type.Atom,
        constraints: [one_of: [:a, :b]]
      }

      %{entry: entry}
    end

    test "at an attribute use the entry's constraints apply", %{entry: entry} do
      node = %Type{kind: :unknown, module: CustomIdentifier, constraints: [one_of: [:a]]}

      with_entries(:declared, &Map.put(&1, CustomIdentifier, entry), fn ->
        assert TypeMapper.unknown_module_mapping(node) == {:ok, ~s("a" | "b")}
      end)
    end

    test "as a field of a declared custom type the field's constraints apply",
         %{entry: entry} do
      node = %Type{kind: :unknown, module: CustomIdentifier, constraints: [one_of: [:a]]}

      with_entries(:declared, &Map.put(&1, CustomIdentifier, entry), fn ->
        assert TypeMapper.unknown_module_mapping(node, custom_fields?: true) == {:ok, ~s("a")}
      end)
    end
  end

  describe "constraints of a scalar member's base mapping" do
    # ExternalCode re-declared over :atom with `one_of`: Theme's `code` field
    # (no constraints of its own) is a member of a declared custom type, so it
    # maps with its own constraints; ThemeMap's isn't, so the entry's apply.
    setup do
      entry = %Scalar{module: ExternalCode, type: Ash.Type.Atom, constraints: [one_of: [:a, :b]]}
      %{entry: entry}
    end

    test "results", %{entry: entry} do
      with_entries(:declared, &Map.put(&1, ExternalCode, entry), fn ->
        theme =
          TypeMapper.map_type(
            %Type{kind: :type_ref, module: AshTypescript.Test.Theme},
            [],
            :output
          )

        theme_map =
          TypeMapper.map_type(
            %Type{kind: :type_ref, module: AshTypescript.Test.ThemeMap},
            [],
            :output
          )

        assert theme =~ "code: string, codes: Array<string> | null,"
        assert theme_map =~ ~s(code: "a" | "b", codes: Array<"a" | "b"> | null,)
      end)
    end

    test "inputs", %{entry: entry} do
      with_entries(:declared, &Map.put(&1, ExternalCode, entry), fn ->
        theme =
          TypeMapper.map_type(
            %Type{kind: :type_ref, module: AshTypescript.Test.Theme},
            [],
            :input
          )

        theme_map =
          TypeMapper.map_type(
            %Type{kind: :type_ref, module: AshTypescript.Test.ThemeMap},
            [],
            :input
          )

        # Theme is referenced by its input alias, whose body is its input object.
        assert theme == "ThemeInput"

        assert TypeMapper.expand_input(
                 Introspection.named_type_definition(AshTypescript.Test.Theme)
               ) =~
                 "code: string, codes?: Array<string> | null}"

        assert theme_map =~ ~s(code: "a" | "b", codes?: Array<"a" | "b"> | null})
      end)
    end

    test "alias bodies", %{entry: entry} do
      with_entries(:declared, &Map.put(&1, ExternalCode, entry), fn ->
        definition = Introspection.named_type_definition(AshTypescript.Test.Theme)

        assert TypeMapper.expand_plain(definition) =~ "code: string, codes: Array<string> | null}"
      end)
    end
  end

  describe "scalar members keep their own mapping" do
    @theme_result ~s({color: `#${string}`, accent: `#${string}` | null, score: CustomTypes.PriorityScore | null, code: ExternalCode, codes: Array<ExternalCode> | null, __type: "TypedMap", __primitiveFields: "color" | "accent" | "score" | "code" | "codes"} | null;)
    @theme_input ~s({color: `#${string}`, accent?: `#${string}` | null, score?: CustomTypes.PriorityScore | null, code: ExternalCode, codes?: Array<ExternalCode> | null} | null;)

    test "in a declared custom type's result TypedMap", %{content: content} do
      assert content =~ "theme: " <> @theme_result
    end

    test "in a NewType over :map's result TypedMap", %{content: content} do
      assert content =~ "themeMap: " <> @theme_result
    end

    test "in a declared custom type's input alias", %{content: content} do
      assert content =~ "theme?: ThemeInput | null;"

      assert content =~
               "export type ThemeInput = " <> String.replace_suffix(@theme_input, " | null;", ";")
    end

    test "in a NewType over :map's input object", %{content: content} do
      assert content =~ "themeMap?: " <> @theme_input
    end
  end

  describe "built-in types and aliases" do
    test "ULID and Ltree aliases are generated per variant used; Money has one" do
      aliases =
        Codegen.generate_ash_type_aliases([AshTypescript.Test.Task, AshTypescript.Test.Todo])

      assert aliases =~ "export type AshPostgresLtreeArray = string[];"
      assert aliases =~ "export type AshPostgresLtreeFlexible = string | string[];"
      assert aliases =~ "export type ULID = string;"
      assert aliases =~ "export type Money = {currency: string, amount: Decimal};"
    end

    test "Ltree attributes reference their alias per escape?", %{content: content} do
      assert content =~ "  hierarchy: AshPostgresLtreeFlexible | null;"
      assert content =~ "  strictHierarchy: AshPostgresLtreeArray | null;"
      refute content =~ "string | string[] | null;"
    end

    test "ULID references its alias" do
      assert ts(AshDoubleEntry.ULID) == "ULID"
    end
  end

  describe "the built-in Money entry (Task.price)" do
    test "the resource schema types it as a typed map of its fields", %{content: content} do
      assert content =~
               ~s(price: {currency: string, amount: Decimal, __type: "TypedMap", __primitiveFields: "currency" | "amount"} | null;)
    end

    test "the input type references its alias", %{content: content} do
      assert content =~ "price?: Money | null;"
    end

    test "the zod and valibot schemas reference its named schemas", %{content: content} do
      assert content =~ "price: MoneyZodSchema.nullable().optional(),"
      assert content =~ "price: v.optional(v.nullable(MoneyValibotSchema)),"
    end

    test "the named schemas are objects of its fields", %{content: content} do
      assert content =~
               "export const MoneyZodSchema = z.object({ currency: z.string(), amount: z.string() });"

      assert content =~
               "export const MoneyValibotSchema = v.object({ currency: v.string(), amount: v.string() });"
    end
  end

  describe "a type declaring typescript_fields/0 (Todo.color_palette)" do
    test "the input type references its alias", %{content: content} do
      assert content =~ "colorPalette?: ColorPalette | null;"
    end

    test "the zod and valibot schemas reference its named schemas", %{content: content} do
      assert content =~ "colorPalette: ColorPaletteZodSchema.nullable().optional(),"
      assert content =~ "colorPalette: v.optional(v.nullable(ColorPaletteValibotSchema)),"
    end

    test "the named schemas are objects of its fields", %{content: content} do
      assert content =~
               "export const ColorPaletteZodSchema = z.object({ primary: z.string(), secondary: z.string(), accent: z.string() });"

      assert content =~
               "export const ColorPaletteValibotSchema = v.object({ primary: v.string(), secondary: v.string(), accent: v.string() });"
    end
  end
end
