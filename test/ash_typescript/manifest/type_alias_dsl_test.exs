# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.TypeAliasDslTest do
  # The alias opt-ins of the `custom_types` section: `scalar` `ts_alias`
  # and field-less `map` entries for field-bearing NewTypes. Their validation and persistence only; nothing
  # here reads them for codegen. Manifests are compiled with `Module.create/3`
  # under fixed names.
  use ExUnit.Case, async: false

  alias AshTypescript.CustomTypes
  alias AshTypescript.CustomTypes.{Builtin, MapType, Scalar}
  alias AshTypescript.Manifest.Custom
  alias AshTypescript.Manifest.TypeAliasDslTest, as: T

  defmodule CodeTs do
    @moduledoc false
    def typescript(_constraints), do: "string"
    def ts_alias(_constraints), do: "Code"
  end

  defmodule Typed do
    @moduledoc false
    use Ash.TypedStruct

    typed_struct do
      field :a, :string
      field :b, :integer
    end
  end

  defmodule TypedNamed do
    @moduledoc false
    use Ash.TypedStruct

    def typescript_type, do: "TypedNamed"

    typed_struct do
      field :a, :string
    end
  end

  defmodule CallbackScalar do
    @moduledoc false
    use Ash.Type

    def typescript_type, do: "string"

    @impl true
    def storage_type(_), do: :string
    @impl true
    def cast_input(value, _), do: {:ok, value}
    @impl true
    def cast_stored(value, _), do: {:ok, value}
    @impl true
    def dump_to_native(value, _), do: {:ok, value}
  end

  defmodule Empty do
    @moduledoc false
    use Ash.TypedStruct

    typed_struct do
    end
  end

  defmodule MapNew do
    @moduledoc false
    use Ash.Type.NewType, subtype_of: :map, constraints: [fields: [a: [type: :string]]]
  end

  defmodule KeywordNew do
    @moduledoc false
    use Ash.Type.NewType, subtype_of: :keyword, constraints: [fields: [a: [type: :string]]]
  end

  defmodule TupleNew do
    @moduledoc false
    use Ash.Type.NewType, subtype_of: :tuple, constraints: [fields: [a: [type: :string]]]
  end

  defmodule StringNew do
    @moduledoc false
    use Ash.Type.NewType, subtype_of: :string, constraints: [max_length: 10]
  end

  defmodule UnionNew do
    @moduledoc false
    use Ash.Type.NewType,
      subtype_of: :union,
      constraints: [types: [text: [type: :string], number: [type: :integer]]]
  end

  # The scoped manifest prints the RPC resource warnings; they're captured.
  defp compile_manifest!(name, body) do
    module = Module.concat(T, name)

    ExUnit.CaptureIO.with_io(:stderr, fn -> create_manifest(module, body) end)
    module
  end

  defp create_manifest(module, body) do
    Module.create(
      module,
      quote do
        use AshTypescript.Manifest,
          otp_app: :ash_typescript,
          domains: [AshTypescript.Test.SecondDomain]

        unquote(body)
      end,
      Macro.Env.location(__ENV__)
    )
  end

  defp compile_error!(name, body) do
    error = assert_raise Spark.Error.DslError, fn -> compile_manifest!(name, body) end
    Exception.message(error)
  end

  defp persisted(module), do: Spark.Dsl.Extension.get_persisted(module, :custom_types)

  describe "custom_types section" do
    test "custom_types/1 of an undecorated manifest is the built-ins" do
      assert Custom.custom_types(%Ash.Info.Manifest{}) == %{
               declared: %{},
               builtin: AshTypescript.CustomTypes.Builtin.by_module()
             }
    end
  end

  describe "scalar ts_alias" do
    test "a string ts_alias is persisted" do
      module =
        compile_manifest!(
          ScalarTypeName,
          quote do
            custom_types do
              scalar SomeLib.Email, :string, ts_alias: "Email"
            end
          end
        )

      assert persisted(module).declared[SomeLib.Email].ts_alias == "Email"
    end

    test "an MFA ts_alias with an MFA ts_type is persisted" do
      module =
        compile_manifest!(
          ScalarMfaTypeName,
          quote do
            custom_types do
              scalar SomeLib.Code, :string do
                ts_type {T.CodeTs, :typescript, []}
                ts_alias {T.CodeTs, :ts_alias, []}
              end
            end
          end
        )

      scalar = persisted(module).declared[SomeLib.Code]
      assert scalar.ts_type == {T.CodeTs, :typescript, []}
      assert scalar.ts_alias == {T.CodeTs, :ts_alias, []}
    end

    test "an invalid identifier is a DslError" do
      message =
        compile_error!(
          ScalarBadTypeName,
          quote do
            custom_types do
              scalar SomeLib.Email, :string, ts_alias: "E-mail"
            end
          end
        )

      assert message =~
               ~s(The ts_alias "E-mail" of SomeLib.Email is not a TypeScript identifier.)

      assert message =~ "custom_types -> scalar -> Elixir.SomeLib.Email -> ts_alias"
    end

    test "a reserved word is a DslError" do
      message =
        compile_error!(
          ScalarReservedTypeName,
          quote do
            custom_types do
              scalar SomeLib.Email, :string, ts_alias: "string"
            end
          end
        )

      assert message =~ ~s(The ts_alias "string" of SomeLib.Email is a TypeScript reserved word.)
      assert message =~ "custom_types -> scalar -> Elixir.SomeLib.Email -> ts_alias"
    end

    test "an MFA ts_alias needs an MFA ts_type" do
      for {name, ts_type} <- [{ScalarMfaStringTs, "string"}, {ScalarMfaNoTs, nil}] do
        ts_type_opt = if ts_type, do: [ts_type: ts_type], else: []
        opts = Macro.escape([{:ts_alias, {T.CodeTs, :ts_alias, []}} | ts_type_opt])

        message =
          compile_error!(
            name,
            quote do
              custom_types do
                scalar SomeLib.Code, :string, unquote(opts)
              end
            end
          )

        assert message =~
                 "SomeLib.Code: an MFA `ts_alias` needs an MFA `ts_type`: both must be " <>
                   "computed from the use's constraints"

        assert message =~ "custom_types -> scalar -> Elixir.SomeLib.Code -> ts_alias"
      end
    end

    test "ts_alias defaults to nil" do
      module =
        compile_manifest!(
          ScalarNoTypeName,
          quote do
            custom_types do
              scalar SomeLib.Email, :string
            end
          end
        )

      assert persisted(module).declared[SomeLib.Email].ts_alias == nil

      # The built-ins keep their own names (ULID, Ltree; `builtin_test.exs`).
      assert persisted(module).builtin == Builtin.by_module()
    end
  end

  describe "map entries for field-bearing NewTypes" do
    test "a field-less entry for a TypedStruct, a NewType over :map, :keyword and :tuple is accepted" do
      module =
        compile_manifest!(
          FieldlessEntries,
          quote do
            custom_types do
              map T.Typed
              map T.MapNew, ts_alias: "MapNew"
              map T.KeywordNew
              map T.TupleNew
            end
          end
        )

      declared = persisted(module).declared

      assert %MapType{fields: [], ts_alias: nil} = declared[T.Typed]
      assert %MapType{fields: [], ts_alias: "MapNew"} = declared[T.MapNew]
      assert %MapType{fields: [], ts_alias: nil} = declared[T.KeywordNew]
      assert %MapType{fields: [], ts_alias: nil} = declared[T.TupleNew]
    end

    test "a field-less entry's ts_alias is checked" do
      message =
        compile_error!(
          FieldlessBadTypeName,
          quote do
            custom_types do
              map T.Typed, ts_alias: "not-a-name"
            end
          end
        )

      assert message =~
               ~s(The ts_alias "not-a-name" of #{inspect(T.Typed)} is not a TypeScript identifier.)

      assert message =~ "custom_types -> map -> #{T.Typed} -> ts_alias"
    end

    test "zod or valibot on a field-less entry is a DslError" do
      for {option, name} <- [zod: FieldlessZod, valibot: FieldlessValibot] do
        message =
          compile_error!(
            name,
            quote do
              custom_types do
                map T.Typed, [{unquote(option), "Own.schema"}]
              end
            end
          )

        assert message =~
                 "The `map` entry of #{inspect(T.Typed)} has no fields, so its `#{option}` " <>
                   "would never be used; remove it (its schemas are generated from the type)."

        assert message =~ "custom_types -> map -> #{T.Typed} -> #{option}"
      end
    end

    test "fields on a field-bearing NewType are a DslError" do
      message =
        compile_error!(
          NewTypeWithFields,
          quote do
            custom_types do
              map T.Typed do
                field :a, :string
              end
            end
          end
        )

      assert message =~
               "The fields of #{inspect(T.Typed)} come from the type; remove them from its `map` entry."

      assert message =~ "custom_types -> map -> #{T.Typed}"
    end

    test "a field-less entry for anything else needs fields" do
      for {name, module} <- [
            {FieldlessString, T.StringNew},
            {FieldlessEmpty, T.Empty},
            {FieldlessUnion, T.UnionNew},
            {FieldlessScalarType, AshTypescript.Test.CustomIdentifier},
            {FieldlessMissing, SomeLib.Missing}
          ] do
        message =
          compile_error!(
            name,
            quote do
              custom_types do
                map unquote(module)
              end
            end
          )

        assert message =~
                 "The map #{inspect(module)} needs at least one field (a field-less `map` entry " <>
                   "is only for an `Ash.Type.NewType` with fields, such as an `Ash.TypedStruct`)."

        assert message =~ "custom_types -> map -> #{module}"
      end
    end

    test "a field-less map opt-in on a typescript_type/0 type is a DslError" do
      for {name, opts} <- [{NamedTypeOptIn, []}, {NamedTypeOptInNamed, [ts_alias: "X"]}] do
        message =
          compile_error!(
            name,
            quote do
              custom_types do
                map T.TypedNamed, unquote(opts)
              end
            end
          )

        assert message =~
                 "#{inspect(T.TypedNamed)} exports `typescript_type/0`: remove it; " <>
                   "the alias is generated from the fields."

        assert message =~ "custom_types -> map -> #{T.TypedNamed}"
      end
    end

    # A scalar's alias body is its TypeScript, `typescript_type/0` included.
    test "a scalar ts_alias on a typescript_type/0 type is accepted" do
      module =
        compile_manifest!(
          NamedScalarTypeName,
          quote do
            custom_types do
              scalar AshTypescript.Test.HexColor, :string, ts_alias: "Hex"
              scalar T.CallbackScalar, :string, ts_alias: "Cb"
            end
          end
        )

      declared = persisted(module).declared

      assert declared[AshTypescript.Test.HexColor].ts_alias == "Hex"
      assert declared[T.CallbackScalar].ts_alias == "Cb"
    end

    test "a scalar entry without ts_alias on a typescript_type/0 type is accepted" do
      module =
        compile_manifest!(
          NamedScalarNoTypeName,
          quote do
            custom_types do
              scalar AshTypescript.Test.HexColor, :string
            end
          end
        )

      assert %Scalar{ts_alias: nil} = persisted(module).declared[AshTypescript.Test.HexColor]
    end

    test "an entry for a module the manifest never reaches is accepted and has no effect" do
      module =
        compile_manifest!(
          UnreachedEntry,
          quote do
            custom_types do
              map T.Typed, ts_alias: "Unreached"
            end
          end
        )

      assert %MapType{ts_alias: "Unreached"} = persisted(module).declared[T.Typed]
      refute Enum.any?(AshTypescript.manifest(module).types, &(&1.module == T.Typed))
    end

    test "a field-less entry doesn't declare the type" do
      declared = %{T.Typed => %MapType{module: T.Typed}}
      entry_of = &Map.get(declared, &1)

      assert CustomTypes.fields_for(T.Typed, declared, %{}) == nil
      assert CustomTypes.map_entry(T.Typed, entry_of) == nil
      assert CustomTypes.resolve_field_type(T.Typed, [], entry_of) == {:ok, T.Typed, []}
    end

    test "a field typed by a NewType with a field-less entry is still constraint-checked" do
      message =
        compile_error!(
          FieldlessFieldConstraints,
          quote do
            custom_types do
              map SomeLib.Holder do
                field :code, T.Typed, constraints: [not_a_constraint: 1]
              end

              map T.Typed
            end
          end
        )

      assert message =~ "Invalid constraints for field :code of #{inspect(SomeLib.Holder)}"
    end
  end

  describe "field_bearing_new_type_module?/1" do
    test "a NewType with fields is field-bearing" do
      for module <- [T.Typed, T.TypedNamed, T.MapNew, T.KeywordNew, T.TupleNew],
          do: assert(CustomTypes.field_bearing_new_type_module?(module), inspect(module))
    end

    test "anything else is not" do
      for module <- [
            T.Empty,
            T.StringNew,
            T.UnionNew,
            AshTypescript.Test.CustomIdentifier,
            Ash.Type.String,
            SomeLib.Missing
          ],
          do: refute(CustomTypes.field_bearing_new_type_module?(module), inspect(module))
    end

    test "the definition variant reads a manifest type" do
      types = AshTypescript.manifest().types
      task_stats = Enum.find(types, &(&1.module == AshTypescript.Test.TaskStats))
      geo_point = Enum.find(types, &(&1.module == AshTypescript.Test.GeoPoint))

      assert CustomTypes.field_bearing_new_type?(task_stats)
      refute CustomTypes.field_bearing_new_type?(geo_point)

      # A declared custom type's definition is aliased as one, never as a NewType.
      declared = put_in(task_stats.custom, %{ash_rpc: %{custom_type: true}})
      refute CustomTypes.field_bearing_new_type?(declared)
    end
  end
end
