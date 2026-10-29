# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.NamedCustomTypesTest do
  # Declared custom types get an exported alias in the types file (plus an
  # `Input` alias when the input rendering differs), referenced at input
  # positions. Plain positions (filter values, metadata, identity and getBy
  # values) carry no field-selection markers and reference the aliases too.
  # Schema positions (resource schemas, field selection, generic action
  # results) stay inline.
  use ExUnit.Case, async: false

  import AshTypescript.Test.CodegenTestHelper, only: [rpc_content: 1, types_content: 1]

  alias AshTypescript.Rpc.Codegen.Helpers.ConfigBuilder
  alias AshTypescript.Test.Task

  @theme_plain ~s({color: `#${string}`, accent: `#${string}` | null, score: CustomTypes.PriorityScore | null, code: ExternalCode, codes: Array<ExternalCode> | null})
  @theme_input ~s({color: `#${string}`, accent?: `#${string}` | null, score?: CustomTypes.PriorityScore | null, code: ExternalCode, codes?: Array<ExternalCode> | null})

  setup_all do
    {:ok, files} = AshTypescript.Test.CodegenTestHelper.generate_files()
    %{types: types_content(files), rpc: rpc_content(files)}
  end

  defp lines(content), do: String.split(content, "\n")

  defp line_starting(content, prefix),
    do: content |> lines() |> Enum.find(&String.starts_with?(&1, prefix))

  defp index!(content, text) do
    case :binary.match(content, text) do
      {index, _} -> index
      :nomatch -> flunk("#{inspect(text)} not found")
    end
  end

  describe "aliases" do
    test "each declared custom type gets an alias", %{types: types} do
      expected = [
        "export type Money = {currency: string, amount: Decimal};",
        "export type GeoPoint = {lat: number, lng: number};",
        "export type ColorPalette = {primary: string, secondary: string, accent: string};",
        "export type Theme = #{@theme_plain};",
        "export type LineItem = {label: string, price: Money, meta: TaskMetadataResourceSchema | null};"
      ]

      for line <- expected, do: assert(line in lines(types), "missing line: #{line}")
    end

    test "an Input alias only where the input rendering differs", %{types: types} do
      assert "export type ThemeInput = #{@theme_input};" in lines(types)

      assert "export type LineItemInput = {label: string, price: Money, meta?: TaskMetadataInputSchema | null};" in lines(
               types
             )

      refute types =~ "MoneyInput"
      refute types =~ "GeoPointInput"
      refute types =~ "ColorPaletteInput"
    end

    test "a type reaching a non-embedded resource gets only its plain alias", %{types: types} do
      assert "export type AshTypescriptTestTodoRef = {todo: TodoResourceSchema | null};" in lines(
               types
             )

      refute types =~ "TodoRefInput"
      refute types =~ "{todo?: TodoInputSchema"
    end

    test "a NewType over :map gets no alias", %{types: types} do
      refute types =~ "export type ThemeMap"
    end

    test "declared definitions are roots for the primitive aliases" do
      # No resources: Decimal is declared because Money's alias uses it.
      aliases = AshTypescript.Codegen.TypeAliases.generate_ash_type_aliases([], %{}, [])

      assert "export type Decimal = string;" in lines(aliases)
      assert "export type Money = {currency: string, amount: Decimal};" in lines(aliases)
    end

    test "aliases are sorted and follow the primitive aliases", %{types: types} do
      indexes =
        Enum.map(
          [
            "export type Decimal",
            "// Declared custom types",
            "export type ColorPalette",
            "export type GeoPoint",
            "export type LineItem",
            "export type Money",
            "export type Theme"
          ],
          &index!(types, &1)
        )

      assert indexes == Enum.sort(indexes)
    end
  end

  describe "input references" do
    test "Task inputs reference the aliases; a NewType over :map stays inline", %{rpc: rpc} do
      refute rpc =~ "price?: {currency"
      refute rpc =~ "geoPoint?: {lat"
      assert rpc =~ "  geoPoint?: GeoPoint | null;"
      refute rpc =~ "theme?: {color"
      assert rpc =~ "  themeMap?: #{@theme_input} | null;"
    end

    test "RPC input types reference the aliases", %{rpc: rpc} do
      create_task = rpc |> String.split("export type CreateTaskInput = {") |> Enum.at(1)
      create_task = create_task |> String.split("};") |> hd()

      assert create_task =~ "  price?: Money | null;"
      assert create_task =~ "  theme?: ThemeInput | null;"

      create_todo = rpc |> String.split("export type CreateTodoInput = {") |> Enum.at(1)
      create_todo = create_todo |> String.split("};") |> hd()

      assert create_todo =~ "  colorPalette?: ColorPalette | null;"

      assert rpc =~ "export type EchoLineItemInput = {\n  lineItem: LineItemInput;\n};"
    end

    test "a calculation argument references the input alias", %{types: types} do
      assert types =~
               ~s(  themeLabel: { __type: "ComplexCalculation"; __returnType: string | null; __args: { theme: ThemeInput }; };)
    end

    test "a union input member references the input alias", %{rpc: rpc} do
      assert rpc =~
               "export type DescribeStyleInput = {\n  style: { theme: ThemeInput } | { label: string };\n};"
    end

    test "the RPC file imports the aliases it uses", %{rpc: rpc} do
      import_line = line_starting(rpc, "import type {") |> String.trim_trailing()
      assert import_line =~ ~s(} from "./ash_types";)

      names =
        import_line
        |> String.replace(~r/^import type \{ | \} from .*$/, "")
        |> String.split(", ")

      for name <- ~w(ColorPalette GeoPoint LineItemInput Money ThemeInput) do
        assert name in names, "#{name} not imported"
      end
    end
  end

  describe "plain positions" do
    test "filter values reference the alias", %{types: types} do
      price = filter_block(types, "TaskFilterInput", "price")
      assert price =~ "    eq?: Money;\n"
      assert price =~ "    notEq?: Money;\n"
      assert price =~ "    in?: Array<Money>;\n"

      assert filter_block(types, "TaskFilterInput", "geoPoint") =~ "    eq?: GeoPoint;\n"
      assert filter_block(types, "TaskFilterInput", "theme") =~ "    eq?: Theme;\n"
      assert filter_block(types, "TodoFilterInput", "colorPalette") =~ "    eq?: ColorPalette;\n"
    end

    test "filter values of other typed maps are plain", %{types: types} do
      assert types =~
               "    eq?: {totalCount1: number, isComplete: boolean | null, lastUpdatedAt: UtcDateTime | null};\n"

      refute types =~ ~r/^    eq\?: \{totalCount1.*__type/m
    end

    test "union filter values keep their schema form", %{types: types} do
      content = filter_block(types, "InputParsingResourceFilterInput", "content")

      assert content =~
               ~s(    eq?: { __type: "Union"; __primitiveFields: "simpleValue"; text?: InputParsingTextContentResourceSchema; data?: {itemCount: number, isCached: boolean | null, __type: "TypedMap", __primitiveFields: "itemCount" | "isCached"}; simpleValue?: string; };)
    end

    test "metadata values are plain", %{rpc: rpc} do
      assert rpc =~
               """
               export type ReadTasksWithTypedMapMetadataMetadata = {
                 auditEntries?: Array<{fieldName: string | null, oldValue: string | null}>;
                 completionInfo?: {completedAt: string | null, completedBy: string | null};
                 total?: Money;
               };
               """
    end

    test "identity values use the input mapping" do
      assert ConfigBuilder.build_identity_config_field(
               Task,
               [:_primary_key],
               [],
               lookup_with_id_typed_as(:price)
             ) == ["  identity: Money;"]

      assert ConfigBuilder.build_identity_config_field(
               Task,
               [:_primary_key],
               [],
               lookup_with_id_typed_as(:theme)
             ) == ["  identity: ThemeInput;"]
    end

    test "getBy values use the input mapping" do
      assert ConfigBuilder.build_get_by_config_field(
               Task,
               %{get_by: [:id]},
               lookup_with_id_typed_as(:theme)
             ) == ["  getBy: {", "    id: ThemeInput;", "  };"]
    end
  end

  # The `field` block of the `filter_type` filter input type.
  defp filter_block(types, filter_type, field) do
    [_, after_type] = String.split(types, "export type #{filter_type} = {\n", parts: 2)
    [_, block] = String.split(after_type, "\n  #{field}?: {\n", parts: 2)
    block |> String.split("\n  };", parts: 2) |> hd() |> Kernel.<>("\n")
  end

  # The resource lookup, with Task's `id` typed as the `source` field's type.
  defp lookup_with_id_typed_as(source) do
    lookup = AshTypescript.resource_lookup()
    task = Map.fetch!(lookup, Task)
    source_type = Map.fetch!(task.fields, source).type
    fields = Map.update!(task.fields, :id, &%{&1 | type: source_type})
    Map.put(lookup, Task, %{task | fields: fields})
  end

  describe "schema positions stay inline" do
    test "resource schemas", %{types: types} do
      assert types =~
               ~s(  price: {currency: string, amount: Decimal, __type: "TypedMap", __primitiveFields: "currency" | "amount"} | null;)

      assert types =~
               ~s(  theme: {color: `#${string}`, accent: `#${string}` | null, score: CustomTypes.PriorityScore | null, code: ExternalCode, codes: Array<ExternalCode> | null, __type: "TypedMap", __primitiveFields: "color" | "accent" | "score" | "code" | "codes"} | null;)
    end

    test "a generic action's result and field selection", %{rpc: rpc} do
      fields = line_starting(rpc, "export type EchoLineItemFields = ")
      result = rpc |> String.split("export type InferEchoLineItemResult<") |> Enum.at(1)
      result = result |> String.split("\n\n") |> hd()

      for body <- [fields, result] do
        assert body =~ ~s(__type: "TypedMap")
        refute body =~ ~r/\b(LineItem|Money)\b/
      end
    end
  end
end
