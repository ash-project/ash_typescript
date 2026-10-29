# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.CustomTypesDslTest do
  # The `custom_types` section of a manifest module: its grammar, the
  # validation `NormalizeCustomTypes` adds, the persisted `:custom_types`
  # state and the copy under `manifest.custom.ash_typescript.custom_types`.
  # Manifests are compiled with `Module.create/3` under fixed names.
  use ExUnit.Case, async: false

  alias AshTypescript.CustomTypes.{Builtin, Field, MapType, Scalar}
  alias AshTypescript.Manifest.Custom
  alias AshTypescript.Manifest.CustomTypesDslTest, as: T

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

  # An option or entity used inside a `do` block it doesn't belong to is an
  # undefined function there, so the compiler (not Spark) rejects it. The
  # compiler logs the reason to stderr.
  defp undefined_function_error!(name, body) do
    {_, stderr} =
      ExUnit.CaptureIO.with_io(:stderr, fn ->
        assert_raise CompileError, fn -> create_manifest(Module.concat(T, name), body) end
      end)

    stderr
  end

  # Compiled once: the section from the spec's example.
  defp palette_manifest do
    module = Module.concat(T, Palette)

    if Code.ensure_loaded?(module) do
      module
    else
      compile_manifest!(
        Palette,
        quote do
          custom_types do
            scalar SomeLib.HexColor, :string do
              constraints match: ~r/^#[0-9a-f]{6}$/
              ts_type "`#${string}`"
            end

            scalar SomeLib.Percent, :integer, constraints: [min: 0, max: 100]

            map SomeLib.Palette do
              field :primary, SomeLib.HexColor, allow_nil?: false
              field :accent_color, :string, client_name: "accentColour"
              field :shade, SomeLib.HexColor, constraints: [max_length: 7]
              zod "MyZod.palette"
            end
          end
        end
      )
    end
  end

  defp persisted(module), do: Spark.Dsl.Extension.get_persisted(module, :custom_types)

  describe "grammar" do
    test "scalar and map entities compile" do
      assert Code.ensure_loaded?(palette_manifest())
    end

    test "ts_type on a map is rejected as an option" do
      message =
        compile_error!(
          MapWithTsTypeOption,
          quote do
            custom_types do
              map SomeLib.Bad, ts_type: "Bad"
            end
          end
        )

      assert message =~ "unknown options [:ts_type]"
    end

    test "ts_type inside a map's block is rejected" do
      stderr =
        undefined_function_error!(
          MapWithTsType,
          quote do
            custom_types do
              map SomeLib.Bad do
                field :a, :string
                ts_type "Bad"
              end
            end
          end
        )

      assert stderr =~ "undefined function ts_type/1"
    end

    test "a field inside a scalar is rejected" do
      stderr =
        undefined_function_error!(
          ScalarWithField,
          quote do
            custom_types do
              scalar SomeLib.Bad, :string do
                field :a, :string
              end
            end
          end
        )

      assert stderr =~ "undefined function field/2"
    end
  end

  describe "NormalizeCustomTypes" do
    test "a map with no fields is rejected" do
      message =
        compile_error!(
          EmptyMap,
          quote do
            custom_types do
              map SomeLib.Empty do
                zod "MyZod.empty"
              end
            end
          end
        )

      assert message =~
               "The map SomeLib.Empty needs at least one field (a field-less `map` entry is " <>
                 "only for an `Ash.Type.NewType` with fields, such as an `Ash.TypedStruct`)."
    end

    test "a module declared twice is rejected" do
      message =
        compile_error!(
          Duplicate,
          quote do
            custom_types do
              scalar SomeLib.Twice, :string

              map SomeLib.Twice do
                field :a, :string
              end
            end
          end
        )

      assert message =~ "SomeLib.Twice"
      assert message =~ "more than once"
    end

    test "a field declared twice in a map is rejected" do
      message =
        compile_error!(
          DuplicateField,
          quote do
            custom_types do
              map SomeLib.Twice do
                field :a, :string
                field :a, :integer
              end
            end
          end
        )

      assert message =~ "custom_types -> map -> Elixir.SomeLib.Twice -> field -> a"
      assert message =~ "The field :a of SomeLib.Twice is declared more than once."
    end

    test "scalar constraints the base type rejects" do
      message =
        compile_error!(
          BadScalarConstraints,
          quote do
            custom_types do
              scalar SomeLib.Bad, :string, constraints: [min: 1]
            end
          end
        )

      assert message =~ "SomeLib.Bad"
      assert message =~ "min"
    end

    test "field constraints the declared scalar's base type rejects" do
      message =
        compile_error!(
          BadFieldConstraints,
          quote do
            custom_types do
              scalar SomeLib.HexColor, :string

              map SomeLib.Palette do
                field :p, SomeLib.HexColor, constraints: [min: 1]
              end
            end
          end
        )

      assert message =~ "SomeLib.Palette"
      assert message =~ ":p"
      assert message =~ "min"
    end

    test "field constraints the field's own type rejects" do
      message =
        compile_error!(
          BadOwnFieldConstraints,
          quote do
            custom_types do
              map SomeLib.Palette do
                field :p, :integer, constraints: [max_length: 1]
              end
            end
          end
        )

      assert message =~ ":p"
      assert message =~ "max_length"
    end

    test "a scalar whose base is not an Ash type is rejected" do
      message =
        compile_error!(
          UnknownScalarBase,
          quote do
            custom_types do
              scalar SomeLib.Bad, SomeLib.NotAType
            end
          end
        )

      assert message =~ "SomeLib.NotAType"
      assert message =~ "not an Ash type"
    end

    test "a field whose type is neither an Ash type nor an entry is rejected" do
      message =
        compile_error!(
          UnknownFieldType,
          quote do
            custom_types do
              map SomeLib.Palette do
                field :p, SomeLib.NotAType
              end
            end
          end
        )

      assert message =~ "SomeLib.NotAType"
      assert message =~ "not an Ash type"
    end

    test "a field may be typed by another map entry or a built-in" do
      module =
        compile_manifest!(
          NestedEntries,
          quote do
            custom_types do
              map SomeLib.Inner do
                field :a, :string
              end

              map SomeLib.Outer do
                field :inner, SomeLib.Inner
                field :price, AshMoney.Types.Money
                field :id, AshDoubleEntry.ULID
              end
            end
          end
        )

      assert %MapType{fields: [%Field{type: SomeLib.Inner}, _, _]} =
               persisted(module).declared[SomeLib.Outer]
    end
  end

  describe "persisted :custom_types" do
    test "holds the declared entries, regexes as MFAs" do
      %{declared: declared} = persisted(palette_manifest())

      assert %Scalar{
               module: SomeLib.HexColor,
               type: Ash.Type.String,
               constraints: [match: {Spark.Regex, :cache, ["^#[0-9a-f]{6}$", regex_opts]}],
               ts_type: "`#${string}`"
             } = declared[SomeLib.HexColor]

      assert regex_opts in [[], ""]

      assert %Scalar{type: Ash.Type.Integer, constraints: [min: 0, max: 100]} =
               declared[SomeLib.Percent]

      assert %MapType{module: SomeLib.Palette, zod: "MyZod.palette", valibot: nil} =
               declared[SomeLib.Palette]

      assert Map.keys(declared) |> Enum.sort() ==
               Enum.sort([SomeLib.HexColor, SomeLib.Percent, SomeLib.Palette])
    end

    test "converts regexes nested in item constraints" do
      module =
        compile_manifest!(
          NestedRegex,
          quote do
            custom_types do
              scalar SomeLib.Path, {:array, :string}, constraints: [items: [match: ~r/^[a-z]+$/]]

              map SomeLib.Holder do
                field :codes, {:array, :string}, constraints: [items: [match: ~r/^[0-9]+$/]]
              end
            end
          end
        )

      %{declared: declared} = persisted(module)

      assert %Scalar{
               type: {:array, Ash.Type.String},
               constraints: [items: [match: {Spark.Regex, :cache, ["^[a-z]+$", _]}]]
             } = declared[SomeLib.Path]

      assert %MapType{
               fields: [
                 %Field{constraints: [items: [match: {Spark.Regex, :cache, ["^[0-9]+$", _]}]]}
               ]
             } = declared[SomeLib.Holder]
    end

    test "holds the built-ins keyed by module" do
      %{builtin: builtin} = persisted(palette_manifest())

      assert builtin == Map.new(Builtin.entries(), &{&1.module, &1})
      assert %MapType{} = builtin[AshMoney.Types.Money]
      assert %Scalar{} = builtin[AshDoubleEntry.ULID]
      assert %Scalar{} = builtin[AshPostgres.Ltree]
    end

    test "a field's allow_nil? defaults to true and client_name is kept" do
      %MapType{fields: fields} = persisted(palette_manifest()).declared[SomeLib.Palette]

      assert [
               %Field{name: :primary, type: SomeLib.HexColor, allow_nil?: false},
               %Field{
                 name: :accent_color,
                 type: Ash.Type.String,
                 allow_nil?: true,
                 client_name: "accentColour"
               },
               %Field{name: :shade, allow_nil?: true}
             ] = fields
    end

    test "a field typed by a declared scalar has its constraints merged over the scalar's" do
      %MapType{fields: fields} = persisted(palette_manifest()).declared[SomeLib.Palette]
      shade = Enum.find(fields, &(&1.name == :shade))
      primary = Enum.find(fields, &(&1.name == :primary))

      assert [{:match, {Spark.Regex, :cache, ["^#[0-9a-f]{6}$", _]}}, {:max_length, 7}] =
               shade.constraints

      assert [match: {Spark.Regex, :cache, ["^#[0-9a-f]{6}$", _]}] = primary.constraints
    end

    test "the field wins per key over the scalar's constraints" do
      module =
        compile_manifest!(
          FieldWins,
          quote do
            custom_types do
              scalar SomeLib.Short, :string, constraints: [max_length: 5, min_length: 1]

              map SomeLib.Holder do
                field :s, SomeLib.Short, constraints: [max_length: 9]
              end
            end
          end
        )

      %MapType{fields: [field]} = persisted(module).declared[SomeLib.Holder]
      assert Enum.sort(field.constraints) == [max_length: 9, min_length: 1]
    end

    test "an array of a declared scalar merges the item constraints" do
      module =
        compile_manifest!(
          ArrayOfScalar,
          quote do
            custom_types do
              scalar SomeLib.Short, :string, constraints: [max_length: 5]

              map SomeLib.Holder do
                field :plain, {:array, SomeLib.Short}
                field :tight, {:array, SomeLib.Short}, constraints: [items: [min_length: 2]]
              end
            end
          end
        )

      %MapType{fields: [plain, tight]} = persisted(module).declared[SomeLib.Holder]
      assert plain.type == {:array, SomeLib.Short}
      assert plain.constraints == [items: [max_length: 5]]
      assert tight.constraints == [items: [max_length: 5, min_length: 2]]
    end

    test "an array of a declared scalar checks the items against the base type" do
      message =
        compile_error!(
          BadArrayItems,
          quote do
            custom_types do
              scalar SomeLib.Short, :string

              map SomeLib.Holder do
                field :s, {:array, SomeLib.Short}, constraints: [items: [min: 1]]
              end
            end
          end
        )

      assert message =~ ":s"
      assert message =~ "min"
    end

    test "a manifest without the section persists no declarations and the built-ins" do
      module = compile_manifest!(NoSection, nil)
      assert %{declared: declared, builtin: builtin} = persisted(module)
      assert declared == %{}
      assert Map.has_key?(builtin, AshMoney.Types.Money)
    end

    test "the test manifest persists its entries" do
      assert %{declared: declared} = persisted(AshTypescript.Test.Manifest)

      assert Map.keys(declared) |> Enum.sort() ==
               [
                 AshTypescript.Test.CustomIdentifier,
                 AshTypescript.Test.ExternalCode,
                 AshTypescript.Test.GeoPoint,
                 AshTypescript.Test.LineItem,
                 AshTypescript.Test.TodoRef,
                 AshTypescript.Test.TodoTimestamp
               ]
    end
  end

  describe "manifest.custom.ash_typescript.custom_types" do
    test "the readers return the declared and the built-in entries" do
      manifest = AshTypescript.manifest(palette_manifest())

      assert %Scalar{module: SomeLib.HexColor} =
               Custom.declared_custom_type(manifest, SomeLib.HexColor)

      assert %MapType{module: AshMoney.Types.Money} =
               Custom.builtin_custom_type(manifest, AshMoney.Types.Money)

      assert Custom.declared_custom_type(manifest, AshMoney.Types.Money) == nil
      assert Custom.builtin_custom_type(manifest, SomeLib.HexColor) == nil

      assert manifest.custom.ash_typescript.custom_types == persisted(palette_manifest())
    end

    test "the readers accept a manifest module" do
      assert %Scalar{} = Custom.declared_custom_type(palette_manifest(), SomeLib.Percent)
    end

    test "the routes and publications are kept beside the entries" do
      data = AshTypescript.manifest(AshTypescript.Test.Manifest).custom.ash_typescript
      assert Map.has_key?(data, :custom_types)
      assert map_size(data.routes) > 0
      assert map_size(data.publications) > 0
    end

    test "with_manifest/2 serves an override struct's entries" do
      entry = %Scalar{module: SomeLib.Override, type: Ash.Type.String}

      base = AshTypescript.manifest(AshTypescript.Test.Manifest)
      manifest = put_in(base.custom.ash_typescript.custom_types.declared[SomeLib.Override], entry)

      assert Custom.declared_custom_type(AshTypescript.manifest(), SomeLib.Override) == nil

      AshTypescript.with_manifest(manifest, fn ->
        assert Custom.declared_custom_type(AshTypescript.manifest(), SomeLib.Override) == entry
        assert Custom.declared_custom_type(nil, SomeLib.Override) == entry
      end)
    end

    test "a manifest without decoration has no entries" do
      manifest = %Ash.Info.Manifest{}
      assert Custom.declared_custom_type(manifest, SomeLib.HexColor) == nil
      assert Custom.builtin_custom_type(manifest, AshMoney.Types.Money) == nil
    end

    test "AshTypescript.Manifest.redecorate/2 keeps the entries" do
      manifest = AshTypescript.manifest(palette_manifest())
      redecorated = AshTypescript.Manifest.redecorate(manifest, output_formatter: :pascal_case)

      assert redecorated.custom.ash_typescript.custom_types ==
               manifest.custom.ash_typescript.custom_types
    end
  end
end
