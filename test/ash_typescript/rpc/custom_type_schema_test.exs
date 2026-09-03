# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.CustomTypeSchemaTest do
  @moduledoc """
  Tests validation-schema generation for hand-rolled custom Ash types
  (`kind: :unknown`).

  An `Ash.Type.NewType` never reaches this path — it resolves to its subtype's
  kind and carries its declared constraints through the normal dispatch. What
  lands here is a hand-rolled `use Ash.Type` module, resolved in this order:

  1. `zod_mapping_overrides` / `valibot_mapping_overrides` config
  2. the in-tree accept-lists (`simple_primitives`, `third_party_types`)
  3. a schema derived from the type's `storage_type/1`
  """
  use ExUnit.Case, async: false

  # Snapshot the global config this module mutates so it cannot leak into
  # later test modules.
  setup_all do
    AshTypescript.Test.TestHelpers.restore_application_env_on_exit([
      :valibot_mapping_overrides,
      :zod_mapping_overrides
    ])
  end

  alias Ash.Info.Manifest.Generator.TypeResolver
  alias AshTypescript.Codegen.SchemaCore
  alias AshTypescript.Codegen.ValibotSchemaGenerator
  alias AshTypescript.Codegen.ZodSchemaGenerator
  alias AshTypescript.Test.GeoPoint
  alias AshTypescript.Test.Todo.ColorPalette
  alias AshTypescript.Test.Todo.PriorityScore

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

  defp zod(type), do: SchemaCore.get_type(ZodSchemaGenerator, TypeResolver.resolve(type, []))

  defp valibot(type),
    do: SchemaCore.get_type(ValibotSchemaGenerator, TypeResolver.resolve(type, []))

  describe "storage-derived fallback" do
    test "an integer-storage custom type validates as a number, not a string" do
      assert zod(PriorityScore) == "z.number().int()"
      assert valibot(PriorityScore) == "v.pipe(v.number(), v.integer())"
    end

    test "a map-storage custom type validates as a record, not a string" do
      assert zod(ColorPalette) == "z.record(z.string(), z.any())"
      assert valibot(ColorPalette) == "v.record(v.string(), v.any())"
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

  describe "config overrides" do
    setup do
      # Restore rather than delete — config/config.exs sets these for the test
      # env, and `delete_env` would wipe them for every later test.
      zod_config = Application.get_env(:ash_typescript, :zod_mapping_overrides)
      valibot_config = Application.get_env(:ash_typescript, :valibot_mapping_overrides)

      on_exit(fn ->
        Application.put_env(:ash_typescript, :zod_mapping_overrides, zod_config)
        Application.put_env(:ash_typescript, :valibot_mapping_overrides, valibot_config)
      end)
    end

    test "an override replaces the storage-derived schema" do
      Application.put_env(:ash_typescript, :zod_mapping_overrides, [
        {IntegerStorageType, ~s{z.string().brand<"Id">()}}
      ])

      Application.put_env(:ash_typescript, :valibot_mapping_overrides, [
        {IntegerStorageType, "v.string()"}
      ])

      assert zod(IntegerStorageType) == ~s{z.string().brand<"Id">()}
      assert valibot(IntegerStorageType) == "v.string()"
    end

    test "overrides are independent per library" do
      Application.put_env(:ash_typescript, :zod_mapping_overrides, [
        {IntegerStorageType, "z.string()"}
      ])

      assert zod(IntegerStorageType) == "z.string()"
      # Valibot has no override configured, so it keeps the storage-derived schema.
      assert valibot(IntegerStorageType) == "v.pipe(v.number(), v.integer())"
    end

    test "an unrelated override does not leak onto other types" do
      Application.put_env(:ash_typescript, :zod_mapping_overrides, [
        {IntegerStorageType, "z.string()"}
      ])

      assert zod(PriorityScore) == "z.number().int()"
    end

    test "GeoPoint's override replaces a record schema it would otherwise get" do
      # The contrast the generated-output tests rely on: clear the configured
      # overrides and the map-storage fallback is all that's left.
      Application.put_env(:ash_typescript, :zod_mapping_overrides, [])
      Application.put_env(:ash_typescript, :valibot_mapping_overrides, [])

      assert zod(GeoPoint) == "z.record(z.string(), z.any())"
      assert valibot(GeoPoint) == "v.record(v.string(), v.any())"
    end

    test "an override wins over an in-tree third-party mapping" do
      Application.put_env(:ash_typescript, :zod_mapping_overrides, [
        {AshDoubleEntry.ULID, "z.string().length(26)"}
      ])

      assert zod(AshDoubleEntry.ULID) == "z.string().length(26)"
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
      assert content =~ "colorPalette: z.record(z.string(), z.any())"
      refute content =~ "priorityScore: z.string()"
      refute content =~ "colorPalette: z.string()"
    end

    test "configured overrides reach both generators", %{content: content} do
      # AshTypescript.Test.CustomIdentifier has no `typescript_type_name`, so
      # without the config overrides in config/config.exs it would fall through
      # to `z.any()` / `v.any()` here.
      assert content =~ "customId: CustomZodSchemas.objectId"
      assert content =~ "customId: v.optional(v.nullable(CustomValibotSchemas.objectId))"
      refute content =~ "customId: z.any()"
      refute content =~ "customId: v.any()"
    end

    test "an override replaces a too-permissive storage-derived schema", %{content: content} do
      # GeoPoint stores `:map`, so without its override it would generate the
      # record schema below and accept a half-built point.
      assert content =~ "geoPoint: NestedZodSchemas.geoPoint"
      assert content =~ "geoPoint: v.optional(v.nullable(NestedValibotSchemas.geoPoint))"
      refute content =~ "geoPoint: z.record(z.string(), z.any())"
      refute content =~ "geoPoint: v.record(v.string(), v.any())"
    end

    test "an override may name a schema from a user-authored file", %{content: content} do
      # The override is only usable if the schema file also imports it —
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
