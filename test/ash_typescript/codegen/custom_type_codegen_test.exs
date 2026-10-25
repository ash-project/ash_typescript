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

  setup_all do
    {:ok, content} = AshTypescript.Test.CodegenTestHelper.generate_all_content()
    %{content: content}
  end

  @doc false
  # A `typescript` MFA target: echoes the constraints it receives.
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

  describe "scalar entries (D40)" do
    test "CustomIdentifier's manifest scalar maps it as its base type", %{content: content} do
      assert content =~ "customId: string | null;"
      assert ts(CustomIdentifier) == "string"
      assert ts({:array, CustomIdentifier}) == "Array<string>"
    end

    test "a typescript MFA is called with the use's constraints" do
      entry = %Scalar{
        module: CustomIdentifier,
        type: Ash.Type.String,
        typescript: {__MODULE__, :echo_typescript, ["id"]}
      }

      with_entries(:declared, &Map.put(&1, CustomIdentifier, entry), fn ->
        assert ts(CustomIdentifier, foo: 1) == "id:[foo: 1]"
      end)
    end

    test "the test manifest's MFA scalar (ExternalCode)" do
      assert ts(ExternalCode) == "`code-${string}`"
    end

    test "a typescript MFA returning a non-string raises, naming the module and MFA" do
      entry = %Scalar{
        module: CustomIdentifier,
        type: Ash.Type.String,
        typescript: {__MODULE__, :non_string_typescript, []}
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

  describe "the order of TypeScript mappings for a scalar (Decision 20)" do
    test "a manifest scalar's typescript beats typescript_type_name/0" do
      entry = %Scalar{module: PriorityScore, type: Ash.Type.Integer, typescript: "number"}

      with_entries(:declared, &Map.put(&1, PriorityScore, entry), fn ->
        assert ts(PriorityScore) == "number"
      end)
    end

    test "a manifest scalar without typescript maps as its base type" do
      entry = %Scalar{module: PriorityScore, type: Ash.Type.Boolean}

      with_entries(:declared, &Map.put(&1, PriorityScore, entry), fn ->
        assert ts(PriorityScore) == "boolean"
      end)
    end

    test "typescript_type_name/0 beats a built-in scalar's typescript" do
      entry = %Scalar{module: PriorityScore, type: Ash.Type.Integer, typescript: "Builtin"}

      with_entries(:builtin, &Map.put(&1, PriorityScore, entry), fn ->
        assert ts(PriorityScore) == "CustomTypes.PriorityScore"
      end)
    end

    test "a built-in scalar applies to a type without a callback or manifest entry" do
      entry = %Scalar{module: CustomIdentifier, type: Ash.Type.String, typescript: "BuiltinId"}

      with_entries(:builtin, &Map.put(&1, CustomIdentifier, entry), fn ->
        with_entries(:declared, &Map.delete(&1, CustomIdentifier), fn ->
          assert ts(CustomIdentifier) == "BuiltinId"
        end)
      end)
    end
  end

  describe "constraints of a scalar's base mapping (Decision 36)" do
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

  describe "constraints of a scalar member's base mapping (Decision 36)" do
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

        assert theme =~ "code: string, codes?: Array<string> | null}"
        assert theme_map =~ ~s(code: "a" | "b", codes?: Array<"a" | "b"> | null})
      end)
    end
  end

  describe "scalar members keep their own mapping (D35, D40)" do
    @theme_result ~s({color: `#${string}`, accent: `#${string}` | null, score: CustomTypes.PriorityScore | null, code: `code-${string}`, codes: Array<`code-${string}`> | null, __type: "TypedMap", __primitiveFields: "color" | "accent" | "score" | "code" | "codes"} | null;)
    @theme_input ~s({color: `#${string}`, accent?: `#${string}` | null, score?: CustomTypes.PriorityScore | null, code: `code-${string}`, codes?: Array<`code-${string}`> | null} | null;)

    test "in a declared custom type's result TypedMap", %{content: content} do
      assert content =~ "theme: " <> @theme_result
    end

    test "in a NewType over :map's result TypedMap", %{content: content} do
      assert content =~ "themeMap: " <> @theme_result
    end

    test "in a declared custom type's input object", %{content: content} do
      assert content =~ "theme?: " <> @theme_input
    end

    test "in a NewType over :map's input object", %{content: content} do
      assert content =~ "themeMap?: " <> @theme_input
    end
  end

  describe "built-in scalars without aliases (D33)" do
    test "no ULID, Ltree or Money alias is generated" do
      aliases =
        Codegen.generate_ash_type_aliases([AshTypescript.Test.Task, AshTypescript.Test.Todo])

      refute aliases =~ "export type ULID"
      refute aliases =~ "AshPostgresLtreeArray"
      refute aliases =~ "AshPostgresLtreeFlexible"
      refute aliases =~ "export type Money"
    end

    test "Ltree attributes map per escape? through the built-in's MFA", %{content: content} do
      assert content =~ "  hierarchy: string | string[] | null;"
      assert content =~ "  strictHierarchy: string[] | null;"
      refute content =~ "AshPostgresLtree"
    end

    test "ULID maps as its base type" do
      assert ts(AshDoubleEntry.ULID) == "string"
    end
  end

  describe "the built-in Money entry (Task.price)" do
    test "the resource schema types it as a typed map of its fields", %{content: content} do
      assert content =~
               ~s(price: {currency: string, amount: Decimal, __type: "TypedMap", __primitiveFields: "currency" | "amount"} | null;)
    end

    test "the input type is an object of its fields", %{content: content} do
      assert content =~ "price?: {currency: string, amount: Decimal} | null;"
    end

    test "the zod and valibot schemas are objects of its fields", %{content: content} do
      assert content =~
               "price: z.object({ currency: z.string(), amount: z.string() }).nullable().optional(),"

      assert content =~
               "price: v.optional(v.nullable(v.object({ currency: v.string(), amount: v.string() }))),"
    end
  end

  describe "a type declaring typescript_fields/0 (Todo.color_palette)" do
    test "the input type is an object of its fields", %{content: content} do
      assert content =~
               "colorPalette?: {primary: string, secondary: string, accent: string} | null;"
    end

    test "the zod and valibot schemas are objects of its fields", %{content: content} do
      assert content =~
               "colorPalette: z.object({ primary: z.string(), secondary: z.string(), accent: z.string() })"

      assert content =~
               "colorPalette: v.optional(v.nullable(v.object({ primary: v.string(), secondary: v.string(), accent: v.string() })))"
    end
  end
end
