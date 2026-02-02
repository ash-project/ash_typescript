# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.VerifyActionTypes.CustomAshTypeTest do
  use ExUnit.Case, async: true

  @moduletag :generates_warnings

  describe "verify/1 - Truly custom Ash.Type (use Ash.Type)" do
    # Tests for custom types defined with `use Ash.Type` directly,
    # not using Ash.Type.NewType. These are completely custom type implementations.

    test "primitive custom Ash.Type passes verification (no field structure)" do
      # A simple primitive custom type - like a custom float or string type
      # These have no internal field structure, so should always pass
      defmodule CustomPrimitiveType do
        use Ash.Type

        @impl true
        def storage_type(_), do: :string

        @impl true
        def cast_input(nil, _), do: {:ok, nil}
        def cast_input(value, _) when is_binary(value), do: {:ok, String.upcase(value)}
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

      defmodule TestResourcePrimitiveCustomType do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourcePrimitiveCustomType"
        end

        attributes do
          uuid_primary_key :id
        end

        actions do
          action :get_value, CustomPrimitiveType do
            run fn _input, _context ->
              {:ok, "HELLO"}
            end
          end
        end
      end

      defmodule TestDomainPrimitiveCustomType do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourcePrimitiveCustomType do
            rpc_action :get_value, :get_value
          end
        end

        resources do
          resource TestResourcePrimitiveCustomType
        end
      end

      result = AshTypescript.VerifierChecker.check_all_verifiers([TestDomainPrimitiveCustomType])

      # Primitive types have no field structure to validate
      assert result == :ok
    end

    test "custom Ash.Type used as action argument passes when primitive" do
      defmodule CustomIdentifierType do
        use Ash.Type

        @impl true
        def storage_type(_), do: :string

        @impl true
        def cast_input(nil, _), do: {:ok, nil}

        def cast_input(value, _) when is_binary(value) do
          if String.match?(value, ~r/^[A-Z]{3}-\d{4}$/) do
            {:ok, value}
          else
            :error
          end
        end

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

      defmodule TestResourceCustomTypeAsArg do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceCustomTypeAsArg"
        end

        attributes do
          uuid_primary_key :id
        end

        actions do
          action :lookup, :boolean do
            argument :identifier, CustomIdentifierType

            run fn _input, _context ->
              {:ok, true}
            end
          end
        end
      end

      defmodule TestDomainCustomTypeAsArg do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceCustomTypeAsArg do
            rpc_action :lookup, :lookup
          end
        end

        resources do
          resource TestResourceCustomTypeAsArg
        end
      end

      result = AshTypescript.VerifierChecker.check_all_verifiers([TestDomainCustomTypeAsArg])

      assert result == :ok
    end

    test "composite custom Ash.Type with invalid field names in composite_types" do
      # A composite type (like a Point) that has field structure via composite_types/1
      # This type has invalid field names in its composite structure
      defmodule CustomCompositePointType do
        use Ash.Type

        @impl true
        def storage_type(_), do: :map

        @impl true
        def cast_input(nil, _), do: {:ok, nil}

        def cast_input(%{x_1: x, y_2: y}, _) when is_number(x) and is_number(y) do
          {:ok, %{x_1: x, y_2: y}}
        end

        def cast_input(_, _), do: :error

        @impl true
        def cast_stored(nil, _), do: {:ok, nil}
        def cast_stored(%{} = value, _), do: {:ok, value}
        def cast_stored(_, _), do: :error

        @impl true
        def dump_to_native(nil, _), do: {:ok, nil}
        def dump_to_native(%{x_1: x, y_2: y}, _), do: {:ok, %{x_1: x, y_2: y}}
        def dump_to_native(_, _), do: :error

        # Composite type callbacks - these define the field structure
        @impl true
        def composite?(_), do: true

        @impl true
        def composite_types(_) do
          # Format: {field_name, type, constraints}
          # These field names are invalid for TypeScript (underscore + digit)
          [{:x_1, :float, []}, {:y_2, :float, []}]
        end
      end

      defmodule TestResourceCompositeType do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceCompositeType"
        end

        attributes do
          uuid_primary_key :id
        end

        actions do
          action :get_point, CustomCompositePointType do
            run fn _input, _context ->
              {:ok, %{x_1: 1.0, y_2: 2.0}}
            end
          end
        end
      end

      defmodule TestDomainCompositeType do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceCompositeType do
            rpc_action :get_point, :get_point
          end
        end

        resources do
          resource TestResourceCompositeType
        end
      end

      result = AshTypescript.VerifierChecker.check_all_verifiers([TestDomainCompositeType])

      # Composite types are now verified - invalid field names should be detected
      assert {:error, error_message} = result
      assert error_message =~ ~r/Invalid field names found in action return types/
      assert error_message =~ "x_1"
      assert error_message =~ "y_2"
    end

    test "custom Ash.Type with constraints callback can define field structure" do
      # A custom type that uses constraints to define its field structure
      # When used with field constraints, those should be verified
      defmodule CustomMapLikeType do
        use Ash.Type

        @impl true
        def storage_type(_), do: :map

        @impl true
        def constraints do
          [
            fields: [
              type: {:spark_opts, []},
              doc: "The fields and their types"
            ]
          ]
        end

        @impl true
        def cast_input(nil, _), do: {:ok, nil}
        def cast_input(%{} = value, _), do: {:ok, value}
        def cast_input(_, _), do: :error

        @impl true
        def cast_stored(nil, _), do: {:ok, nil}
        def cast_stored(%{} = value, _), do: {:ok, value}
        def cast_stored(_, _), do: :error

        @impl true
        def dump_to_native(nil, _), do: {:ok, nil}
        def dump_to_native(%{} = value, _), do: {:ok, value}
        def dump_to_native(_, _), do: :error
      end

      defmodule TestResourceCustomMapLikeType do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceCustomMapLikeType"
        end

        attributes do
          uuid_primary_key :id
        end

        actions do
          # When we use this type with field constraints, those constraints
          # should be validated by the verifier
          action :get_config, :map do
            constraints fields: [
                          setting_1: [type: :string],
                          enabled?: [type: :boolean]
                        ]

            run fn _input, _context ->
              {:ok, %{setting_1: "value", enabled?: true}}
            end
          end
        end
      end

      defmodule TestDomainCustomMapLikeType do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceCustomMapLikeType do
            rpc_action :get_config, :get_config
          end
        end

        resources do
          resource TestResourceCustomMapLikeType
        end
      end

      result = AshTypescript.VerifierChecker.check_all_verifiers([TestDomainCustomMapLikeType])

      # The :map type with field constraints should be verified
      assert {:error, error_message} = result
      assert error_message =~ ~r/Invalid field names found in action return types/
      assert error_message =~ "setting_1"
      assert error_message =~ "enabled?"
    end

    test "array of custom primitive Ash.Type passes verification" do
      defmodule CustomTagType do
        use Ash.Type

        @impl true
        def storage_type(_), do: :string

        @impl true
        def cast_input(nil, _), do: {:ok, nil}

        def cast_input(value, _) when is_binary(value) do
          {:ok, String.downcase(String.trim(value))}
        end

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

      defmodule TestResourceArrayOfCustomType do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceArrayOfCustomType"
        end

        attributes do
          uuid_primary_key :id
        end

        actions do
          action :get_tags, {:array, CustomTagType} do
            run fn _input, _context ->
              {:ok, ["elixir", "ash", "typescript"]}
            end
          end
        end
      end

      defmodule TestDomainArrayOfCustomType do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceArrayOfCustomType do
            rpc_action :get_tags, :get_tags
          end
        end

        resources do
          resource TestResourceArrayOfCustomType
        end
      end

      result = AshTypescript.VerifierChecker.check_all_verifiers([TestDomainArrayOfCustomType])

      assert result == :ok
    end
  end
end
