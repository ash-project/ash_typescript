# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.CustomTypeNamesTest do
  # The names of declared custom types: the `map` entry's `ts_alias`, the
  # type's `typescript_type_alias/0`, the joined module name default, their
  # validation, `AshTypescript.CustomTypes.names/2`, and the decorated
  # `custom.ash_typescript.type_alias_names` read through
  # `AshTypescript.Manifest.Custom.type_alias_names/1`.
  # Manifests are compiled with `Module.create/3` under fixed names.
  use ExUnit.Case, async: false

  alias AshTypescript.CustomTypes
  alias AshTypescript.CustomTypes.{Builtin, Field, MapType}
  alias AshTypescript.Manifest.Custom
  alias AshTypescript.Manifest.CustomTypeNamesTest, as: T

  defmodule NewGeoPoint do
    @moduledoc false
    use Ash.Type.NewType, subtype_of: AshTypescript.Test.GeoPoint
  end

  # A NewType without an entry of its own, naming itself.
  defmodule NamedNewGeoPoint do
    @moduledoc false
    use Ash.Type.NewType, subtype_of: AshTypescript.Test.GeoPoint

    def typescript_type_alias, do: "OwnGeoPoint"
  end

  defmodule NewMoney do
    @moduledoc false
    use Ash.Type.NewType, subtype_of: AshMoney.Types.Money
  end

  defmodule Coordinates do
    @moduledoc false
    use AshTypescript.Test.PassThroughType
  end

  defmodule NewCoordinates do
    @moduledoc false
    use Ash.Type.NewType, subtype_of: AshTypescript.Manifest.CustomTypeNamesTest.Coordinates
  end

  # Fields and alias from its own callbacks.
  defmodule Aliased do
    @moduledoc false
    use AshTypescript.Test.PassThroughType

    def typescript_fields, do: [lat: [type: :float, allow_nil?: false]]
    def typescript_type_alias, do: "GeoAliased"
  end

  # Inherits Aliased's fields, not its alias.
  defmodule NewAliased do
    @moduledoc false
    use Ash.Type.NewType, subtype_of: AshTypescript.Manifest.CustomTypeNamesTest.Aliased
  end

  # Its alias is whatever the test puts under `{Configurable, :alias}`
  # (default: a valid name), read when a manifest compiles.
  defmodule Configurable do
    @moduledoc false
    use AshTypescript.Test.PassThroughType

    def typescript_fields, do: [lat: [type: :float, allow_nil?: false]]

    def typescript_type_alias,
      do: :persistent_term.get({__MODULE__, :alias}, "ConfigurableAlias")
  end

  # A generic RPC action returning both types, so both reach the manifest.
  defmodule Holder do
    @moduledoc false
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "CustomTypeNamesHolder"
    end

    attributes do
      uuid_primary_key :id
    end

    actions do
      action :locate, :map do
        constraints fields: [
                      coords: [type: T.Coordinates],
                      new_coords: [type: T.NewCoordinates]
                    ]

        run fn _input, _context -> {:ok, %{}} end
      end
    end
  end

  defmodule HolderDomain do
    @moduledoc false
    use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

    typescript_rpc do
      resource T.Holder do
        rpc_action :locate, :locate
      end
    end

    resources do
      resource T.Holder
    end
  end

  # The types that name themselves with `typescript_type_alias/0`.
  defmodule CallbackHolder do
    @moduledoc false
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "CustomTypeNamesCallbackHolder"
    end

    attributes do
      uuid_primary_key :id
    end

    actions do
      action :describe, :map do
        constraints fields: [
                      aliased: [type: T.Aliased],
                      new_aliased: [type: T.NewAliased],
                      configurable: [type: T.Configurable]
                    ]

        run fn _input, _context -> {:ok, %{}} end
      end
    end
  end

  defmodule CallbackHolderDomain do
    @moduledoc false
    use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

    typescript_rpc do
      resource T.CallbackHolder do
        rpc_action :describe, :describe
      end
    end

    resources do
      resource T.CallbackHolder
    end
  end

  # The scoped manifest prints the RPC resource warnings; they're captured.
  defp compile_manifest!(name, body, domains \\ [AshTypescript.Test.SecondDomain]) do
    module = Module.concat(T, name)

    ExUnit.CaptureIO.with_io(:stderr, fn -> create_manifest(module, body, domains) end)
    module
  end

  defp create_manifest(module, body, domains) do
    Module.create(
      module,
      quote do
        use AshTypescript.Manifest,
          otp_app: :ash_typescript,
          domains: unquote(domains)

        unquote(body)
      end,
      Macro.Env.location(__ENV__)
    )
  end

  defp compile_error!(name, body, domains \\ [AshTypescript.Test.SecondDomain]) do
    error = assert_raise Spark.Error.DslError, fn -> compile_manifest!(name, body, domains) end
    Exception.message(error)
  end

  defp persisted(module), do: Spark.Dsl.Extension.get_persisted(module, :custom_types)

  defp definition(manifest, module), do: Enum.find(manifest.types, &(&1.module == module))

  defp names_in(manifest, module),
    do: Custom.type_alias_names(definition(manifest, module))

  describe "map entry options" do
    test "ts_alias is persisted" do
      module =
        compile_manifest!(
          AllNames,
          quote do
            custom_types do
              map SomeLib.Coordinates do
                ts_alias "GeoCoordinates"
                field :lat, :float, allow_nil?: false
              end
            end
          end
        )

      assert persisted(module).declared[SomeLib.Coordinates].ts_alias == "GeoCoordinates"
    end

    test "ts_alias defaults to nil" do
      module =
        compile_manifest!(
          NoNames,
          quote do
            custom_types do
              map SomeLib.Coordinates do
                field :lat, :float, allow_nil?: false
              end
            end
          end
        )

      assert persisted(module).declared[SomeLib.Coordinates].ts_alias == nil
    end

    test "the built-in Money entry is named Money" do
      assert Builtin.by_module()[AshMoney.Types.Money].ts_alias == "Money"
    end

    test "a name that isn't a TypeScript identifier is a DslError" do
      message =
        compile_error!(
          DashedName,
          quote do
            custom_types do
              map SomeLib.Coordinates do
                ts_alias "Geo-Coordinates"
                field :lat, :float, allow_nil?: false
              end
            end
          end
        )

      assert message =~
               ~s(The ts_alias "Geo-Coordinates" of SomeLib.Coordinates is not a TypeScript identifier)

      assert message =~ "custom_types -> map -> Elixir.SomeLib.Coordinates -> ts_alias"

      message =
        compile_error!(
          DigitName,
          quote do
            custom_types do
              map SomeLib.Coordinates do
                ts_alias "1abc"
                field :lat, :float, allow_nil?: false
              end
            end
          end
        )

      assert message =~
               ~s(The ts_alias "1abc" of SomeLib.Coordinates is not a TypeScript identifier)
    end

    test "a name with a trailing newline is not an identifier" do
      message =
        compile_error!(
          NewlineName,
          quote do
            custom_types do
              map SomeLib.Coordinates do
                ts_alias "Shade\n"
                field :lat, :float, allow_nil?: false
              end
            end
          end
        )

      assert message =~
               ~s(The ts_alias "Shade\\n" of SomeLib.Coordinates is not a TypeScript identifier)
    end

    test "await, eval and arguments are rejected" do
      for name <- ["await", "eval", "arguments"] do
        message =
          compile_error!(
            Module.concat(StrictName, Macro.camelize(name)),
            quote do
              custom_types do
                map SomeLib.Coordinates do
                  ts_alias unquote(name)
                  field :lat, :float, allow_nil?: false
                end
              end
            end
          )

        assert message =~
                 ~s(The ts_alias "#{name}" of SomeLib.Coordinates is a TypeScript reserved word)
      end
    end

    test "a TypeScript type keyword is rejected" do
      message =
        compile_error!(
          KeywordName,
          quote do
            custom_types do
              map SomeLib.Coordinates do
                ts_alias "string"
                field :lat, :float, allow_nil?: false
              end
            end
          end
        )

      assert message =~
               ~s(The ts_alias "string" of SomeLib.Coordinates is a TypeScript reserved word)
    end

    test "a global TypeScript name the generated code uses is rejected" do
      for name <- ~w(Array Record Promise Partial Date URLSearchParams) do
        message =
          compile_error!(
            Module.concat(GlobalName, name),
            quote do
              custom_types do
                map SomeLib.Coordinates do
                  ts_alias unquote(name)
                  field :lat, :float, allow_nil?: false
                end
              end
            end
          )

        assert message =~
                 ~s(The ts_alias "#{name}" of SomeLib.Coordinates is a global TypeScript ) <>
                   "name the generated code uses."
      end
    end

    test "a JavaScript reserved word is rejected" do
      message =
        compile_error!(
          ReservedName,
          quote do
            custom_types do
              map SomeLib.Coordinates do
                ts_alias "default"
                field :lat, :float, allow_nil?: false
              end
            end
          end
        )

      assert message =~
               ~s(The ts_alias "default" of SomeLib.Coordinates is a TypeScript reserved word)
    end

    test "ts_alias false is rejected by Spark" do
      message =
        compile_error!(
          FalseName,
          quote do
            custom_types do
              map SomeLib.Coordinates do
                ts_alias false
                field :lat, :float, allow_nil?: false
              end
            end
          end
        )

      assert message =~ "invalid value for :ts_alias option: expected string, got: false"
    end

    test "a non-string value is rejected by Spark" do
      message =
        compile_error!(
          TrueName,
          quote do
            custom_types do
              map SomeLib.Coordinates do
                ts_alias true
                field :lat, :float, allow_nil?: false
              end
            end
          end
        )

      assert message =~ "invalid value for :ts_alias option: expected string, got: true"
    end

    test "zod_schema_name and valibot_schema_name are no options" do
      for option <- [:zod_schema_name, :valibot_schema_name] do
        module = Module.concat([T, SchemaName, Macro.camelize(to_string(option))])

        body =
          quote do
            custom_types do
              map SomeLib.Coordinates do
                unquote({option, [], ["coordsSchema"]})
                field :lat, :float, allow_nil?: false
              end
            end
          end

        # The compiler logs the undefined function and raises a CompileError.
        stderr =
          ExUnit.CaptureIO.capture_io(:stderr, fn ->
            assert_raise CompileError, fn ->
              create_manifest(module, body, [AshTypescript.Test.SecondDomain])
            end
          end)

        assert stderr =~ "undefined function #{option}/1"
      end
    end
  end

  describe "typescript_type_alias/0 validation" do
    setup do
      on_exit(fn -> :persistent_term.erase({T.Configurable, :alias}) end)
    end

    defp callback_error!(name, value) do
      :persistent_term.put({T.Configurable, :alias}, value)
      compile_error!(name, quote(do: nil), [T.CallbackHolderDomain])
    end

    test "a result that isn't a TypeScript identifier is a DslError" do
      message = callback_error!(DashedCallback, "Geo-Aliased")

      assert message =~
               ~s[The typescript_type_alias/0 result "Geo-Aliased" of #{inspect(T.Configurable)} ] <>
                 "is not a TypeScript identifier."

      assert message =~ "custom_types"
    end

    test "a reserved word is a DslError" do
      message = callback_error!(ReservedCallback, "class")

      assert message =~
               ~s[The typescript_type_alias/0 result "class" of #{inspect(T.Configurable)} ] <>
                 "is a TypeScript reserved word."
    end

    test "a global TypeScript name the generated code uses is a DslError" do
      message = callback_error!(GlobalCallback, "Promise")

      assert message =~
               ~s[The typescript_type_alias/0 result "Promise" of #{inspect(T.Configurable)} ] <>
                 "is a global TypeScript name the generated code uses."
    end

    test "a result that isn't a string is a DslError" do
      message = callback_error!(AtomCallback, :geo)

      assert message =~
               "The typescript_type_alias/0 of #{inspect(T.Configurable)} must return a " <>
                 "string, got: :geo."
    end

    test "names/2 raises on an invalid result" do
      :persistent_term.put({T.Configurable, :alias}, "class")

      assert_raise ArgumentError,
                   ~s[The typescript_type_alias/0 result "class" of #{inspect(T.Configurable)} ] <>
                     "is a TypeScript reserved word.",
                   fn ->
                     CustomTypes.names(T.Configurable, %{
                       declared: %{},
                       builtin: Builtin.by_module()
                     })
                   end
    end

    test "an invalid result is ignored when the map entry has a ts_alias" do
      :persistent_term.put({T.Configurable, :alias}, "Geo-Aliased")

      module =
        compile_manifest!(
          EntryOverBadCallback,
          quote do
            custom_types do
              map AshTypescript.Manifest.CustomTypeNamesTest.Configurable do
                ts_alias "EntryConfigurable"
                field :lat, :float, allow_nil?: false
              end
            end
          end,
          [T.CallbackHolderDomain]
        )

      assert module |> AshTypescript.manifest() |> names_in(T.Configurable) ==
               %{typescript: "EntryConfigurable", zod: :derive, valibot: :derive}
    end

    test "an invalid result is a DslError when the map entry has no ts_alias" do
      :persistent_term.put({T.Configurable, :alias}, "Geo-Aliased")

      message =
        compile_error!(
          EntryWithoutNameBadCallback,
          quote do
            custom_types do
              map AshTypescript.Manifest.CustomTypeNamesTest.Configurable do
                field :lat, :float, allow_nil?: false
              end
            end
          end,
          [T.CallbackHolderDomain]
        )

      assert message =~
               ~s[The typescript_type_alias/0 result "Geo-Aliased" of #{inspect(T.Configurable)} ] <>
                 "is not a TypeScript identifier."
    end
  end

  describe "AshTypescript.CustomTypes.names/2" do
    @derived %{zod: :derive, valibot: :derive}

    defp geo_point_entry(opts) do
      struct!(
        %MapType{
          module: AshTypescript.Test.GeoPoint,
          fields: [%Field{name: :lat, type: :float, allow_nil?: false}],
          zod: "NestedZodSchemas.geoPoint",
          valibot: "NestedValibotSchemas.geoPoint"
        },
        opts
      )
    end

    defp names(module, declared \\ %{}),
      do: CustomTypes.names(module, %{declared: declared, builtin: Builtin.by_module()})

    test "a type with no entry and no callback is named after its joined module name" do
      assert names(T.Coordinates) ==
               Map.put(
                 @derived,
                 :typescript,
                 "AshTypescriptManifestCustomTypeNamesTestCoordinates"
               )
    end

    test "the built-in Money entry names it Money" do
      assert names(AshMoney.Types.Money) == Map.put(@derived, :typescript, "Money")
    end

    test "the entry's ts_alias wins" do
      entry = %MapType{
        module: SomeLib.Coordinates,
        fields: [%Field{name: :lat, type: :float}],
        ts_alias: "GeoCoordinates"
      }

      assert names(SomeLib.Coordinates, %{SomeLib.Coordinates => entry}) ==
               Map.put(@derived, :typescript, "GeoCoordinates")
    end

    test "an entry without a ts_alias gives the joined module name" do
      entry = %MapType{module: SomeLib.Coordinates, fields: [%Field{name: :lat, type: :float}]}

      assert names(SomeLib.Coordinates, %{SomeLib.Coordinates => entry}) ==
               Map.put(@derived, :typescript, "SomeLibCoordinates")
    end

    test "a type without an entry is named by its typescript_type_alias/0" do
      assert names(T.Aliased) == Map.put(@derived, :typescript, "GeoAliased")
    end

    test "an entry's ts_alias wins over typescript_type_alias/0; without one the callback names it" do
      entry = %MapType{module: T.Aliased, fields: [%Field{name: :lat, type: :float}]}

      assert names(T.Aliased, %{T.Aliased => entry}) ==
               Map.put(@derived, :typescript, "GeoAliased")

      assert names(T.Aliased, %{T.Aliased => %{entry | ts_alias: "EntryAliased"}}) ==
               Map.put(@derived, :typescript, "EntryAliased")
    end

    test "typescript_type_alias/0 wins over a built-in entry, as the type's own callbacks do" do
      builtin = %{T.Aliased => %MapType{module: T.Aliased, ts_alias: "BuiltinAliased"}}

      assert CustomTypes.names(T.Aliased, %{declared: %{}, builtin: builtin}).typescript ==
               "GeoAliased"

      builtin = %{T.Coordinates => %MapType{module: T.Coordinates, ts_alias: "BuiltinCoords"}}

      assert CustomTypes.names(T.Coordinates, %{declared: %{}, builtin: builtin}).typescript ==
               "BuiltinCoords"
    end

    test "a NewType doesn't inherit its subtype's typescript_type_alias/0" do
      assert names(T.NewAliased) ==
               Map.put(
                 @derived,
                 :typescript,
                 "AshTypescriptManifestCustomTypeNamesTestNewAliased"
               )
    end

    test "a NewType without an entry of its own uses its own typescript_type_alias/0" do
      declared = %{AshTypescript.Test.GeoPoint => geo_point_entry(ts_alias: "Geo")}

      assert names(T.NamedNewGeoPoint, declared) ==
               %{typescript: "OwnGeoPoint", zod: nil, valibot: nil}
    end

    test "a replacement gets no named schema for its library" do
      declared = %{AshTypescript.Test.GeoPoint => geo_point_entry(ts_alias: "GeoPoint")}

      assert names(AshTypescript.Test.GeoPoint, declared) ==
               %{typescript: "GeoPoint", zod: nil, valibot: nil}

      declared = %{
        AshTypescript.Test.GeoPoint => geo_point_entry(ts_alias: "GeoPoint", valibot: nil)
      }

      assert names(AshTypescript.Test.GeoPoint, declared) ==
               %{typescript: "GeoPoint", zod: nil, valibot: :derive}
    end

    test "a NewType inherits its subtype's replacement, not its ts_alias" do
      declared = %{
        AshTypescript.Test.GeoPoint => geo_point_entry(ts_alias: "Geo", valibot: nil)
      }

      assert names(T.NewGeoPoint, declared) ==
               %{
                 typescript: "AshTypescriptManifestCustomTypeNamesTestNewGeoPoint",
                 zod: nil,
                 valibot: :derive
               }
    end

    test "a NewType over the built-in Money gets its own name" do
      assert names(T.NewMoney) ==
               Map.put(@derived, :typescript, "AshTypescriptManifestCustomTypeNamesTestNewMoney")
    end
  end

  describe "decorated names" do
    # Compiled once.
    defp holder_manifest do
      module = Module.concat(T, HolderManifest)

      if Code.ensure_loaded?(module) do
        module
      else
        compile_manifest!(
          HolderManifest,
          quote do
            custom_types do
              map AshTypescript.Manifest.CustomTypeNamesTest.Coordinates do
                ts_alias "GeoCoordinates"
                field :lat, :float, allow_nil?: false
              end
            end
          end,
          [T.HolderDomain]
        )
      end
    end

    test "the test manifest's declared definitions carry names" do
      names =
        AshTypescript.manifest().types
        |> Enum.filter(&AshRpc.Manifest.Custom.custom_type?/1)
        |> Map.new(&{&1.module, Custom.type_alias_names(&1)})

      assert names == %{
               AshMoney.Types.Money => %{typescript: "Money", zod: :derive, valibot: :derive},
               AshTypescript.Test.GeoPoint => %{typescript: "GeoPoint", zod: nil, valibot: nil},
               AshTypescript.Test.LineItem => %{
                 typescript: "LineItem",
                 zod: :derive,
                 valibot: :derive
               },
               AshTypescript.Test.Todo.ColorPalette => %{
                 typescript: "ColorPalette",
                 zod: :derive,
                 valibot: :derive
               },
               AshTypescript.Test.Theme => %{typescript: "Theme", zod: :derive, valibot: :derive},
               AshTypescript.Test.TodoRef => %{
                 typescript: "AshTypescriptTestTodoRef",
                 zod: :derive,
                 valibot: :derive
               }
             }
    end

    test "non-declared types get no names" do
      manifest = AshTypescript.manifest()
      theme_map = definition(manifest, AshTypescript.Test.ThemeMap)

      assert theme_map
      assert Custom.type_alias_names(theme_map) == nil

      named = Enum.filter(manifest.types, &Custom.type_name/1)

      assert named != []
      assert Enum.all?(named, &(Custom.type_alias_names(&1) == nil))
    end

    test "DSL names reach the definition" do
      assert holder_manifest() |> AshTypescript.manifest() |> names_in(T.Coordinates) ==
               %{typescript: "GeoCoordinates", zod: :derive, valibot: :derive}
    end

    test "a NewType over a declared type gets its own name" do
      assert holder_manifest() |> AshTypescript.manifest() |> names_in(T.NewCoordinates) ==
               %{
                 typescript: "AshTypescriptManifestCustomTypeNamesTestNewCoordinates",
                 zod: :derive,
                 valibot: :derive
               }
    end

    test "typescript_type_alias/0 names a type without an entry, not its NewType" do
      manifest =
        CallbackNames
        |> compile_manifest!(nil, [T.CallbackHolderDomain])
        |> AshTypescript.manifest()

      assert names_in(manifest, T.Aliased) ==
               %{typescript: "GeoAliased", zod: :derive, valibot: :derive}

      assert names_in(manifest, T.NewAliased) ==
               %{
                 typescript: "AshTypescriptManifestCustomTypeNamesTestNewAliased",
                 zod: :derive,
                 valibot: :derive
               }
    end

    test "AshTypescript.Manifest.redecorate/2 keeps the names" do
      manifest =
        AshTypescript.Manifest.redecorate(AshTypescript.manifest(), output_formatter: :snake_case)

      assert names_in(manifest, AshMoney.Types.Money) ==
               %{typescript: "Money", zod: :derive, valibot: :derive}

      assert names_in(manifest, AshTypescript.Test.Theme) ==
               %{typescript: "Theme", zod: :derive, valibot: :derive}
    end
  end
end
