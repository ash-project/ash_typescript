# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.VerifyMappableTypesTest do
  use ExUnit.Case, async: false

  # Snapshot the global config this module mutates so it cannot leak into
  # later test modules.
  setup_all do
    AshTypescript.Test.TestHelpers.restore_application_env_on_exit([:type_mapping_overrides])
  end

  defmodule BareCustomType do
    @moduledoc false
    use Ash.Type

    @impl true
    def storage_type(_), do: :string

    @impl true
    def cast_input(nil, _), do: {:ok, nil}
    def cast_input(value, _) when is_binary(value), do: {:ok, value}
    def cast_input(_, _), do: :error

    @impl true
    def cast_stored(nil, _), do: {:ok, nil}
    def cast_stored(value, _) when is_binary(value), do: {:ok, value}
    def cast_stored(_, _), do: :error

    @impl true
    def dump_to_native(nil, _), do: {:ok, nil}
    def dump_to_native(value, _) when is_binary(value), do: {:ok, value}
    def dump_to_native(_, _), do: :error
  end

  defmodule NamedCustomType do
    @moduledoc false
    use Ash.Type

    def typescript_type_name, do: "string"

    @impl true
    def storage_type(_), do: :string

    @impl true
    def cast_input(nil, _), do: {:ok, nil}
    def cast_input(value, _) when is_binary(value), do: {:ok, value}
    def cast_input(_, _), do: :error

    @impl true
    def cast_stored(nil, _), do: {:ok, nil}
    def cast_stored(value, _) when is_binary(value), do: {:ok, value}
    def cast_stored(_, _), do: :error

    @impl true
    def dump_to_native(nil, _), do: {:ok, nil}
    def dump_to_native(value, _) when is_binary(value), do: {:ok, value}
    def dump_to_native(_, _), do: :error
  end

  describe "unmappable custom types" do
    test "bare custom type on an attribute is rejected with remediation guidance" do
      defmodule ResourceWithBareAttribute do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "ResourceWithBareAttribute"
        end

        attributes do
          uuid_primary_key :id

          attribute :identifier, AshTypescript.Manifest.VerifyMappableTypesTest.BareCustomType do
            public? true
          end
        end

        actions do
          defaults [:read]
        end
      end

      defmodule DomainWithBareAttribute do
        use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource ResourceWithBareAttribute do
            rpc_action :list_bare, :read
          end
        end

        resources do
          resource ResourceWithBareAttribute
        end
      end

      assert {:error, message} = silent_verify_for_domains([DomainWithBareAttribute])

      assert message =~ "Unsupported types found"
      assert message =~ "VerifyMappableTypesTest.BareCustomType"
      assert message =~ "field :identifier"
      assert message =~ "typescript_type_name/0"
      assert message =~ "type_mapping_overrides"
    end

    test "bare custom type as an action argument is rejected with action context" do
      defmodule ResourceWithBareArgument do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "ResourceWithBareArgument"
        end

        attributes do
          uuid_primary_key :id
        end

        actions do
          defaults [:read]

          read :by_identifier do
            argument :identifier, AshTypescript.Manifest.VerifyMappableTypesTest.BareCustomType
          end
        end
      end

      defmodule DomainWithBareArgument do
        use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource ResourceWithBareArgument do
            rpc_action :by_identifier, :by_identifier
          end
        end

        resources do
          resource ResourceWithBareArgument
        end
      end

      assert {:error, message} = silent_verify_for_domains([DomainWithBareArgument])

      assert message =~ "VerifyMappableTypesTest.BareCustomType"
      assert message =~ "action :by_identifier"
      assert message =~ "input :identifier"
    end

    test "bare custom type nested in a typed map field is rejected" do
      defmodule ResourceWithNestedBareType do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "ResourceWithNestedBareType"
        end

        attributes do
          uuid_primary_key :id

          attribute :payload, :map do
            public? true

            constraints fields: [
                          identifier: [
                            type: AshTypescript.Manifest.VerifyMappableTypesTest.BareCustomType
                          ]
                        ]
          end
        end

        actions do
          defaults [:read]
        end
      end

      defmodule DomainWithNestedBareType do
        use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource ResourceWithNestedBareType do
            rpc_action :list_nested, :read
          end
        end

        resources do
          resource ResourceWithNestedBareType
        end
      end

      assert {:error, message} = silent_verify_for_domains([DomainWithNestedBareType])

      assert message =~ "VerifyMappableTypesTest.BareCustomType"
      assert message =~ "field :payload"
    end
  end

  describe "mappable custom types" do
    test "custom type with typescript_type_name/0 passes" do
      defmodule ResourceWithNamedType do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "ResourceWithNamedType"
        end

        attributes do
          uuid_primary_key :id

          attribute :identifier, AshTypescript.Manifest.VerifyMappableTypesTest.NamedCustomType do
            public? true
          end
        end

        actions do
          defaults [:read]
        end
      end

      defmodule DomainWithNamedType do
        use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource ResourceWithNamedType do
            rpc_action :list_named, :read
          end
        end

        resources do
          resource ResourceWithNamedType
        end
      end

      assert silent_verify_for_domains([DomainWithNamedType]) == :ok
    end

    test "bare custom type with a type_mapping_overrides entry passes" do
      defmodule ResourceWithOverriddenType do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "ResourceWithOverriddenType"
        end

        attributes do
          uuid_primary_key :id

          attribute :identifier, AshTypescript.Manifest.VerifyMappableTypesTest.BareCustomType do
            public? true
          end
        end

        actions do
          defaults [:read]
        end
      end

      defmodule DomainWithOverriddenType do
        use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource ResourceWithOverriddenType do
            rpc_action :list_overridden, :read
          end
        end

        resources do
          resource ResourceWithOverriddenType
        end
      end

      original = Application.get_env(:ash_typescript, :type_mapping_overrides, [])

      Application.put_env(:ash_typescript, :type_mapping_overrides, [
        {AshTypescript.Manifest.VerifyMappableTypesTest.BareCustomType, "string"} | original
      ])

      on_exit(fn ->
        Application.put_env(:ash_typescript, :type_mapping_overrides, original)
      end)

      assert silent_verify_for_domains([DomainWithOverriddenType]) == :ok
    end
  end

  defp silent_verify_for_domains(domains) do
    {result, _stderr} =
      ExUnit.CaptureIO.with_io(:standard_error, fn ->
        AshTypescript.Manifest.verify_for_domains(domains)
      end)

    result
  end
end
