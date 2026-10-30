# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# Defines a resource or domain per scenario.
defmodule AshTypescript.Codegen.ScalarAliasesTest.Fixtures do
  @moduledoc false

  defmacro holder(name, type_name, attributes) do
    quote do
      defmodule unquote(name) do
        @moduledoc false
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name unquote(type_name)
        end

        attributes do
          integer_primary_key :id
          unquote_splicing(attributes)
        end

        actions do
          defaults [:read]
        end
      end
    end
  end

  defmacro domain(name, resource) do
    quote do
      defmodule unquote(name) do
        @moduledoc false
        use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource unquote(resource) do
            rpc_action :read, :read
          end
        end

        resources do
          resource unquote(resource)
        end
      end
    end
  end
end

defmodule AshTypescript.Codegen.ScalarAliasesTest do
  # Scalars that opt into an alias (a `scalar` entry's `ts_alias`,
  # `typescript_type_alias/0`, a built-in `ts_alias`) are declared once per
  # name in the primitive alias block and referenced at every position that
  # renders them; zod and valibot stay inline. The app fixtures are
  # `CustomIdentifier` (a string name), `ExternalCode` (an MFA name, inside
  # the declared `Theme`), Ltree's two built-in variants and the ULID stub;
  # the other cases use the fixtures below.
  use ExUnit.Case, async: false

  import AshTypescript.Test.CodegenTestHelper,
    only: [generate_files: 2, rpc_content: 1, types_content: 1, zod_content: 1]

  alias AshTypescript.Codegen.{
    ScalarAliases,
    SchemaCore,
    TypeAliases,
    TypeMapper,
    ZodSchemaGenerator
  }

  alias AshTypescript.Codegen.ScalarAliasesTest, as: T
  alias AshTypescript.Manifest.{Custom, TypeUses}
  alias AshTypescript.Test.InlineManifest
  alias AshTypescript.Test.PassThroughType

  # Named per use by an MFA `ts_alias`, from the uses' `max_length`.
  defmodule Mfa do
    @moduledoc false
    use PassThroughType, storage: :string, constraints: [max_length: [type: :integer]]
  end

  # One MFA name for two TypeScript types.
  defmodule TwoBodies do
    @moduledoc false
    use PassThroughType, storage: :string, constraints: [max_length: [type: :integer]]
  end

  defmodule Email do
    @moduledoc false
    use Ash.Type.NewType, subtype_of: :string
  end

  # A `scalar` entry over `:uuid` without a `ts_alias`.
  defmodule Opaque do
    @moduledoc false
    use PassThroughType, storage: :string
  end

  defmodule CallbackScalar do
    @moduledoc false
    use PassThroughType, storage: :string

    def typescript_type, do: "`cb-${string}`"
    def typescript_type_alias, do: "CallbackScalar"
  end

  # Used only as a route argument, and only in a channel payload.
  defmodule RouteOnly do
    @moduledoc false
    use PassThroughType, storage: :string
  end

  defmodule PayloadOnly do
    @moduledoc false
    use PassThroughType, storage: :string
  end

  # Used only as a union member.
  defmodule UnionOnly do
    @moduledoc false
    use PassThroughType, storage: :string

    def typescript_type, do: "string"
    def typescript_type_alias, do: "UnionOnly"
  end

  # A scalar whose `scalar` entry maps it as an atom with `one_of`, and a
  # declared custom type with a member of it.
  defmodule Choice do
    @moduledoc false
    use Ash.Type

    @impl true
    def constraints, do: [one_of: [type: {:list, :atom}]]
    @impl true
    def storage_type(_), do: :string
    @impl true
    def cast_input(value, _), do: {:ok, value}
    @impl true
    def cast_stored(value, _), do: {:ok, value}
    @impl true
    def dump_to_native(value, _), do: {:ok, value}
  end

  defmodule Report do
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

  defmodule Names do
    @moduledoc false
    def ts_type(_constraints), do: "string"

    def ts_alias(constraints) do
      case Keyword.get(constraints, :max_length) do
        nil -> nil
        max when max <= 10 -> "Short"
        _ -> "Long"
      end
    end

    def by_length(constraints) do
      if Keyword.get(constraints, :max_length, 0) <= 10, do: "string", else: "number"
    end

    def same(_constraints), do: "Same"

    # `{Names, :fixed, [name]}` returns `name` at every use.
    def fixed(_constraints, name), do: name
  end

  import AshTypescript.Codegen.ScalarAliasesTest.Fixtures

  holder(MfaHolder, "ScalarAliasesMfaHolder", [
    attribute(:short, T.Mfa, public?: true, constraints: [max_length: 5]),
    attribute(:long, T.Mfa, public?: true, constraints: [max_length: 50]),
    attribute(:plain, T.Mfa, public?: true)
  ])

  holder(TwoBodiesHolder, "ScalarAliasesTwoBodiesHolder", [
    attribute(:short, T.TwoBodies, public?: true, constraints: [max_length: 5]),
    attribute(:long, T.TwoBodies, public?: true, constraints: [max_length: 50])
  ])

  holder(EmailHolder, "ScalarAliasesEmailHolder", [
    attribute(:email, T.Email, public?: true)
  ])

  holder(UuidHolder, "ScalarAliasesUuidHolder", [
    attribute(:opaque, T.Opaque, public?: true)
  ])

  holder(UnionHolder, "ScalarAliasesUnionHolder", [
    attribute(:pick, :union,
      public?: true,
      constraints: [types: [only: [type: T.UnionOnly], text: [type: :string]]]
    )
  ])

  holder(ReportHolder, "ScalarAliasesReportHolder", [
    attribute(:report, T.Report, public?: true)
  ])

  holder(CallbackHolder, "ScalarAliasesCallbackHolder", [
    attribute(:hex, AshTypescript.Test.HexColor, public?: true),
    attribute(:callback, T.CallbackScalar, public?: true)
  ])

  domain(MfaDomain, T.MfaHolder)
  domain(TwoBodiesDomain, T.TwoBodiesHolder)
  domain(EmailDomain, T.EmailHolder)
  domain(UuidDomain, T.UuidHolder)
  domain(CallbackDomain, T.CallbackHolder)
  domain(ReportDomain, T.ReportHolder)
  domain(UnionDomain, T.UnionHolder)

  defmodule RouteController do
    @moduledoc false
    use AshTypescript.TypedController

    typed_controller do
      module_name AshTypescript.Codegen.ScalarAliasesTest.RouteControllerImpl

      get :lookup do
        run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "") end
        argument :code, AshTypescript.Codegen.ScalarAliasesTest.RouteOnly
      end
    end
  end

  defmodule Item do
    @moduledoc false
    use Ash.Resource,
      domain: nil,
      notifiers: [Ash.Notifier.PubSub]

    pub_sub do
      module AshTypescript.Test.TestEndpoint
      prefix "scalar_aliases"

      publish :create, [:id],
        event: "scalar_aliases_created",
        public?: true,
        returns: :map,
        constraints: [fields: [code: [type: AshTypescript.Codegen.ScalarAliasesTest.PayloadOnly]]],
        transform: fn _notification -> %{code: "x"} end
    end

    attributes do
      uuid_primary_key :id
    end

    actions do
      defaults [:read, :create]
    end
  end

  defmodule ItemChannel do
    @moduledoc false
    use Phoenix.Channel
    use AshTypescript.TypedChannel

    typed_channel do
      topic "scalar_aliases:*"

      resource AshTypescript.Codegen.ScalarAliasesTest.Item do
        publish :scalar_aliases_created
      end
    end

    @impl true
    def join(_topic, _payload, socket), do: {:ok, socket}
  end

  setup_all do
    {:ok, files} = generate_files(:ash_typescript, [])
    %{types: types_content(files), rpc: rpc_content(files), zod: zod_content(files)}
  end

  defp manifest(domain, entries) do
    InlineManifest.build!(
      domains: [domain],
      body:
        quote do
          custom_types do
            unquote(entries)
          end
        end
    )
  end

  defp aliases(manifest, resource) do
    AshTypescript.with_manifest(manifest, fn ->
      TypeAliases.generate_ash_type_aliases([resource], AshTypescript.resource_lookup(), [])
    end)
  end

  defp attribute_ts(manifest, resource, name) do
    AshTypescript.with_manifest(manifest, fn ->
      TypeMapper.map_type(field(resource, name), [], :output)
    end)
  end

  defp attribute_zod(manifest, resource, name) do
    AshTypescript.with_manifest(manifest, fn ->
      SchemaCore.get_type(ZodSchemaGenerator, field(resource, name))
    end)
  end

  defp field(resource, name) do
    AshTypescript.resource_lookup()
    |> Map.fetch!(resource)
    |> Map.fetch!(:fields)
    |> Map.values()
    |> Enum.find(&(&1.name == name))
    |> Map.fetch!(:type)
  end

  defp index_of(content, text) do
    case :binary.match(content, text) do
      {index, _} -> index
      :nomatch -> flunk("#{inspect(text)} not found")
    end
  end

  # The body of the top-level type declared by `header`.
  defp block(content, header), do: body(content, header, "\n};")

  # The body of the nested object type `header` (`  name?: {`) of a block.
  defp nested(block, header), do: body(block, header, "\n  };")

  defp body(content, header, terminator) do
    [_, rest] = String.split(content, header, parts: 2)
    rest |> String.split(terminator, parts: 2) |> hd()
  end

  describe "the app fixtures" do
    test "a constant-name scalar is declared once and referenced at schema, input and filter positions",
         %{types: types, rpc: rpc, zod: zod} do
      line = "export type CustomIdentifier = string;\n"

      assert [_, _] = String.split(types, line)
      assert index_of(types, "export type AshVector = ") < index_of(types, line)
      assert index_of(types, line) < index_of(types, "export type Decimal = ")

      assert block(types, "export type TaskResourceSchema = {") =~
               "  customId: CustomIdentifier | null;"

      customid_filter =
        types |> block("export type TaskFilterInput = {") |> nested("  customId?: {")

      assert customid_filter =~ "eq?: CustomIdentifier;"
      assert customid_filter =~ "in?: Array<CustomIdentifier>;"
      refute customid_filter =~ "string"

      assert rpc =~ "  customId?: CustomIdentifier | null;"
      refute rpc =~ "customId?: string"
      assert zod =~ "customId: CustomZodSchemas.objectId"
    end

    test "an MFA-named scalar inside a declared type's alias", %{types: types} do
      assert types =~ "export type ExternalCode = `code-${string}`;\n"

      assert types =~
               ~r/export type Theme = \{[^\n]*code: ExternalCode, codes: Array<ExternalCode> \| null\};/

      assert types =~
               ~r/export type ThemeInput = \{[^\n]*code: ExternalCode, codes\?: Array<ExternalCode> \| null\};/

      refute types =~ "code-${string}`, codes"
    end

    test "Ltree's two variants", %{types: types, rpc: rpc} do
      assert types =~ "export type AshPostgresLtreeArray = string[];\n"
      assert types =~ "export type AshPostgresLtreeFlexible = string | string[];\n"

      schema = block(types, "export type TodoResourceSchema = {")
      assert schema =~ "  hierarchy: AshPostgresLtreeFlexible | null;"
      assert schema =~ "  strictHierarchy: AshPostgresLtreeArray | null;"

      filter = block(types, "export type TodoFilterInput = {")
      assert filter |> nested("  hierarchy?: {") =~ "eq?: AshPostgresLtreeFlexible;"
      assert filter |> nested("  strictHierarchy?: {") =~ "eq?: AshPostgresLtreeArray;"

      assert rpc =~ "  hierarchy?: AshPostgresLtreeFlexible | null;"
      assert rpc =~ "  strictHierarchy?: AshPostgresLtreeArray | null;"
      refute rpc =~ "hierarchy?: string"
      refute rpc =~ "Hierarchy?: string"
    end

    test "ULID", %{types: types, rpc: rpc} do
      assert types =~ "export type ULID = string;\n"
      assert block(rpc, "export type EchoUlidInput = {") =~ "  ulid: ULID;"
      assert rpc =~ "export type InferEchoUlidResult = ULID;"
    end

    test "the RPC file imports the names it uses", %{rpc: rpc} do
      import_line =
        rpc |> String.split("\n") |> Enum.find(&String.starts_with?(&1, "import type {"))

      # ExternalCode through the inline ThemeMap inputs.
      for name <-
            ~w(AshPostgresLtreeArray AshPostgresLtreeFlexible CustomIdentifier ExternalCode ULID) do
        assert import_line =~ ~r/\b#{name}\b/
      end

      assert rpc =~ "code: ExternalCode, codes?: Array<ExternalCode> | null}"
    end
  end

  describe "inline manifests" do
    test "an MFA name with two variants emits two aliases, each use its own" do
      manifest =
        manifest(
          T.MfaDomain,
          quote do
            scalar AshTypescript.Codegen.ScalarAliasesTest.Mfa, :string,
              ts_type: {AshTypescript.Codegen.ScalarAliasesTest.Names, :ts_type, []},
              ts_alias: {AshTypescript.Codegen.ScalarAliasesTest.Names, :ts_alias, []}
          end
        )

      lines = manifest |> aliases(T.MfaHolder) |> String.split("\n")

      assert "export type Short = string;" in lines
      assert "export type Long = string;" in lines
      assert Enum.count(lines, &(&1 =~ ~r/^export type \w+ = string;$/)) == 2

      assert attribute_ts(manifest, T.MfaHolder, :short) == "Short"
      assert attribute_ts(manifest, T.MfaHolder, :long) == "Long"
      assert attribute_ts(manifest, T.MfaHolder, :plain) == "string"
    end

    test "a scalar member of a declared type's alias maps with its own constraints" do
      manifest =
        manifest(
          T.ReportDomain,
          quote do
            scalar AshTypescript.Codegen.ScalarAliasesTest.Choice, :atom,
              constraints: [one_of: [:a, :b]],
              ts_alias: "Choice"

            map AshTypescript.Codegen.ScalarAliasesTest.Report do
              ts_alias "ScalarAliasesReport"

              field :choice, AshTypescript.Codegen.ScalarAliasesTest.Choice,
                constraints: [one_of: [:x, :y]]
            end
          end
        )

      lines = manifest |> aliases(T.ReportHolder) |> String.split("\n")

      # The member's `one_of`, not the entry's.
      assert ~s(export type Choice = "x" | "y";) in lines
      assert "export type ScalarAliasesReport = {choice: Choice | null};" in lines
    end

    test "a scalar used only as a union member is declared" do
      manifest = InlineManifest.build!(domains: [T.UnionDomain], body: nil)

      assert aliases(manifest, T.UnionHolder) =~ "export type UnionOnly = string;"
    end

    test "the fields of struct argument resources are roots" do
      manifest = InlineManifest.build!(domains: [T.UnionDomain], body: nil)

      AshTypescript.with_manifest(manifest, fn ->
        lookup = AshTypescript.resource_lookup()

        refute TypeAliases.generate_ash_type_aliases([], lookup, []) =~ "UnionOnly"

        assert TypeAliases.generate_ash_type_aliases([], lookup, [],
                 struct_argument_resources: [T.UnionHolder]
               ) =~ "export type UnionOnly = string;"
      end)
    end

    test "one name with two bodies is a codegen error" do
      manifest =
        manifest(
          T.TwoBodiesDomain,
          quote do
            scalar AshTypescript.Codegen.ScalarAliasesTest.TwoBodies, :string,
              ts_type: {AshTypescript.Codegen.ScalarAliasesTest.Names, :by_length, []},
              ts_alias: {AshTypescript.Codegen.ScalarAliasesTest.Names, :same, []}
          end
        )

      assert {:error, message} = catch_throw(aliases(manifest, T.TwoBodiesHolder))
      assert message =~ "`Same`"
      assert message =~ "`string`"
      assert message =~ "`number`"
      assert message =~ inspect(T.TwoBodies)
    end

    test "an MFA ts_alias result that can't be exported fails, at the use and in the alias block" do
      cases = [
        {"my-code", "string", "is not a TypeScript identifier."},
        {"string", "number", "is a TypeScript reserved word."},
        {"Array", "string", "is a global TypeScript name the generated code uses."},
        {"Promise", "string", "is a global TypeScript name the generated code uses."},
        {"Decimal", "string", "is a type ash_typescript generates: return another name."},
        {"InferResult", "string", "is a type ash_typescript generates: return another name."},
        {"Code", "Code",
         "is its ts_type at that use, so the alias would alias itself " <>
           "(`export type Code = Code;`): return another name, or nil to keep the use inline."}
      ]

      for {name, ts_type, reason} <- cases do
        manifest =
          manifest(
            T.MfaDomain,
            quote do
              scalar AshTypescript.Codegen.ScalarAliasesTest.Mfa, :string,
                ts_type:
                  {AshTypescript.Codegen.ScalarAliasesTest.Names, :fixed, [unquote(ts_type)]},
                ts_alias: {AshTypescript.Codegen.ScalarAliasesTest.Names, :fixed, [unquote(name)]}
            end
          )

        expected =
          "The result #{inspect(name)} of the `ts_alias` MFA #{inspect(T.Names)}.fixed/2 " <>
            "of the custom type #{inspect(T.Mfa)} #{reason}"

        assert catch_throw(attribute_ts(manifest, T.MfaHolder, :short)) == {:error, expected}
        assert catch_throw(aliases(manifest, T.MfaHolder)) == {:error, expected}
      end
    end

    test "an MFA ts_alias result that is a valid name is used" do
      manifest =
        manifest(
          T.MfaDomain,
          quote do
            scalar AshTypescript.Codegen.ScalarAliasesTest.Mfa, :string,
              ts_type: {AshTypescript.Codegen.ScalarAliasesTest.Names, :fixed, ["string"]},
              ts_alias: {AshTypescript.Codegen.ScalarAliasesTest.Names, :fixed, ["MfaCode"]}
          end
        )

      assert attribute_ts(manifest, T.MfaHolder, :short) == "MfaCode"
      assert aliases(manifest, T.MfaHolder) =~ "export type MfaCode = string;"
    end

    test "a NewType over :string with a ts_alias is aliased, zod unchanged" do
      aliased =
        manifest(
          T.EmailDomain,
          quote do
            scalar AshTypescript.Codegen.ScalarAliasesTest.Email, :string, ts_alias: "Email"
          end
        )

      plain = InlineManifest.build!(domains: [T.EmailDomain], body: nil)

      assert aliases(aliased, T.EmailHolder) =~ "export type Email = string;"
      assert attribute_ts(aliased, T.EmailHolder, :email) == "Email"
      refute aliases(plain, T.EmailHolder) =~ "Email"

      zod = attribute_zod(aliased, T.EmailHolder, :email)
      assert zod == attribute_zod(plain, T.EmailHolder, :email)
      refute zod =~ "Email"
    end

    test "a scalar X, :uuid declares UUID with no other UUID use" do
      manifest =
        manifest(
          T.UuidDomain,
          quote do
            scalar AshTypescript.Codegen.ScalarAliasesTest.Opaque, :uuid
          end
        )

      assert attribute_ts(manifest, T.UuidHolder, :opaque) == "UUID"
      assert aliases(manifest, T.UuidHolder) =~ "export type UUID = string;"
    end

    test "a scalar's alias body is its typescript_type/0" do
      manifest =
        manifest(
          T.CallbackDomain,
          quote do
            scalar AshTypescript.Test.HexColor, :string, ts_alias: "Hex"
          end
        )

      unaliased = InlineManifest.build!(domains: [T.CallbackDomain], body: nil)
      lines = manifest |> aliases(T.CallbackHolder) |> String.split("\n")

      assert "export type Hex = `#${string}`;" in lines
      assert "export type CallbackScalar = `cb-${string}`;" in lines
      assert attribute_ts(manifest, T.CallbackHolder, :hex) == "Hex"
      assert attribute_ts(manifest, T.CallbackHolder, :callback) == "CallbackScalar"

      assert attribute_zod(manifest, T.CallbackHolder, :hex) ==
               attribute_zod(unaliased, T.CallbackHolder, :hex)
    end
  end

  describe "uses outside RPC resources" do
    setup do
      manifest =
        InlineManifest.build!(
          typed_controllers: [T.RouteController],
          typed_channels: [T.ItemChannel],
          body:
            InlineManifest.app_custom_types([
              quote do
                scalar AshTypescript.Codegen.ScalarAliasesTest.RouteOnly, :string,
                  ts_alias: "RouteOnlyId"
              end,
              quote do
                scalar AshTypescript.Codegen.ScalarAliasesTest.PayloadOnly, :string,
                  ts_alias: "PayloadOnlyId"
              end
            ])
        )

      {:ok, files} = generate_files(:ash_typescript, manifest: manifest)
      %{types: types_content(files)}
    end

    test "a scalar used only in a route is declared", %{types: types} do
      assert types =~ "export type RouteOnlyId = string;\n"
    end

    test "a scalar used only in a channel payload is declared", %{types: types} do
      assert types =~ "export type PayloadOnlyId = string;\n"
      assert types =~ ~r/code\??: PayloadOnlyId/
    end
  end

  test "an invalid MFA ts_alias result fails codegen" do
    manifest =
      InlineManifest.build!(
        typed_controllers: [T.RouteController],
        body:
          InlineManifest.app_custom_types([
            quote do
              scalar AshTypescript.Codegen.ScalarAliasesTest.RouteOnly, :string,
                ts_type: {AshTypescript.Codegen.ScalarAliasesTest.Names, :fixed, ["string"]},
                ts_alias: {AshTypescript.Codegen.ScalarAliasesTest.Names, :fixed, ["my-code"]}
            end
          ])
      )

    assert generate_files(:ash_typescript, manifest: manifest) ==
             {:error,
              ~s(The result "my-code" of the `ts_alias` MFA #{inspect(T.Names)}.fixed/2 ) <>
                "of the custom type #{inspect(T.RouteOnly)} is not a TypeScript identifier."}
  end

  test "every scalar alias a generated file mentions is declared in the types file" do
    {:ok, files} = generate_files(:ash_typescript, [])
    types_path = AshTypescript.types_output_file()
    types = Map.fetch!(files, types_path)
    custom_types = Custom.custom_types(nil)

    names =
      AshTypescript.manifest()
      |> TypeUses.nodes()
      |> Enum.uniq()
      |> Enum.map(&ScalarAliases.name(&1, custom_types))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    assert names != []

    for name <- names,
        {path, content} <- files,
        path != types_path,
        content =~ ~r/\b#{name}\b/ do
      assert types =~ "export type #{name} = ", "#{path} mentions #{name}, which isn't declared"
    end
  end
end
