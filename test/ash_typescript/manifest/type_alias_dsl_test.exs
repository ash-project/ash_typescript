# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.TypeAliasDslTest do
  # The alias opt-ins of the `custom_types` section: the `alias_all_types?`
  # option, `scalar` `type_name`, and field-less `map` entries for
  # field-bearing NewTypes. Their validation and persistence only; nothing
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
    def type_name(_constraints), do: "Code"
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

    def typescript_type_name, do: "TypedNamed"

    typed_struct do
      field :a, :string
    end
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

  describe "alias_all_types?" do
    test "defaults to false" do
      module = compile_manifest!(AliasAllDefault, nil)

      assert persisted(module).alias_all_types? == false
      assert Custom.alias_all_types?(AshTypescript.manifest(module)) == false

      # A section without the option takes the schema default.
      module =
        compile_manifest!(
          AliasAllSectionDefault,
          quote do
            custom_types do
              scalar SomeLib.Email, :string
            end
          end
        )

      assert persisted(module).alias_all_types? == false
    end

    test "is persisted with the entries and reaches the manifest" do
      module =
        compile_manifest!(
          AliasAllOn,
          quote do
            custom_types do
              alias_all_types? true
            end
          end
        )

      assert %{declared: declared, builtin: _, alias_all_types?: true} = persisted(module)
      assert declared == %{}

      manifest = AshTypescript.manifest(module)
      assert Custom.alias_all_types?(manifest) == true
      assert Custom.custom_types(manifest).alias_all_types? == true
    end

    test "a non-boolean is rejected by Spark" do
      message =
        compile_error!(
          AliasAllString,
          quote do
            custom_types do
              alias_all_types? "yes"
            end
          end
        )

      assert message =~ "alias_all_types?"
      assert message =~ "expected boolean"
    end

    test "the app manifest has it off" do
      assert Custom.alias_all_types?(nil) == false
      assert Custom.custom_types(nil).alias_all_types? == false
    end

    test "custom_types/1 of an undecorated manifest is the built-ins, off" do
      assert Custom.custom_types(%Ash.Info.Manifest{}) == %{
               declared: %{},
               builtin: AshTypescript.CustomTypes.Builtin.by_module(),
               alias_all_types?: false
             }

      assert Custom.alias_all_types?(%Ash.Info.Manifest{}) == false
    end
  end

  describe "scalar type_name" do
    test "a string type_name is persisted" do
      module =
        compile_manifest!(
          ScalarTypeName,
          quote do
            custom_types do
              scalar SomeLib.Email, :string, type_name: "Email"
            end
          end
        )

      assert persisted(module).declared[SomeLib.Email].type_name == "Email"
    end

    test "an MFA type_name with an MFA typescript is persisted" do
      module =
        compile_manifest!(
          ScalarMfaTypeName,
          quote do
            custom_types do
              scalar SomeLib.Code, :string do
                typescript {T.CodeTs, :typescript, []}
                type_name {T.CodeTs, :type_name, []}
              end
            end
          end
        )

      scalar = persisted(module).declared[SomeLib.Code]
      assert scalar.typescript == {T.CodeTs, :typescript, []}
      assert scalar.type_name == {T.CodeTs, :type_name, []}
    end

    test "an invalid identifier is a DslError" do
      message =
        compile_error!(
          ScalarBadTypeName,
          quote do
            custom_types do
              scalar SomeLib.Email, :string, type_name: "E-mail"
            end
          end
        )

      assert message =~
               ~s(The type_name "E-mail" of SomeLib.Email is not a TypeScript identifier.)

      assert message =~ "custom_types -> scalar -> Elixir.SomeLib.Email -> type_name"
    end

    test "a reserved word is a DslError" do
      message =
        compile_error!(
          ScalarReservedTypeName,
          quote do
            custom_types do
              scalar SomeLib.Email, :string, type_name: "string"
            end
          end
        )

      assert message =~ ~s(The type_name "string" of SomeLib.Email is a TypeScript reserved word.)
      assert message =~ "custom_types -> scalar -> Elixir.SomeLib.Email -> type_name"
    end

    test "an MFA type_name needs an MFA typescript" do
      for {name, typescript} <- [{ScalarMfaStringTs, "string"}, {ScalarMfaNoTs, nil}] do
        typescript_opt = if typescript, do: [typescript: typescript], else: []
        opts = Macro.escape([{:type_name, {T.CodeTs, :type_name, []}} | typescript_opt])

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
                 "SomeLib.Code: an MFA `type_name` needs an MFA `typescript`: both must be " <>
                   "computed from the use's constraints"

        assert message =~ "custom_types -> scalar -> Elixir.SomeLib.Code -> type_name"
      end
    end

    test "type_name defaults to nil" do
      module =
        compile_manifest!(
          ScalarNoTypeName,
          quote do
            custom_types do
              scalar SomeLib.Email, :string
            end
          end
        )

      assert persisted(module).declared[SomeLib.Email].type_name == nil

      for %Scalar{} = scalar <- Builtin.entries(), do: assert(scalar.type_name == nil)
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
              map T.MapNew, type_name: "MapNew"
              map T.KeywordNew
              map T.TupleNew
            end
          end
        )

      declared = persisted(module).declared

      assert %MapType{fields: [], type_name: nil} = declared[T.Typed]
      assert %MapType{fields: [], type_name: "MapNew"} = declared[T.MapNew]
      assert %MapType{fields: [], type_name: nil} = declared[T.KeywordNew]
      assert %MapType{fields: [], type_name: nil} = declared[T.TupleNew]
    end

    test "a field-less entry's type_name is checked" do
      message =
        compile_error!(
          FieldlessBadTypeName,
          quote do
            custom_types do
              map T.Typed, type_name: "not-a-name"
            end
          end
        )

      assert message =~
               ~s(The type_name "not-a-name" of #{inspect(T.Typed)} is not a TypeScript identifier.)

      assert message =~ "custom_types -> map -> #{T.Typed} -> type_name"
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

    test "an opt-in on a typescript_type_name/0 type is a DslError" do
      for {name, opts} <- [{NamedTypeOptIn, []}, {NamedTypeOptInNamed, [type_name: "X"]}] do
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
                 "#{inspect(T.TypedNamed)} exports `typescript_type_name/0`: remove it; " <>
                   "the alias is generated from the fields."

        assert message =~ "custom_types -> map -> #{T.TypedNamed}"
      end

      message =
        compile_error!(
          NamedScalarTypeName,
          quote do
            custom_types do
              scalar AshTypescript.Test.HexColor, :string, type_name: "Hex"
            end
          end
        )

      assert message =~
               "AshTypescript.Test.HexColor exports `typescript_type_name/0`: remove it; " <>
                 "the alias is generated from its TypeScript."

      assert message =~
               "custom_types -> scalar -> Elixir.AshTypescript.Test.HexColor -> type_name"
    end

    test "a scalar entry without type_name on a typescript_type_name/0 type is accepted" do
      module =
        compile_manifest!(
          NamedScalarNoTypeName,
          quote do
            custom_types do
              scalar AshTypescript.Test.HexColor, :string
            end
          end
        )

      assert %Scalar{type_name: nil} = persisted(module).declared[AshTypescript.Test.HexColor]
    end

    test "an entry for a module the manifest never reaches is accepted and has no effect" do
      module =
        compile_manifest!(
          UnreachedEntry,
          quote do
            custom_types do
              map T.Typed, type_name: "Unreached"
            end
          end
        )

      assert %MapType{type_name: "Unreached"} = persisted(module).declared[T.Typed]
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
