# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.TypeAliasNamesTest do
  # The alias names of map-like types (declared custom types and
  # field-bearing NewTypes): their precedence (`CustomTypes.alias_name/3`),
  # the decorated `custom.ash_typescript.type_alias_names` read through
  # `AshTypescript.Manifest.Custom.type_alias_names/1`, the compile checks
  # on their callbacks, and the compile dependencies on NewTypes.
  # Manifests are compiled with `Module.create/3` under fixed names.
  use ExUnit.Case, async: false

  alias AshTypescript.CustomTypes
  alias AshTypescript.CustomTypes.{Builtin, Field, MapType}
  alias AshTypescript.Manifest.Custom
  alias AshTypescript.Manifest.TypeAliasNamesTest, as: T

  defmodule MapStorage do
    @moduledoc false
    defmacro __using__(_) do
      quote do
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
    end
  end

  # A declared custom type naming itself.
  defmodule Declared do
    @moduledoc false
    use MapStorage

    def typescript_fields, do: [lat: [type: :float, allow_nil?: false]]
    def typescript_type_alias, do: "DeclaredAlias"
  end

  defmodule Aliased do
    @moduledoc false
    use Ash.TypedStruct

    def typescript_type_alias, do: "AliasedStruct"

    typed_struct do
      field :a, :string
    end
  end

  defmodule Plain do
    @moduledoc false
    use Ash.TypedStruct

    typed_struct do
      field :a, :string
    end
  end

  defmodule BadName do
    @moduledoc false
    use Ash.TypedStruct

    def typescript_type_alias, do: "bad-name"

    typed_struct do
      field :a, :string
    end
  end

  defmodule AtomName do
    @moduledoc false
    use Ash.TypedStruct

    def typescript_type_alias, do: :atom

    typed_struct do
      field :a, :string
    end
  end

  defmodule MapNew do
    @moduledoc false
    use Ash.Type.NewType, subtype_of: :map, constraints: [fields: [a: [type: :string]]]
  end

  defmodule WithNames do
    @moduledoc false
    use Ash.TypedStruct

    def typescript_field_names, do: [a?: "a"]

    typed_struct do
      field :a?, :string
    end
  end

  defmodule Untouched do
    @moduledoc false
    use Ash.TypedStruct

    typed_struct do
      field :a, :string
    end
  end

  defmodule Status do
    @moduledoc false
    use Ash.Type.Enum, values: [:open, :closed]
  end

  defmodule StringNew do
    @moduledoc false
    use Ash.Type.NewType, subtype_of: :string, constraints: [max_length: 10]
  end

  # A generic RPC action whose result reaches every type here, and its domain.
  defmodule Holder do
    @moduledoc false
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "TypeAliasNamesHolder"
    end

    attributes do
      uuid_primary_key :id
    end

    actions do
      action :describe, :map do
        constraints fields: [
                      declared: [type: T.Declared],
                      plain: [type: T.Plain],
                      aliased: [type: T.Aliased],
                      map_new: [type: T.MapNew],
                      with_names: [type: T.WithNames],
                      untouched: [type: T.Untouched],
                      status: [type: T.Status],
                      string_new: [type: T.StringNew]
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
        rpc_action :describe, :describe
      end
    end

    resources do
      resource T.Holder
    end
  end

  defmodule BothCallbacks do
    @moduledoc false
    use Ash.TypedStruct

    def typescript_type_alias, do: "BothCallbacks"
    def typescript_type, do: "BothCallbacksTs"

    typed_struct do
      field :a, :string
    end
  end

  defmodule TypedNamed do
    @moduledoc false
    use Ash.TypedStruct

    def typescript_type, do: "TypedNamedTs"

    typed_struct do
      field :a, :string
    end
  end

  # Holders for the compile checks, one type each.
  defmodule BothHolder do
    @moduledoc false
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "TypeAliasNamesBothHolder"
    end

    attributes do
      uuid_primary_key :id
    end

    actions do
      action :describe, :map do
        constraints fields: [both: [type: T.BothCallbacks]]
        run fn _input, _context -> {:ok, %{}} end
      end
    end
  end

  defmodule BothHolderDomain do
    @moduledoc false
    use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

    typescript_rpc do
      resource T.BothHolder do
        rpc_action :describe_both, :describe
      end
    end

    resources do
      resource T.BothHolder
    end
  end

  defmodule TypedNamedHolder do
    @moduledoc false
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "TypeAliasNamesTypedNamedHolder"
    end

    attributes do
      uuid_primary_key :id
    end

    actions do
      action :describe, :map do
        constraints fields: [typed_named: [type: T.TypedNamed]]
        run fn _input, _context -> {:ok, %{}} end
      end
    end
  end

  defmodule TypedNamedHolderDomain do
    @moduledoc false
    use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

    typescript_rpc do
      resource T.TypedNamedHolder do
        rpc_action :describe_typed_named, :describe
      end
    end

    resources do
      resource T.TypedNamedHolder
    end
  end

  defmodule BadHolder do
    @moduledoc false
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "TypeAliasNamesBadHolder"
    end

    attributes do
      uuid_primary_key :id
    end

    actions do
      action :describe, :map do
        constraints fields: [bad: [type: T.BadName]]
        run fn _input, _context -> {:ok, %{}} end
      end
    end
  end

  defmodule BadHolderDomain do
    @moduledoc false
    use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

    typescript_rpc do
      resource T.BadHolder do
        rpc_action :describe_bad, :describe
      end
    end

    resources do
      resource T.BadHolder
    end
  end

  # The scoped manifest prints the RPC resource warnings; they're captured.
  # A module already compiled under `name` is reused.
  defp compile_manifest!(name, body, domains \\ [T.HolderDomain]) do
    module = Module.concat(T, name)

    unless Code.ensure_loaded?(module) do
      ExUnit.CaptureIO.with_io(:stderr, fn -> create_manifest(module, body, domains) end)
    end

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

  defp compile_error!(name, body, domains) do
    error = assert_raise Spark.Error.DslError, fn -> compile_manifest!(name, body, domains) end
    Exception.message(error)
  end

  defp definition(manifest, module), do: Enum.find(manifest.types, &(&1.module == module))

  defp names_in(manifest, module),
    do: Custom.type_alias_names(definition(manifest, module))

  defp derived(name), do: %{typescript: name, zod: :derive, valibot: :derive}

  defp holder_manifest do
    NamedHolderManifest
    |> compile_manifest!(
      quote do
        custom_types do
          map AshTypescript.Manifest.TypeAliasNamesTest.Plain
          map AshTypescript.Manifest.TypeAliasNamesTest.MapNew, ts_alias: "MapNew"
          map AshTypescript.Manifest.TypeAliasNamesTest.WithNames
        end
      end
    )
    |> AshTypescript.manifest()
  end

  @declared_entry %MapType{module: T.Declared, fields: [%Field{name: :lat, type: :float}]}

  defp custom_types(declared, alias_all? \\ false),
    do: %{declared: declared, builtin: Builtin.by_module(), alias_all_types?: alias_all?}

  defp field_less(module, ts_alias \\ nil),
    do: %{module => %MapType{module: module, fields: [], ts_alias: ts_alias}}

  defp joined(module), do: AshTypescript.Codegen.Helpers.module_type_name(module)

  describe "CustomTypes.alias_name/3" do
    test "declared type: an entry without ts_alias now takes the callback" do
      entry = @declared_entry

      assert CustomTypes.alias_name(T.Declared, custom_types(%{T.Declared => entry}), true) ==
               {:ok, "DeclaredAlias"}

      assert CustomTypes.alias_name(
               T.Declared,
               custom_types(%{T.Declared => %{entry | ts_alias: "E"}}),
               true
             ) == {:ok, "E"}

      assert CustomTypes.alias_name(T.Declared, custom_types(%{}), true) ==
               {:ok, "DeclaredAlias"}

      assert CustomTypes.alias_name(SomeLib.Coordinates, custom_types(%{}), true) ==
               {:ok, "SomeLibCoordinates"}
    end

    test "field-bearing NewType: a field-less entry opts in" do
      assert CustomTypes.alias_name(T.Plain, custom_types(field_less(T.Plain)), false) ==
               {:ok, joined(T.Plain)}

      assert CustomTypes.alias_name(T.Plain, custom_types(field_less(T.Plain, "P")), false) ==
               {:ok, "P"}

      assert CustomTypes.alias_name(T.Aliased, custom_types(field_less(T.Aliased)), false) ==
               {:ok, "AliasedStruct"}

      assert CustomTypes.alias_name(
               T.Aliased,
               custom_types(field_less(T.Aliased, "EntryName")),
               false
             ) == {:ok, "EntryName"}
    end

    test "field-bearing NewType: the callback opts in" do
      assert CustomTypes.alias_name(T.Aliased, custom_types(%{}), false) ==
               {:ok, "AliasedStruct"}
    end

    test "field-bearing NewType: alias_all_types? opts in under the joined name" do
      assert CustomTypes.alias_name(T.Plain, custom_types(%{}, true), false) ==
               {:ok, joined(T.Plain)}

      assert CustomTypes.alias_name(T.Plain, custom_types(%{}, false), false) == {:ok, nil}

      # A map without the option counts as off.
      assert CustomTypes.alias_name(
               T.Plain,
               %{declared: %{}, builtin: Builtin.by_module()},
               false
             ) == {:ok, nil}
    end

    test "an invalid callback result is an error for every kind" do
      for aliased_by_default? <- [true, false] do
        assert CustomTypes.alias_name(T.BadName, custom_types(%{}), aliased_by_default?) ==
                 {:error,
                  ~s[The typescript_type_alias/0 result "bad-name" of #{inspect(T.BadName)} ] <>
                    "is not a TypeScript identifier."}

        assert CustomTypes.alias_name(T.AtomName, custom_types(%{}), aliased_by_default?) ==
                 {:error,
                  "The typescript_type_alias/0 of #{inspect(T.AtomName)} must return a " <>
                    "string, got: :atom."}
      end
    end
  end

  describe "decorated NewType names" do
    test "a field-less entry or the callback names a field-bearing NewType" do
      manifest = holder_manifest()

      assert names_in(manifest, T.Plain) == derived(joined(T.Plain))
      assert names_in(manifest, T.MapNew) == derived("MapNew")
      assert names_in(manifest, T.Aliased) == derived("AliasedStruct")
    end

    test "a NewType with typescript_field_names/0 keeps type_name: nil beside its names" do
      assert definition(holder_manifest(), T.WithNames).custom.ash_typescript ==
               %{type_name: nil, type_alias_names: derived(joined(T.WithNames))}
    end

    test "no opt-in, no names" do
      assert names_in(holder_manifest(), T.Untouched) == nil

      app = AshTypescript.manifest()

      for module <- [
            AshTypescript.Test.TaskStats,
            AshTypescript.Test.TodoTimestamp,
            AshTypescript.Test.ThemeMap
          ] do
        assert definition(app, module), "#{inspect(module)} is in the app manifest"
        assert names_in(app, module) == nil
      end
    end

    test "alias_all_types? names every field-bearing NewType" do
      manifest =
        AliasAllHolderManifest
        |> compile_manifest!(
          quote do
            custom_types do
              alias_all_types? true
            end
          end
        )
        |> AshTypescript.manifest()

      assert names_in(manifest, T.Untouched) == derived(joined(T.Untouched))
      assert names_in(manifest, T.Plain) == derived(joined(T.Plain))
      assert names_in(manifest, T.Aliased) == derived("AliasedStruct")

      for module <- [T.Status, T.StringNew] do
        assert definition(manifest, module), "#{inspect(module)} is in the manifest"
        assert names_in(manifest, module) == nil
      end
    end

    test "AshTypescript.Manifest.redecorate/2 keeps NewType names" do
      manifest =
        AshTypescript.Manifest.redecorate(holder_manifest(), output_formatter: :snake_case)

      assert names_in(manifest, T.Plain) == derived(joined(T.Plain))
      assert names_in(manifest, T.Aliased) == derived("AliasedStruct")
    end
  end

  describe "map-like compile checks" do
    @type_name_message "exports `typescript_type/0`: remove it; the alias is generated " <>
                         "from the fields."

    test "typescript_type_alias/0 with typescript_type/0 on a field-bearing NewType" do
      message = compile_error!(BothCallbacksManifest, nil, [T.BothHolderDomain])

      assert message =~ "#{inspect(T.BothCallbacks)} #{@type_name_message}"
      assert message =~ "custom_types"
    end

    test "under alias_all_types?, a field-bearing NewType exporting typescript_type/0" do
      message =
        compile_error!(
          AliasAllTypedNamedManifest,
          quote do
            custom_types do
              alias_all_types? true
            end
          end,
          [T.TypedNamedHolderDomain]
        )

      assert message =~ "#{inspect(T.TypedNamed)} #{@type_name_message}"
    end

    test "without any opt-in, typescript_type/0 on a field-bearing NewType is unchanged" do
      manifest =
        TypedNamedManifest
        |> compile_manifest!(nil, [T.TypedNamedHolderDomain])
        |> AshTypescript.manifest()

      assert definition(manifest, T.TypedNamed).custom.ash_typescript ==
               %{type_name: "TypedNamedTs"}
    end

    test "an invalid typescript_type_alias/0 on a NewType fails compilation" do
      message = compile_error!(BadNameManifest, nil, [T.BadHolderDomain])

      assert message =~
               ~s[The typescript_type_alias/0 result "bad-name" of #{inspect(T.BadName)} ] <>
                 "is not a TypeScript identifier."
    end
  end

  describe "compile dependencies" do
    defp dependencies(manifest) do
      %{declared: declared, builtin: builtin} = Custom.custom_types(manifest)
      CustomTypes.compile_dependencies(manifest, declared, builtin)
    end

    test "every NewType definition of the test manifest is a dependency" do
      manifest = AshTypescript.manifest()

      new_types =
        for %{module: module} <- manifest.types,
            is_atom(module) and not is_nil(module),
            Ash.Type.NewType.new_type?(module),
            do: module

      assert AshTypescript.Test.TaskStats in new_types
      assert AshTypescript.Test.TodoTimestamp in new_types
      assert new_types -- dependencies(manifest) == []
    end

    test "typescript_type_alias/0 is a dependency unless the entry's ts_alias names the type" do
      entry = fn ts_alias ->
        name = if ts_alias, do: [quote(do: ts_alias(unquote(ts_alias)))], else: []

        quote do
          custom_types do
            map AshTypescript.Manifest.TypeAliasNamesTest.Declared do
              unquote_splicing(name)
              field :lat, :float, allow_nil?: false
            end
          end
        end
      end

      unnamed =
        DeclaredUnnamedManifest |> compile_manifest!(entry.(nil)) |> AshTypescript.manifest()

      named = DeclaredNamedManifest |> compile_manifest!(entry.("E")) |> AshTypescript.manifest()

      assert T.Declared in dependencies(unnamed)
      refute T.Declared in dependencies(named)
    end
  end
end
