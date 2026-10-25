# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.CustomTypeSchemaTest do
  @moduledoc """
  Tests validation-schema generation for custom Ash types.

  A hand-rolled `use Ash.Type` module (`kind: :unknown`) is resolved in this
  order (D40):

  1. a `scalar` entry in the manifest's `custom_types` section: its `zod` /
     `valibot`, else its base type;
  2. the formatter's `simple_primitives`;
  3. a built-in `scalar` entry (`AshTypescript.CustomTypes.Builtin`);
  4. a schema derived from the type's `storage_type/1`.

  A declared custom type (a `:type_ref` to its definition) uses its `map`
  entry's `zod` / `valibot` when it has one, else an object of its fields.
  Variants of the test manifest go through `AshTypescript.with_manifest/2`.
  """
  use ExUnit.Case, async: false

  alias Ash.Info.Manifest.Generator.TypeResolver
  alias Ash.Info.Manifest.Type, as: SpecType
  alias AshTypescript.Codegen.SchemaCore
  alias AshTypescript.Codegen.ValibotSchemaGenerator
  alias AshTypescript.Codegen.ZodSchemaGenerator
  alias AshTypescript.CustomTypes.{MapType, Scalar}
  alias AshTypescript.Test.{ExternalCode, GeoPoint, Theme, ThemeMap}
  alias AshTypescript.Test.Todo.PriorityScore
  alias AshTypescript.TypeSystem.Introspection

  defmodule IntegerStorageType do
    @moduledoc false
    use Ash.Type

    @impl true
    def storage_type(_), do: :integer
    @impl true
    def cast_input(v, _), do: {:ok, v}
    @impl true
    def cast_stored(v, _), do: {:ok, v}
    @impl true
    def dump_to_native(v, _), do: {:ok, v}

    def typescript_type_name, do: "IntegerStorage"
  end

  defmodule DatetimeStorageType do
    @moduledoc false
    use Ash.Type

    @impl true
    def storage_type(_), do: :utc_datetime_usec
    @impl true
    def cast_input(v, _), do: {:ok, v}
    @impl true
    def cast_stored(v, _), do: {:ok, v}
    @impl true
    def dump_to_native(v, _), do: {:ok, v}

    def typescript_type_name, do: "DatetimeStorage"
  end

  defmodule ArrayStorageType do
    @moduledoc false
    use Ash.Type

    @impl true
    def storage_type(_), do: {:array, :string}
    @impl true
    def cast_input(v, _), do: {:ok, v}
    @impl true
    def cast_stored(v, _), do: {:ok, v}
    @impl true
    def dump_to_native(v, _), do: {:ok, v}

    def typescript_type_name, do: "ArrayStorage"
  end

  defmodule MapStorageType do
    @moduledoc false
    use Ash.Type

    @impl true
    def storage_type(_), do: :map
    @impl true
    def cast_input(v, _), do: {:ok, v}
    @impl true
    def cast_stored(v, _), do: {:ok, v}
    @impl true
    def dump_to_native(v, _), do: {:ok, v}

    def typescript_type_name, do: "MapStorage"
  end

  defmodule OpaqueStorageType do
    @moduledoc false
    use Ash.Type

    @impl true
    def storage_type(_), do: :some_unmappable_thing
    @impl true
    def cast_input(v, _), do: {:ok, v}
    @impl true
    def cast_stored(v, _), do: {:ok, v}
    @impl true
    def dump_to_native(v, _), do: {:ok, v}

    def typescript_type_name, do: "OpaqueStorage"
  end

  defmodule NewGeoPoint do
    @moduledoc false
    use Ash.Type.NewType, subtype_of: AshTypescript.Test.GeoPoint
  end

  defmodule NewGeoPointWithFields do
    @moduledoc false
    use Ash.Type.NewType, subtype_of: AshTypescript.Test.GeoPoint

    def typescript_fields, do: [x: [type: :integer]]
  end

  @doc false
  # A `zod` / `valibot` MFA target: echoes the constraints it receives.
  def echo_schema(constraints, tag), do: "#{tag}:#{inspect(constraints)}"

  @doc false
  def non_string_schema(_constraints), do: :not_a_string

  defp zod(type, constraints \\ []),
    do: SchemaCore.get_type(ZodSchemaGenerator, TypeResolver.resolve(type, constraints))

  defp valibot(type, constraints \\ []),
    do: SchemaCore.get_type(ValibotSchemaGenerator, TypeResolver.resolve(type, constraints))

  defp ref_zod(module),
    do: SchemaCore.get_type(ZodSchemaGenerator, %SpecType{kind: :type_ref, module: module})

  defp ref_valibot(module),
    do: SchemaCore.get_type(ValibotSchemaGenerator, %SpecType{kind: :type_ref, module: module})

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

  defp declare(entry, fun), do: with_entries(:declared, &Map.put(&1, entry.module, entry), fun)

  defp regex(source), do: {Spark.Regex, :cache, [source, []]}

  describe "storage-derived fallback" do
    test "an integer-storage custom type validates as a number, not a string" do
      assert zod(PriorityScore) == "z.number().int()"
      assert valibot(PriorityScore) == "v.pipe(v.number(), v.integer())"
    end

    test "a map-storage custom type validates as a record, not a string" do
      assert zod(MapStorageType) == "z.record(z.string(), z.any())"
      assert valibot(MapStorageType) == "v.record(v.string(), v.any())"
    end

    test "derives from storage for datetime-backed types" do
      assert zod(DatetimeStorageType) == "z.iso.datetime()"
      assert valibot(DatetimeStorageType) == "v.pipe(v.string(), v.isoTimestamp())"
    end

    test "derives an array schema for array storage" do
      assert zod(ArrayStorageType) == "z.array(z.string())"
      assert valibot(ArrayStorageType) == "v.array(v.string())"
    end

    test "unmappable storage stays permissive rather than guessing" do
      # A wrong schema rejects valid data, which is worse than not validating.
      assert zod(OpaqueStorageType) == "z.any()"
      assert valibot(OpaqueStorageType) == "v.any()"
    end
  end

  describe "scalar entries" do
    test "an entry's zod and valibot replace the storage-derived schema" do
      entry = %Scalar{
        module: IntegerStorageType,
        type: Ash.Type.Integer,
        zod: ~s{z.string().brand<"Id">()},
        valibot: "v.string()"
      }

      declare(entry, fn ->
        assert zod(IntegerStorageType) == ~s{z.string().brand<"Id">()}
        assert valibot(IntegerStorageType) == "v.string()"
      end)
    end

    test "each library reads its own option" do
      entry = %Scalar{module: IntegerStorageType, type: Ash.Type.Integer, zod: "z.string()"}

      declare(entry, fn ->
        assert zod(IntegerStorageType) == "z.string()"
        # No valibot schema: valibot maps the entry's base type.
        assert valibot(IntegerStorageType) == "v.pipe(v.number(), v.integer())"
      end)
    end

    test "an entry without a schema maps as its base type, not the storage type" do
      entry = %Scalar{module: IntegerStorageType, type: Ash.Type.Boolean}

      declare(entry, fn ->
        assert zod(IntegerStorageType) == "z.boolean()"
        assert valibot(IntegerStorageType) == "v.boolean()"
      end)
    end

    test "an entry with a match constraint gives the regex" do
      entry = %Scalar{
        module: IntegerStorageType,
        type: Ash.Type.String,
        constraints: [match: regex("^id-[0-9]+$"), max_length: 12]
      }

      declare(entry, fn ->
        assert zod(IntegerStorageType) =~ "z.string()"
        assert zod(IntegerStorageType) =~ ".max(12).regex(/^id-[0-9]+$/)"
        assert valibot(IntegerStorageType) =~ "v.maxLength(12)"
        assert valibot(IntegerStorageType) =~ "v.regex(/^id-[0-9]+$/)"
      end)
    end

    test "an MFA zod or valibot is called with the use's constraints" do
      entry = %Scalar{
        module: IntegerStorageType,
        type: Ash.Type.Integer,
        zod: {__MODULE__, :echo_schema, ["zod"]},
        valibot: {__MODULE__, :echo_schema, ["valibot"]}
      }

      declare(entry, fn ->
        assert zod(IntegerStorageType, foo: 1) == "zod:[foo: 1]"
        assert valibot(IntegerStorageType, foo: 1) == "valibot:[foo: 1]"
      end)
    end

    test "an MFA returning a non-string raises, naming the module and MFA" do
      entry = %Scalar{
        module: IntegerStorageType,
        type: Ash.Type.Integer,
        zod: {__MODULE__, :non_string_schema, []}
      }

      declare(entry, fn ->
        error = assert_raise ArgumentError, fn -> zod(IntegerStorageType) end
        message = Exception.message(error)
        assert message =~ "`zod`"
        assert message =~ inspect(IntegerStorageType)
        assert message =~ "AshTypescript.Rpc.CustomTypeSchemaTest.non_string_schema/1"
        assert message =~ ":not_a_string"
      end)
    end

    test "an entry is per module" do
      entry = %Scalar{module: IntegerStorageType, type: Ash.Type.Integer, zod: "z.string()"}

      declare(entry, fn -> assert zod(PriorityScore) == "z.number().int()" end)
    end

    test "the test manifest's MFA scalar (ExternalCode)" do
      assert zod(ExternalCode) == ~s{z.string().startsWith("code-")}
      assert valibot(ExternalCode) == ~s{v.pipe(v.string(), v.startsWith("code-"))}
    end
  end

  describe "built-in scalars" do
    test "ULID maps as its base type" do
      assert zod(AshDoubleEntry.ULID) == "z.string()"
      assert valibot(AshDoubleEntry.ULID) == "v.string()"
    end

    test "Ltree maps through the built-in's MFAs, per escape?" do
      assert zod(AshPostgres.Ltree, escape?: true) == "z.array(z.string())"
      assert zod(AshPostgres.Ltree) == "z.union([z.string(), z.array(z.string())])"
      assert valibot(AshPostgres.Ltree, escape?: true) == "v.array(v.string())"
      assert valibot(AshPostgres.Ltree) == "v.union([v.string(), v.array(v.string())])"
    end

    test "a manifest entry replaces the built-in" do
      entry = %Scalar{
        module: AshDoubleEntry.ULID,
        type: Ash.Type.String,
        zod: "z.string().length(26)"
      }

      declare(entry, fn ->
        assert zod(AshDoubleEntry.ULID) == "z.string().length(26)"
        # The built-in is replaced whole: valibot maps the entry's base type.
        assert valibot(AshDoubleEntry.ULID) == "v.string()"
      end)
    end

    test "typescript_type_name/0 doesn't replace a built-in's schema (D41)" do
      entry = %Scalar{module: PriorityScore, type: Ash.Type.Integer, zod: "Builtin.score"}

      with_entries(:builtin, &Map.put(&1, PriorityScore, entry), fn ->
        assert zod(PriorityScore) == "Builtin.score"
      end)
    end
  end

  describe "map entries" do
    test "GeoPoint's zod and valibot replace the object of its fields" do
      assert ref_zod(GeoPoint) == "NestedZodSchemas.geoPoint"
      assert ref_valibot(GeoPoint) == "NestedValibotSchemas.geoPoint"
    end

    test "without zod or valibot, the schema is an object of the fields" do
      with_entries(
        :declared,
        &Map.update!(&1, GeoPoint, fn e -> %{e | zod: nil, valibot: nil} end),
        fn ->
          assert ref_zod(GeoPoint) == "z.object({ lat: z.number(), lng: z.number() })"
          assert ref_valibot(GeoPoint) == "v.object({ lat: v.number(), lng: v.number() })"
        end
      )
    end

    test "a built-in map entry's zod applies to a declared custom type" do
      entry = %MapType{module: Theme, fields: [], zod: {__MODULE__, :echo_schema, ["theme"]}}

      with_entries(:builtin, &Map.put(&1, Theme, entry), fn ->
        assert ref_zod(Theme) == "theme:[]"
        assert ref_valibot(Theme) =~ "v.object({ color: "
      end)
    end

    test "a NewType over a type with a map entry inherits its zod and valibot" do
      assert ref_zod(NewGeoPoint) == "NestedZodSchemas.geoPoint"
      assert ref_valibot(NewGeoPoint) == "NestedValibotSchemas.geoPoint"
    end

    test "a NewType's own map entry wins over its subtype's" do
      entry = %MapType{module: NewGeoPoint, fields: [], zod: "Own.geo", valibot: "Own.vgeo"}

      declare(entry, fn ->
        assert ref_zod(NewGeoPoint) == "Own.geo"
        assert ref_valibot(NewGeoPoint) == "Own.vgeo"
      end)
    end

    test "a NewType declaring its own fields doesn't inherit its subtype's schema" do
      # Its schema is the object of its own fields, read from its definition,
      # which this manifest doesn't have.
      assert_raise ArgumentError, ~r/NewGeoPointWithFields is not in the manifest/, fn ->
        ref_zod(NewGeoPointWithFields)
      end
    end

    test "a type without an entry is an object of its fields" do
      assert ref_zod(ThemeMap) =~ "z.object({ color: "
    end
  end

  describe "constraints of a scalar member's base mapping" do
    # ExternalCode re-declared over :string with a regex and no schemas. Theme
    # is a declared custom type: decoration merged the entry's constraints
    # into its members, which map with them. ThemeMap isn't one, so the
    # entry's constraints apply at the use.
    setup do
      manifest =
        AshTypescript.Test.InlineManifest.build!(
          body:
            quote do
              custom_types do
                scalar AshTypescript.Test.CustomIdentifier, :string do
                  zod "CustomZodSchemas.objectId"
                  valibot "CustomValibotSchemas.objectId"
                end

                scalar AshTypescript.Test.ExternalCode, :string,
                  constraints: [match: ~r/^code-/, max_length: 20]

                map AshTypescript.Test.GeoPoint do
                  field :lat, :float, allow_nil?: false
                  field :lng, :float, allow_nil?: false
                end
              end
            end
        )

      %{manifest: manifest}
    end

    test "a member of a declared custom type maps with its merged constraints", %{
      manifest: manifest
    } do
      AshTypescript.with_manifest(manifest, fn ->
        code = Enum.find(Introspection.named_type_definition(Theme).fields, &(&1.name == :code))
        assert Keyword.get(code.type.constraints, :max_length) == 20

        schema = ref_zod(Theme)
        assert schema =~ "code: z.string().max(20).regex(/^code-/)"
        assert schema =~ "codes: z.array(z.string().max(20).regex(/^code-/))"
      end)
    end

    test "a member of another typed map uses the entry's constraints", %{manifest: manifest} do
      AshTypescript.with_manifest(manifest, fn ->
        schema = ref_zod(ThemeMap)

        assert schema =~ "code: z.string().max(20).regex(/^code-/)"
        assert schema =~ "codes: z.array(z.string().max(20).regex(/^code-/))"
      end)
    end
  end

  describe "scalar members carry the regex (D35)" do
    test "in a declared custom type and a NewType over :map" do
      for module <- [Theme, ThemeMap] do
        assert ref_zod(module) =~ "color: z.string().min(1).regex(/^#[0-9a-fA-F]{6}$/)"
        assert ref_valibot(module) =~ "v.regex(/^#[0-9a-fA-F]{6}$/)"
      end
    end
  end

  describe "SchemaFormatter.library/0" do
    test "names each formatter's library" do
      assert ZodSchemaGenerator.library() == :zod
      assert ValibotSchemaGenerator.library() == :valibot
    end
  end

  describe "generated output" do
    setup do
      {:ok, content} = AshTypescript.Test.CodegenTestHelper.generate_all_content()
      %{content: content}
    end

    test "hand-rolled custom types no longer collapse to a flat string schema", %{
      content: content
    } do
      assert content =~ "priorityScore: z.number().int()"
      # ColorPalette declares its fields, so it is an object of them.
      assert content =~ "colorPalette: z.object("
      refute content =~ "priorityScore: z.string()"
      refute content =~ "colorPalette: z.string()"
    end

    test "a scalar entry's schemas reach both generators", %{content: content} do
      # AshTypescript.Test.CustomIdentifier has no `typescript_type_name`; its
      # `scalar` entry in the test manifest names schemas authored in TypeScript.
      assert content =~ "customId: CustomZodSchemas.objectId"
      assert content =~ "customId: v.optional(v.nullable(CustomValibotSchemas.objectId))"
      refute content =~ "customId: z.any()"
      refute content =~ "customId: v.any()"
    end

    test "a map entry's schemas replace the object of its fields", %{content: content} do
      # GeoPoint's fields would give a plain object of two numbers; its entry
      # names a stricter schema with ranges.
      assert content =~ "geoPoint: NestedZodSchemas.geoPoint"
      assert content =~ "geoPoint: v.optional(v.nullable(NestedValibotSchemas.geoPoint))"
      refute content =~ "geoPoint: z.record(z.string(), z.any())"
      refute content =~ "geoPoint: z.object("
    end

    test "a schema may come from a user-authored file", %{content: content} do
      # The schema is only usable if the schema file also imports it —
      # otherwise the generated TypeScript references an undefined name.
      assert content =~ ~s{import * as CustomZodSchemas from "./customZodSchemas";}
      assert content =~ ~s{import * as CustomValibotSchemas from "./customValibotSchemas";}
    end
  end

  describe "per-library schema imports" do
    setup do
      {:ok, files} = AshTypescript.Test.CodegenTestHelper.generate_files()

      zod =
        Enum.find_value(files, "", fn {path, c} -> String.ends_with?(path, "ash_zod.ts") && c end)

      valibot =
        Enum.find_value(files, "", fn {path, c} ->
          String.ends_with?(path, "ash_valibot.ts") && c
        end)

      %{zod: zod, valibot: valibot}
    end

    test "each schema file imports only its own configured module", %{zod: zod, valibot: valibot} do
      assert zod =~ ~s(import * as CustomZodSchemas from "./customZodSchemas";)
      refute zod =~ "CustomValibotSchemas"

      assert valibot =~ ~s(import * as CustomValibotSchemas from "./customValibotSchemas";)
      refute valibot =~ "CustomZodSchemas"
    end

    test "every configured entry is emitted, not just the first", %{zod: zod, valibot: valibot} do
      assert zod =~ ~s(import * as NestedZodSchemas from "./custom/nestedZodSchemas";)
      assert valibot =~ ~s(import * as NestedValibotSchemas from "./custom/nestedValibotSchemas";)
    end

    test "import paths resolve relative to the schema file, not the project root", %{zod: zod} do
      # The config entry is `./test/ts/custom/nestedZodSchemas.ts` and the
      # schema file lives in `test/ts/`, so the emitted path must descend into
      # the subdirectory rather than repeat the project-relative prefix.
      assert zod =~ ~s(from "./custom/nestedZodSchemas";)
      refute zod =~ "test/ts/custom"
    end

    test "the shared import_into_generated modules stay out of the schema files", %{
      zod: zod,
      valibot: valibot
    } do
      # `import_into_generated` targets the types and RPC files; pulling those
      # into the schema files risks import cycles.
      for module <- ["RpcHooks", "ChannelHooks"] do
        refute zod =~ module
        refute valibot =~ module
      end
    end
  end
end
