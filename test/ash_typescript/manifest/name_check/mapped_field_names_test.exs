# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.NameCheck.MappedFieldNamesTest do
  use ExUnit.Case, async: false

  describe "typescript_field_names/0 values wherever the manifest reaches the type" do
    test "rejects a mapping that isn't a TypeScript identifier on a resource attribute" do
      defmodule DashedAttributeSwatch do
        use Ash.Type.NewType,
          subtype_of: :map,
          constraints: [fields: [hex_code: [type: :string]]]

        def typescript_field_names, do: [hex_code: "hex-code"]
      end

      defmodule TestResourceDashedAttribute do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceDashedAttribute"
        end

        attributes do
          uuid_primary_key :id
          attribute :swatch, DashedAttributeSwatch, public?: true
        end

        actions do
          defaults [:read]
        end
      end

      defmodule TestDomainDashedAttribute do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceDashedAttribute do
            rpc_action :list_dashed, :read
          end
        end

        resources do
          resource TestResourceDashedAttribute
        end
      end

      %{message: error_message} =
        assert_raise Spark.Error.DslError, fn ->
          silent_verify_for_domains([TestDomainDashedAttribute])
        end

      assert error_message =~
               "  Type #{inspect(DashedAttributeSwatch)}:\n" <>
                 ~s{    - field :hex_code → "hex-code" (typescript_field_names/0), not an identifier: } <>
                 "change #{inspect(DashedAttributeSwatch)}.typescript_field_names/0\n"
    end

    test "accepts a mapping to a TypeScript identifier on a resource attribute" do
      defmodule CamelAttributeSwatch do
        use Ash.Type.NewType,
          subtype_of: :map,
          constraints: [fields: [hex_code: [type: :string]]]

        def typescript_field_names, do: [hex_code: "hexCode"]
      end

      defmodule TestResourceCamelAttribute do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceCamelAttribute"
        end

        attributes do
          uuid_primary_key :id
          attribute :swatch, CamelAttributeSwatch, public?: true
        end

        actions do
          defaults [:read]
        end
      end

      defmodule TestDomainCamelAttribute do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceCamelAttribute do
            rpc_action :list_camel, :read
          end
        end

        resources do
          resource TestResourceCamelAttribute
        end
      end

      assert silent_verify_for_domains([TestDomainCamelAttribute]) == :ok
    end
  end

  describe "a mapping on the struct module of an inline :struct attribute" do
    defmodule DashedStruct do
      defstruct [:hex_code]

      def typescript_field_names, do: [hex_code: "hex-code"]
    end

    test "is reported under the resource, with a fix naming the struct module" do
      defmodule TestResourceDashedStruct do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceDashedStruct"
        end

        attributes do
          uuid_primary_key :id

          attribute :swatch, :struct,
            public?: true,
            constraints: [instance_of: DashedStruct, fields: [hex_code: [type: :string]]]
        end

        actions do
          defaults [:read]
        end
      end

      defmodule TestDomainDashedStruct do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceDashedStruct do
            rpc_action :list_dashed_struct, :read
          end
        end

        resources do
          resource TestResourceDashedStruct
        end
      end

      %{message: error_message} =
        assert_raise Spark.Error.DslError, fn ->
          silent_verify_for_domains([TestDomainDashedStruct])
        end

      assert error_message =~
               ~s{- field :swatch.hex_code → "hex-code" (typescript_field_names/0), not an identifier: } <>
                 "change #{inspect(DashedStruct)}.typescript_field_names/0\n"
    end
  end

  describe "a mapping reached through a typed controller route" do
    defmodule DashedRouteSwatch do
      use Ash.Type.NewType,
        subtype_of: :map,
        constraints: [fields: [hex_code: [type: :string]]]

      def typescript_field_names, do: [hex_code: "hex-code"]
    end

    test "is reported by the manifest too" do
      %{message: error_message} =
        assert_raise Spark.Error.DslError, fn ->
          ExUnit.CaptureIO.with_io(:standard_error, fn ->
            defmodule DashedRouteController do
              use AshTypescript.TypedController

              typed_controller do
                module_name AshTypescript.Test.DashedRouteSwatchController

                get :swatch do
                  run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
                  returns DashedRouteSwatch
                end
              end
            end

            module = Module.concat(__MODULE__, DashedRouteManifest)

            Module.create(
              module,
              quote do
                use AshTypescript.Manifest,
                  otp_app: :ash_typescript,
                  domains: [],
                  typed_controllers: [DashedRouteController]
              end,
              Macro.Env.location(__ENV__)
            )

            AshTypescript.Manifest.run_verifiers(module)
          end)
        end

      assert error_message =~
               "  Type #{inspect(DashedRouteSwatch)}:\n" <>
                 ~s{    - field :hex_code → "hex-code" (typescript_field_names/0), not an identifier: } <>
                 "change #{inspect(DashedRouteSwatch)}.typescript_field_names/0\n"
    end
  end

  describe "a mapping reached through an entrypoint and a resource attribute" do
    test "is reported once, under the type definition" do
      defmodule DashedSharedSwatch do
        use Ash.Type.NewType,
          subtype_of: :map,
          constraints: [fields: [hex_code: [type: :string]]]

        def typescript_field_names, do: [hex_code: "hex-code"]
      end

      defmodule TestResourceDashedShared do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceDashedShared"
        end

        attributes do
          uuid_primary_key :id
          attribute :swatch, DashedSharedSwatch, public?: true
        end

        actions do
          defaults [:read]

          action :get_swatch, DashedSharedSwatch do
            run fn _input, _context -> {:ok, %{hex_code: "#000000"}} end
          end
        end
      end

      defmodule TestDomainDashedShared do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceDashedShared do
            rpc_action :list_shared, :read
            rpc_action :get_swatch, :get_swatch
          end
        end

        resources do
          resource TestResourceDashedShared
        end
      end

      %{message: error_message} =
        assert_raise Spark.Error.DslError, fn ->
          silent_verify_for_domains([TestDomainDashedShared])
        end

      line =
        "  Type #{inspect(DashedSharedSwatch)}:\n" <>
          ~s{    - field :hex_code → "hex-code" (typescript_field_names/0), not an identifier: } <>
          "change #{inspect(DashedSharedSwatch)}.typescript_field_names/0\n"

      assert length(String.split(error_message, line)) == 2
      assert length(String.split(error_message, ~s{"hex-code"})) == 2
    end
  end

  describe "the hint for a custom type with a `map` entry" do
    defmodule EntrySwatch do
      @moduledoc false
      # Declared by a manifest `map` entry, so `typescript_field_names/0` isn't read.
      use AshTypescript.Test.PassThroughType

      def typescript_field_names, do: [is_on?: "isOn"]
    end

    defmodule TestResourceEntrySwatch do
      use Ash.Resource,
        domain: nil,
        data_layer: Ash.DataLayer.Ets,
        extensions: [AshTypescript.Resource]

      typescript do
        type_name "TestResourceEntrySwatch"
      end

      attributes do
        uuid_primary_key :id
      end

      actions do
        action :paint, :boolean do
          argument :swatch, EntrySwatch
          run fn _input, _context -> {:ok, true} end
        end
      end
    end

    defmodule TestDomainEntrySwatch do
      use Ash.Domain,
        otp_app: :ash_typescript,
        extensions: [AshTypescript.Rpc]

      typescript_rpc do
        resource TestResourceEntrySwatch do
          rpc_action :paint, :paint
        end
      end

      resources do
        resource TestResourceEntrySwatch
      end
    end

    test "points to the entry's client_name, not typescript_field_names/0" do
      module = Module.concat(__MODULE__, EntryManifest)

      %{message: error_message} =
        assert_raise Spark.Error.DslError, fn ->
          ExUnit.CaptureIO.with_io(:stderr, fn ->
            Module.create(
              module,
              quote do
                use AshTypescript.Manifest,
                  otp_app: :ash_typescript,
                  domains: [TestDomainEntrySwatch]

                custom_types do
                  map EntrySwatch do
                    field :is_on?, :boolean
                  end
                end
              end,
              Macro.Env.location(__ENV__)
            )
          end)
        end

      assert error_message =~
               "  Type #{inspect(EntrySwatch)} (custom_types map entry):\n" <>
                 ~s{    - field :is_on? → "isOn?" (formatted), not an identifier: } <>
                 ~s{set client_name on the field, e.g. client_name: "isOn"\n}

      refute error_message =~ "typescript_field_names/0"
    end

    test "keeps the typescript_field_names/0 hint for a type without one" do
      defmodule NoEntryOptions do
        use Ash.Type.NewType,
          subtype_of: :map,
          constraints: [fields: [is_on?: [type: :boolean]]]
      end

      defmodule TestResourceNoEntry do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceNoEntry"
        end

        attributes do
          uuid_primary_key :id
        end

        actions do
          action :configure, :boolean do
            argument :options, NoEntryOptions
            run fn _input, _context -> {:ok, true} end
          end
        end
      end

      defmodule TestDomainNoEntry do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceNoEntry do
            rpc_action :configure, :configure
          end
        end

        resources do
          resource TestResourceNoEntry
        end
      end

      %{message: error_message} =
        assert_raise Spark.Error.DslError, fn ->
          silent_verify_for_domains([TestDomainNoEntry])
        end

      assert error_message =~
               ~s{- field :is_on? → "isOn?" (formatted), not an identifier: } <>
                 ~s{add typescript_field_names/0 to #{inspect(NoEntryOptions)}, e.g. is_on?: "isOn"\n}

      refute error_message =~ "client_name"
    end
  end

  describe "a `map` entry field without client_name wherever the manifest reaches the type" do
    defmodule UnnamedEntryToggle do
      @moduledoc false
      # Declared by a manifest `map` entry in each test.
      use AshTypescript.Test.PassThroughType
    end

    defmodule TestResourceUnnamedEntry do
      use Ash.Resource,
        domain: nil,
        data_layer: Ash.DataLayer.Ets,
        extensions: [AshTypescript.Resource]

      typescript do
        type_name "TestResourceUnnamedEntry"
      end

      attributes do
        uuid_primary_key :id
        attribute :toggle, UnnamedEntryToggle, public?: true
      end

      actions do
        defaults [:read]

        action :get_toggle, UnnamedEntryToggle do
          run fn _input, _context -> {:ok, %{is_on?: true}} end
        end
      end
    end

    defmodule TestDomainUnnamedEntry do
      use Ash.Domain,
        otp_app: :ash_typescript,
        extensions: [AshTypescript.Rpc]

      typescript_rpc do
        resource TestResourceUnnamedEntry do
          rpc_action :list_unnamed_entry, :read
        end
      end

      resources do
        resource TestResourceUnnamedEntry
      end
    end

    defmodule TestDomainUnnamedEntryAction do
      use Ash.Domain,
        otp_app: :ash_typescript,
        extensions: [AshTypescript.Rpc]

      typescript_rpc do
        resource TestResourceUnnamedEntry do
          rpc_action :list_unnamed_entry, :read
          rpc_action :get_toggle, :get_toggle
        end
      end

      resources do
        resource TestResourceUnnamedEntry
      end
    end

    test "rejects a formatter-made name that isn't valid on a resource attribute" do
      %{message: error_message} =
        assert_raise Spark.Error.DslError, fn ->
          verify_with_entry(UnnamedEntryAttributeManifest, TestDomainUnnamedEntry, [])
        end

      assert error_message =~
               "  Type #{inspect(UnnamedEntryToggle)} (custom_types map entry):\n" <>
                 ~s{    - field :is_on? → "isOn?" (formatted), not an identifier: } <>
                 ~s{set client_name on the field, e.g. client_name: "isOn"\n}
    end

    test "accepts the field with a client_name that is a TypeScript identifier" do
      assert verify_with_entry(UnnamedEntryNamedManifest, TestDomainUnnamedEntry,
               client_name: "isOn"
             ) == :ok
    end

    test "is reported once, under the type definition, when an action reaches the type too" do
      %{message: error_message} =
        assert_raise Spark.Error.DslError, fn ->
          verify_with_entry(UnnamedEntrySharedManifest, TestDomainUnnamedEntryAction, [])
        end

      line =
        "  Type #{inspect(UnnamedEntryToggle)} (custom_types map entry):\n" <>
          ~s{    - field :is_on? → "isOn?" (formatted), not an identifier: } <>
          ~s{set client_name on the field, e.g. client_name: "isOn"\n}

      assert length(String.split(error_message, line)) == 2
      assert length(String.split(error_message, ~s{"isOn?"})) == 2
    end
  end

  # A manifest over `domain` whose `map` entry declares `UnnamedEntryToggle`'s
  # `is_on?` field with `field_opts`.
  defp verify_with_entry(name, domain, field_opts) do
    module = Module.concat(__MODULE__, name)
    toggle = __MODULE__.UnnamedEntryToggle

    ExUnit.CaptureIO.with_io(:stderr, fn ->
      Module.create(
        module,
        quote do
          use AshTypescript.Manifest,
            otp_app: :ash_typescript,
            domains: [unquote(domain)]

          custom_types do
            map unquote(toggle) do
              field :is_on?, :boolean, unquote(field_opts)
            end
          end
        end,
        Macro.Env.location(__ENV__)
      )
    end)

    AshTypescript.Manifest.run_verifiers(module)
  end

  # Compiling the throwaway manifest module makes Elixir's parallel checker echo
  # raised DslErrors (and RPC config IO.warn output) to stderr, so silence it.
  defp silent_verify_for_domains(domains) do
    {result, _stderr} =
      ExUnit.CaptureIO.with_io(:standard_error, fn ->
        AshTypescript.Manifest.verify_for_domains(domains)
      end)

    result
  end
end
