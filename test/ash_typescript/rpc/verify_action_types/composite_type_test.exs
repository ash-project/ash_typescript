# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.VerifyActionTypes.CompositeTypeTest do
  use ExUnit.Case, async: false

  describe "verify/1 - custom composite Ash.Type" do
    test "detects invalid field names in composite type return" do
      defmodule CompositeTypeWithInvalidFields do
        use Ash.Type

        @impl true
        def storage_type(_), do: :map

        @impl true
        def cast_input(nil, _), do: {:ok, nil}
        def cast_input(value, _) when is_map(value), do: {:ok, value}
        def cast_input(_, _), do: :error

        @impl true
        def cast_stored(nil, _), do: {:ok, nil}
        def cast_stored(value, _) when is_map(value), do: {:ok, value}
        def cast_stored(_, _), do: :error

        @impl true
        def dump_to_native(nil, _), do: {:ok, nil}
        def dump_to_native(value, _) when is_map(value), do: {:ok, value}
        def dump_to_native(_, _), do: :error

        @impl true
        def composite?(_), do: true

        @impl true
        def composite_types(_) do
          [
            {:field_1, :string, []},
            {:is_active?, :boolean, []},
            {:value_2, :integer, []}
          ]
        end
      end

      defmodule TestResourceCompositeReturn do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceCompositeReturn"
        end

        attributes do
          uuid_primary_key :id
        end

        actions do
          action :get_composite, CompositeTypeWithInvalidFields do
            run fn _input, _context ->
              {:ok, %{field_1: "test", is_active?: true, value_2: 42}}
            end
          end
        end
      end

      defmodule TestDomainCompositeReturn do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceCompositeReturn do
            rpc_action :get_composite, :get_composite
          end
        end

        resources do
          resource TestResourceCompositeReturn
        end
      end

      result = silent_verify_for_domains([TestDomainCompositeReturn])

      assert {:error, error_message} = result
      assert error_message =~ ~r/Invalid field names found in action return types/
      assert error_message =~ "field_1"
      assert error_message =~ "is_active?"
      assert error_message =~ "value_2"
    end

    test "accepts composite type with typescript_field_names callback" do
      defmodule CompositeTypeWithMappings do
        use Ash.Type

        @impl true
        def storage_type(_), do: :map

        @impl true
        def cast_input(nil, _), do: {:ok, nil}
        def cast_input(value, _) when is_map(value), do: {:ok, value}
        def cast_input(_, _), do: :error

        @impl true
        def cast_stored(nil, _), do: {:ok, nil}
        def cast_stored(value, _) when is_map(value), do: {:ok, value}
        def cast_stored(_, _), do: :error

        @impl true
        def dump_to_native(nil, _), do: {:ok, nil}
        def dump_to_native(value, _) when is_map(value), do: {:ok, value}
        def dump_to_native(_, _), do: :error

        @impl true
        def composite?(_), do: true

        @impl true
        def composite_types(_) do
          [
            {:field_1, :string, []},
            {:is_active?, :boolean, []}
          ]
        end

        def typescript_field_names do
          [
            field_1: "field1",
            is_active?: "isActive"
          ]
        end
      end

      defmodule TestResourceCompositeWithMappings do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceCompositeWithMappings"
        end

        attributes do
          uuid_primary_key :id
        end

        actions do
          action :get_composite, CompositeTypeWithMappings do
            run fn _input, _context ->
              {:ok, %{field_1: "test", is_active?: true}}
            end
          end
        end
      end

      defmodule TestDomainCompositeWithMappings do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceCompositeWithMappings do
            rpc_action :get_composite, :get_composite
          end
        end

        resources do
          resource TestResourceCompositeWithMappings
        end
      end

      result =
        silent_verify_for_domains([TestDomainCompositeWithMappings])

      assert result == :ok
    end

    test "detects invalid field names in composite type used as argument" do
      defmodule CompositeArgTypeWithInvalidFields do
        use Ash.Type

        @impl true
        def storage_type(_), do: :map

        @impl true
        def cast_input(nil, _), do: {:ok, nil}
        def cast_input(value, _) when is_map(value), do: {:ok, value}
        def cast_input(_, _), do: :error

        @impl true
        def cast_stored(nil, _), do: {:ok, nil}
        def cast_stored(value, _) when is_map(value), do: {:ok, value}
        def cast_stored(_, _), do: :error

        @impl true
        def dump_to_native(nil, _), do: {:ok, nil}
        def dump_to_native(value, _) when is_map(value), do: {:ok, value}
        def dump_to_native(_, _), do: :error

        @impl true
        def composite?(_), do: true

        @impl true
        def composite_types(_) do
          [
            {:arg_1, :string, []},
            {:is_valid?, :boolean, []}
          ]
        end
      end

      defmodule TestResourceCompositeArg do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceCompositeArg"
        end

        attributes do
          uuid_primary_key :id
        end

        actions do
          action :process_composite, :boolean do
            argument :data, CompositeArgTypeWithInvalidFields, allow_nil?: false

            run fn _input, _context ->
              {:ok, true}
            end
          end
        end
      end

      defmodule TestDomainCompositeArg do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceCompositeArg do
            rpc_action :process_composite, :process_composite
          end
        end

        resources do
          resource TestResourceCompositeArg
        end
      end

      result = silent_verify_for_domains([TestDomainCompositeArg])

      assert {:error, error_message} = result
      assert error_message =~ ~r/Invalid field names found in action return types/
      assert error_message =~ "arg_1"
      assert error_message =~ "is_valid?"
    end

    test "detects invalid field names in nested composite types" do
      defmodule NestedCompositeType do
        use Ash.Type

        @impl true
        def storage_type(_), do: :map

        @impl true
        def cast_input(nil, _), do: {:ok, nil}
        def cast_input(value, _) when is_map(value), do: {:ok, value}
        def cast_input(_, _), do: :error

        @impl true
        def cast_stored(nil, _), do: {:ok, nil}
        def cast_stored(value, _) when is_map(value), do: {:ok, value}
        def cast_stored(_, _), do: :error

        @impl true
        def dump_to_native(nil, _), do: {:ok, nil}
        def dump_to_native(value, _) when is_map(value), do: {:ok, value}
        def dump_to_native(_, _), do: :error

        @impl true
        def composite?(_), do: true

        @impl true
        def composite_types(_) do
          [
            {:name, :string, []},
            {:nested_data, Ash.Type.Map,
             [
               fields: [
                 inner_1: [type: :string],
                 is_nested?: [type: :boolean]
               ]
             ]}
          ]
        end
      end

      defmodule TestResourceNestedComposite do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceNestedComposite"
        end

        attributes do
          uuid_primary_key :id
        end

        actions do
          action :get_nested, NestedCompositeType do
            run fn _input, _context ->
              {:ok, %{name: "test", nested_data: %{inner_1: "a", is_nested?: true}}}
            end
          end
        end
      end

      defmodule TestDomainNestedComposite do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceNestedComposite do
            rpc_action :get_nested, :get_nested
          end
        end

        resources do
          resource TestResourceNestedComposite
        end
      end

      result = silent_verify_for_domains([TestDomainNestedComposite])

      assert {:error, error_message} = result
      assert error_message =~ ~r/Invalid field names found in action return types/
      # Should detect nested invalid field names
      assert error_message =~ "inner_1"
      assert error_message =~ "is_nested?"
    end

    # ash_rpc walks a composite type's composite_types/1, so a :struct entry
    # without fields is rejected when the manifest compiles, as at the top level.
    test "rejects a :struct with instance_of a TypedStruct nested in a composite type" do
      defmodule NestedTypedStructPoint do
        use Ash.TypedStruct

        typed_struct do
          field :x_1, :float
        end
      end

      defmodule CompositeWithTypedStructField do
        use Ash.Type

        @impl true
        def storage_type(_), do: :map
        @impl true
        def cast_input(value, _), do: {:ok, value}
        @impl true
        def cast_stored(value, _), do: {:ok, value}
        @impl true
        def dump_to_native(value, _), do: {:ok, value}
        @impl true
        def composite?(_), do: true
        @impl true
        def composite_types(_),
          do: [{:point, :struct, [instance_of: NestedTypedStructPoint]}]
      end

      defmodule TestResourceCompositeWithTypedStruct do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceCompositeWithTypedStruct"
        end

        attributes do
          uuid_primary_key :id
        end

        actions do
          action :get_holder, CompositeWithTypedStructField do
            run fn _input, _context -> {:ok, %{}} end
          end
        end
      end

      defmodule TestDomainCompositeWithTypedStruct do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceCompositeWithTypedStruct do
            rpc_action :get_holder, :get_holder
          end
        end

        resources do
          resource TestResourceCompositeWithTypedStruct
        end
      end

      error =
        assert_raise RuntimeError, fn ->
          silent_verify_for_domains([TestDomainCompositeWithTypedStruct])
        end

      message = Exception.message(error)

      assert message =~
               ~s[Entrypoint "get_holder" (#{inspect(TestResourceCompositeWithTypedStruct)}, ] <>
                 "action :get_holder) returns an untyped struct, " <>
                 "#{inspect(NestedTypedStructPoint)}, at returns → point."

      assert message =~
               "#{inspect(NestedTypedStructPoint)} is an Ash type: use it as the type instead"
    end

    test "rejects a plain struct with typed_struct_fields/0 nested in a composite type" do
      defmodule NestedPlainPoint do
        defstruct [:x_1]

        def typed_struct_fields, do: [x_1: [type: :float]]
      end

      defmodule CompositeWithPlainStructField do
        use Ash.Type

        @impl true
        def storage_type(_), do: :map
        @impl true
        def cast_input(value, _), do: {:ok, value}
        @impl true
        def cast_stored(value, _), do: {:ok, value}
        @impl true
        def dump_to_native(value, _), do: {:ok, value}
        @impl true
        def composite?(_), do: true
        @impl true
        def composite_types(_), do: [{:point, :struct, [instance_of: NestedPlainPoint]}]
      end

      defmodule TestResourceCompositeWithPlainStruct do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceCompositeWithPlainStruct"
        end

        attributes do
          uuid_primary_key :id
        end

        actions do
          action :get_holder, CompositeWithPlainStructField do
            run fn _input, _context -> {:ok, %{}} end
          end
        end
      end

      defmodule TestDomainCompositeWithPlainStruct do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceCompositeWithPlainStruct do
            rpc_action :get_holder, :get_holder
          end
        end

        resources do
          resource TestResourceCompositeWithPlainStruct
        end
      end

      error =
        assert_raise RuntimeError, fn ->
          silent_verify_for_domains([TestDomainCompositeWithPlainStruct])
        end

      message = Exception.message(error)

      assert message =~
               ~s[Entrypoint "get_holder" (#{inspect(TestResourceCompositeWithPlainStruct)}, ] <>
                 "action :get_holder) returns an untyped struct, " <>
                 "#{inspect(NestedPlainPoint)}, at returns → point."

      assert message =~ "* an Ash.TypedStruct"
      refute message =~ "is an Ash type"
    end

    test "accepts a TypedStruct typed as itself in a composite type" do
      defmodule NestedTypedStructPointOk do
        use Ash.TypedStruct

        typed_struct do
          field :x, :float
        end
      end

      defmodule CompositeWithTypedStructEntry do
        use Ash.Type

        @impl true
        def storage_type(_), do: :map
        @impl true
        def cast_input(value, _), do: {:ok, value}
        @impl true
        def cast_stored(value, _), do: {:ok, value}
        @impl true
        def dump_to_native(value, _), do: {:ok, value}
        @impl true
        def composite?(_), do: true
        @impl true
        def composite_types(_), do: [{:point, NestedTypedStructPointOk, []}]
      end

      defmodule TestResourceCompositeWithTypedStructEntry do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceCompositeWithTypedStructEntry"
        end

        attributes do
          uuid_primary_key :id
        end

        actions do
          action :get_holder, CompositeWithTypedStructEntry do
            run fn _input, _context -> {:ok, %{}} end
          end
        end
      end

      defmodule TestDomainCompositeWithTypedStructEntry do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceCompositeWithTypedStructEntry do
            rpc_action :get_holder, :get_holder
          end
        end

        resources do
          resource TestResourceCompositeWithTypedStructEntry
        end
      end

      assert :ok = silent_verify_for_domains([TestDomainCompositeWithTypedStructEntry])
    end

    # typed_struct_fields/0 isn't read, so this map-storage type declares no
    # fields: ash_rpc rejects it with the declaration hint.
    test "a custom type with only typed_struct_fields/0 is rejected as undeclared" do
      defmodule CustomTypeWithTypedStructFields do
        use Ash.Type

        def typescript_type, do: "TypedStructFieldsCustom"

        def typed_struct_fields, do: [x_1: [type: :float]]

        @impl true
        def storage_type(_), do: :map
        @impl true
        def cast_input(value, _), do: {:ok, value}
        @impl true
        def cast_stored(value, _), do: {:ok, value}
        @impl true
        def dump_to_native(value, _), do: {:ok, value}
      end

      defmodule TestResourceCustomTypedStructFields do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceCustomTypedStructFields"
        end

        attributes do
          uuid_primary_key :id
        end

        actions do
          action :get_custom, CustomTypeWithTypedStructFields do
            run fn _input, _context -> {:ok, %{}} end
          end
        end
      end

      defmodule TestDomainCustomTypedStructFields do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceCustomTypedStructFields do
            rpc_action :get_custom, :get_custom
          end
        end

        resources do
          resource TestResourceCustomTypedStructFields
        end
      end

      error =
        assert_raise RuntimeError, fn ->
          silent_verify_for_domains([TestDomainCustomTypedStructFields])
        end

      message = Exception.message(error)

      assert message =~
               ~s[Entrypoint "get_custom" (#{inspect(TestResourceCustomTypedStructFields)}, ] <>
                 "action :get_custom) returns an undeclared custom type, " <>
                 "#{inspect(CustomTypeWithTypedStructFields)}, at returns."

      assert message =~
               "Declare its fields with a `map` entry in your manifest module's " <>
                 "`custom_types` section, a `typescript_fields/0` callback on the type, or " <>
                 "`composite?/1` + `composite_types/1`. Remove `typescript_type/0`: " <>
                 "a map-like type's TypeScript is generated from its fields."
    end
  end

  describe "verify/1 - declared custom types" do
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

    defmodule BadlyNamedFields do
      @moduledoc false
      use MapStorage

      def typescript_fields, do: [label: [type: :string]]
      def typescript_field_names, do: [label: "label_1"]
    end

    defmodule EntryDeclared do
      @moduledoc false
      # Declared by a manifest `map` entry.
      use MapStorage
    end

    defmodule BadPoint do
      @moduledoc false
      use Ash.TypedStruct

      typed_struct do
        field :x_1, :float
      end
    end

    defmodule CompositeWithBadPoint do
      @moduledoc false
      use MapStorage

      @impl true
      def composite?(_), do: true
      @impl true
      def composite_types(_), do: [{:point, BadPoint, []}]
    end

    defmodule DeclaredHolder do
      @moduledoc false
      use Ash.Resource,
        domain: nil,
        data_layer: Ash.DataLayer.Ets,
        extensions: [AshTypescript.Resource]

      typescript do
        type_name "DeclaredHolder"
      end

      attributes do
        uuid_primary_key :id
      end

      actions do
        action :get_badly_named, BadlyNamedFields do
          run fn _input, _context -> {:ok, %{label: "a"}} end
        end

        action :get_entry, EntryDeclared do
          run fn _input, _context -> {:ok, %{label: "a"}} end
        end

        action :get_point, CompositeWithBadPoint do
          run fn _input, _context -> {:ok, %{}} end
        end
      end
    end

    defmodule DeclaredHolderDomain do
      @moduledoc false
      use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

      typescript_rpc do
        resource DeclaredHolder do
          rpc_action :get_badly_named, :get_badly_named
          rpc_action :get_entry, :get_entry
          rpc_action :get_point, :get_point
        end
      end

      resources do
        resource DeclaredHolder
      end
    end

    setup do
      %{message: verify_with_entry!(quote(do: field(:label, :string, client_name: "label_1")))}
    end

    defp verify_with_entry!(field) do
      opts = [
        domains: [DeclaredHolderDomain],
        body:
          quote do
            custom_types do
              map AshTypescript.Rpc.VerifyActionTypes.CompositeTypeTest.EntryDeclared do
                unquote(field)
              end
            end
          end
      ]

      AshTypescript.Test.InlineManifest.build!(opts)

      assert {:error, message} =
               opts
               |> AshTypescript.Test.InlineManifest.module_for()
               |> AshTypescript.Manifest.run_verifiers()

      message
    end

    defp context(message, rpc_name) do
      [_, rest] =
        String.split(message, "Invalid field names in return type of RPC action #{rpc_name} ",
          parts: 2
        )

      rest |> String.split("\n\n") |> hd()
    end

    test "a bad field name from typescript_field_names/0 in declared fields", %{message: message} do
      assert context(message, "get_badly_named") =~ "field label -> label"
    end

    test "a bad client_name in a manifest map entry", %{message: message} do
      assert context(message, "get_entry") =~ "field label -> label"
    end

    test "a TypedStruct inside a composite-derived field is name-checked", %{message: message} do
      assert context(message, "get_point") =~ "struct_field x_1 -> x1"
    end

    test "a valid client_name in a manifest map entry passes" do
      message = verify_with_entry!(quote(do: field(:label, :string, client_name: "label")))

      refute message =~ "get_entry"
      assert message =~ "get_badly_named"
    end
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
