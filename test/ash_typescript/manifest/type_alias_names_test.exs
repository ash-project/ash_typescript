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

  defmodule StringStorage do
    @moduledoc false
    defmacro __using__(_) do
      quote do
        use Ash.Type

        @impl true
        def storage_type(_), do: :string
        @impl true
        def cast_input(value, _), do: {:ok, value}
        @impl true
        def cast_stored(value, _), do: {:ok, value}
        @impl true
        def dump_to_native(value, _), do: {:ok, value}
      end
    end
  end

  # Scalars: NewTypes over primitives and `use Ash.Type` modules.
  defmodule Email do
    @moduledoc false
    use Ash.Type.NewType, subtype_of: :string
  end

  defmodule EmailNamed do
    @moduledoc false
    use Ash.Type.NewType, subtype_of: :string

    def typescript_type_alias, do: "EmailAddress"
  end

  defmodule EmailTyped do
    @moduledoc false
    use Ash.Type.NewType, subtype_of: :string

    def typescript_type, do: "`${string}@${string}`"
    def typescript_type_alias, do: "TypedEmail"
  end

  defmodule TermNew do
    @moduledoc false
    use Ash.Type.NewType, subtype_of: :term
  end

  defmodule AtomNew do
    @moduledoc false
    use Ash.Type.NewType, subtype_of: :atom
  end

  defmodule Opaque do
    @moduledoc false
    use StringStorage
  end

  defmodule OpaqueCb do
    @moduledoc false
    use StringStorage

    def typescript_type_alias, do: "OpaqueCallback"
  end

  defmodule Mfa do
    @moduledoc false
    use StringStorage
  end

  # A NewType over a scalar custom type: its definition is `:unknown` under
  # the NewType's module.
  defmodule OverOpaque do
    @moduledoc false
    use Ash.Type.NewType, subtype_of: T.Opaque
  end

  defmodule MfaNames do
    @moduledoc false
    def ts_type(_constraints), do: "string"
    def bad_alias(_constraints), do: :bad

    def ts_alias(constraints) do
      case Keyword.get(constraints, :max_length) do
        nil -> nil
        max when max <= 10 -> "Short"
        _ -> "Long"
      end
    end
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

  # Scalars for the compile checks, all reached through `ScalarHolder`.
  defmodule OpaqueTyped do
    @moduledoc false
    use StringStorage

    def typescript_type, do: "`op-${string}`"
    def typescript_type_alias, do: "OpaqueTyped"
  end

  defmodule BadScalar do
    @moduledoc false
    use StringStorage

    def typescript_type, do: "string"
    def typescript_type_alias, do: "bad-name"
  end

  defmodule AtomScalar do
    @moduledoc false
    use Ash.Type.NewType, subtype_of: :string

    def typescript_type_alias, do: :atom
  end

  # An attribute typed by `OpaqueTyped`, and one generic action per scalar;
  # each domain below exposes some of them.
  defmodule ScalarHolder do
    @moduledoc false
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "TypeAliasNamesScalarHolder"
    end

    attributes do
      uuid_primary_key :id
      attribute :opaque_typed, T.OpaqueTyped, public?: true
    end

    actions do
      defaults [:read]

      action :email_typed, T.EmailTyped do
        run fn _input, _context -> {:ok, "a@b"} end
      end

      action :bad_scalar, T.BadScalar do
        run fn _input, _context -> {:ok, "a"} end
      end

      action :atom_scalar, T.AtomScalar do
        run fn _input, _context -> {:ok, "a"} end
      end
    end
  end

  defmodule BothScalarDomain do
    @moduledoc false
    use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

    typescript_rpc do
      resource T.ScalarHolder do
        rpc_action :list_scalar_holders, :read
        rpc_action :email_typed, :email_typed
      end
    end

    resources do
      resource T.ScalarHolder
    end
  end

  defmodule BadScalarDomain do
    @moduledoc false
    use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

    typescript_rpc do
      resource T.ScalarHolder do
        rpc_action :bad_scalar, :bad_scalar
      end
    end

    resources do
      resource T.ScalarHolder
    end
  end

  defmodule AtomScalarDomain do
    @moduledoc false
    use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

    typescript_rpc do
      resource T.ScalarHolder do
        rpc_action :atom_scalar, :atom_scalar
      end
    end

    resources do
      resource T.ScalarHolder
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

  defp custom_types(declared), do: %{declared: declared, builtin: Builtin.by_module()}

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

    test "field-bearing NewType: no opt-in, no alias" do
      assert CustomTypes.alias_name(T.Plain, custom_types(%{}), false) == {:ok, nil}
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

  describe "ScalarAliases.name/2" do
    alias Ash.Info.Manifest.Generator.TypeResolver
    alias AshTypescript.Codegen.ScalarAliases
    alias AshTypescript.CustomTypes.Scalar

    defp use_of(module, constraints \\ []), do: TypeResolver.resolve(module, constraints)
    defp definition_of(module), do: TypeResolver.resolve_definition(module)

    defp scalar(module, opts \\ []),
      do: %{module => struct!(%Scalar{module: module, type: Ash.Type.String}, opts)}

    @mfa_entry [
      ts_type: {T.MfaNames, :ts_type, []},
      ts_alias: {T.MfaNames, :ts_alias, []}
    ]

    test "no entry, no callback → nil" do
      assert ScalarAliases.name(use_of(T.Opaque), custom_types(scalar(T.Opaque))) == nil
      assert ScalarAliases.name(definition_of(T.Email), custom_types(%{})) == nil

      assert ScalarAliases.name(definition_of(AshTypescript.Test.HexColor), custom_types(%{})) ==
               nil
    end

    test "a string entry ts_alias names every use" do
      types = custom_types(scalar(T.Opaque, ts_alias: "OpaqueId"))

      assert ScalarAliases.name(use_of(T.Opaque), types) == "OpaqueId"
      assert ScalarAliases.name(use_of(T.Opaque, max_length: 3), types) == "OpaqueId"

      assert ScalarAliases.name(
               definition_of(T.Email),
               custom_types(scalar(T.Email, ts_alias: "Mail"))
             ) == "Mail"
    end

    test "an MFA ts_alias names per use, nil inline with no fallback" do
      types = custom_types(scalar(T.Mfa, @mfa_entry))

      assert ScalarAliases.name(use_of(T.Mfa, max_length: 5), types) == "Short"
      assert ScalarAliases.name(use_of(T.Mfa, max_length: 50), types) == "Long"
      assert ScalarAliases.name(use_of(T.Mfa), types) == nil

      bad =
        scalar(T.Mfa, ts_type: {T.MfaNames, :ts_type, []}, ts_alias: {T.MfaNames, :bad_alias, []})

      assert_raise ArgumentError,
                   "the `ts_alias` MFA #{inspect(T.MfaNames)}.bad_alias/1 of the custom type " <>
                     "#{inspect(T.Mfa)} must return a string or nil, got: :bad",
                   fn -> ScalarAliases.name(use_of(T.Mfa), custom_types(bad)) end
    end

    test "the callback names it, below the entry's ts_alias" do
      assert ScalarAliases.name(definition_of(T.EmailNamed), custom_types(%{})) == "EmailAddress"

      assert ScalarAliases.name(use_of(T.OpaqueCb), custom_types(scalar(T.OpaqueCb))) ==
               "OpaqueCallback"

      assert ScalarAliases.name(
               use_of(T.OpaqueCb),
               custom_types(scalar(T.OpaqueCb, ts_alias: "X"))
             ) == "X"
    end

    test "typescript_type/0 combines with an alias" do
      hex = definition_of(AshTypescript.Test.HexColor)

      assert ScalarAliases.name(definition_of(T.EmailTyped), custom_types(%{})) == "TypedEmail"

      assert ScalarAliases.name(
               hex,
               custom_types(scalar(AshTypescript.Test.HexColor, ts_alias: "Hex"))
             ) == "Hex"
    end

    test "a built-in ts_alias applies without a manifest entry" do
      assert ScalarAliases.name(use_of(AshDoubleEntry.ULID), custom_types(%{})) == "ULID"

      assert ScalarAliases.name(use_of(AshPostgres.Ltree, escape?: true), custom_types(%{})) ==
               "AshPostgresLtreeArray"

      assert ScalarAliases.name(use_of(AshPostgres.Ltree), custom_types(%{})) ==
               "AshPostgresLtreeFlexible"

      # A manifest entry replaces the built-in whole.
      ltree = %{
        AshPostgres.Ltree => %Scalar{module: AshPostgres.Ltree, type: {:array, Ash.Type.String}}
      }

      assert ScalarAliases.name(use_of(AshPostgres.Ltree, escape?: true), custom_types(ltree)) ==
               nil
    end

    # A `scalar` entry's `ts_alias` names NewTypes over primitives (`:term` included)
    # and `use Ash.Type` modules, `typescript_type/0` ones included; nothing else.
    test "an entry's ts_alias names only scalars" do
      named = fn module -> custom_types(scalar(module, ts_alias: "Named")) end

      assert ScalarAliases.name(definition_of(T.AtomNew), named.(T.AtomNew)) == "Named"
      assert ScalarAliases.name(definition_of(T.TermNew), named.(T.TermNew)) == "Named"

      percentage = AshTypescript.Test.Todo.Percentage
      assert ScalarAliases.name(definition_of(percentage), named.(percentage)) == "Named"

      priority = AshTypescript.Test.Todo.PriorityScore
      assert ScalarAliases.name(use_of(priority), named.(priority)) == "Named"

      # A NewType over a scalar custom type, an enum, a primitive and a
      # type reference.
      assert ScalarAliases.name(definition_of(T.OverOpaque), named.(T.OverOpaque)) == nil
      assert ScalarAliases.name(definition_of(T.Status), named.(T.Status)) == nil
      assert ScalarAliases.name(use_of(:string), named.(Ash.Type.String)) == nil
      assert ScalarAliases.name(use_of(:atom), named.(Ash.Type.Atom)) == nil
      assert ScalarAliases.name(use_of(:utc_datetime), named.(Ash.Type.UtcDatetime)) == nil
      assert ScalarAliases.name(use_of(T.Email), named.(T.Email)) == nil
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
      manifest = holder_manifest()

      for module <- [T.Untouched, T.Status, T.StringNew] do
        assert definition(manifest, module), "#{inspect(module)} is in the manifest"
        assert names_in(manifest, module) == nil
      end

      app = AshTypescript.manifest()

      for module <- [AshTypescript.Test.TodoStatistics, AshTypescript.Test.ThemeMap] do
        assert definition(app, module), "#{inspect(module)} is in the app manifest"
        assert names_in(app, module) == nil
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

  describe "scalar compile checks" do
    alias AshTypescript.Codegen.ScalarAliases

    defp scalar_node(manifest, module),
      do: Enum.find(AshTypescript.Manifest.TypeUses.nodes(manifest), &(&1.module == module))

    test "typescript_type_alias/0 with typescript_type/0 on a scalar compiles" do
      manifest =
        BothScalarManifest
        |> compile_manifest!(
          quote do
            custom_types do
              scalar AshTypescript.Manifest.TypeAliasNamesTest.OpaqueTyped, :string
            end
          end,
          [T.BothScalarDomain]
        )
        |> AshTypescript.manifest()

      custom_types = Custom.custom_types(manifest)

      assert %{kind: :unknown} = opaque = scalar_node(manifest, T.OpaqueTyped)
      assert ScalarAliases.name(opaque, custom_types) == "OpaqueTyped"

      assert %{kind: :string} = email = definition(manifest, T.EmailTyped)
      assert ScalarAliases.name(email, custom_types) == "TypedEmail"
    end

    test "an invalid typescript_type_alias/0 on a scalar fails compilation" do
      message = compile_error!(BadScalarManifest, nil, [T.BadScalarDomain])

      assert message =~
               ~s[The typescript_type_alias/0 result "bad-name" of #{inspect(T.BadScalar)} ] <>
                 "is not a TypeScript identifier."

      assert message =~ "custom_types"

      message = compile_error!(AtomScalarManifest, nil, [T.AtomScalarDomain])

      assert message =~
               "The typescript_type_alias/0 of #{inspect(T.AtomScalar)} must return a " <>
                 "string, got: :atom."
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

    test "every :unknown type module the manifest reaches is a dependency" do
      dependencies = dependencies(AshTypescript.manifest())

      for module <- [
            AshTypescript.Test.CustomIdentifier,
            AshTypescript.Test.ExternalCode,
            AshPostgres.Ltree,
            AshTypescript.Test.Todo.PriorityScore
          ] do
        assert module in dependencies, "#{inspect(module)} is not a dependency"
      end
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
