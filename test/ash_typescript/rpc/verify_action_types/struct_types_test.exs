# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.VerifyActionTypes.StructTypesTest do
  use ExUnit.Case, async: true

  @moduletag :generates_warnings

  describe "verify/1 - Struct types with typed_struct_fields" do
    # Tests for custom struct modules used via :struct type with instance_of constraint
    # These are plain Elixir structs that define typed_struct_fields/0 for field introspection

    test "detects invalid field names in custom struct via instance_of" do
      defmodule CustomPointStruct do
        defstruct [:x_1, :y_2, :is_valid?]

        def typed_struct_fields do
          [
            {:x_1, [type: :float]},
            {:y_2, [type: :float]},
            {:is_valid?, [type: :boolean]}
          ]
        end
      end

      defmodule TestResourceCustomStructType do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceCustomStructType"
        end

        attributes do
          uuid_primary_key :id
        end

        actions do
          action :get_point, :struct do
            constraints instance_of: CustomPointStruct

            run fn _input, _context ->
              {:ok, %CustomPointStruct{x_1: 1.0, y_2: 2.0, is_valid?: true}}
            end
          end
        end
      end

      defmodule TestDomainCustomStructType do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceCustomStructType do
            rpc_action :get_point, :get_point
          end
        end

        resources do
          resource TestResourceCustomStructType
        end
      end

      result = AshTypescript.VerifierChecker.check_all_verifiers([TestDomainCustomStructType])

      assert {:error, error_message} = result
      assert error_message =~ ~r/Invalid field names found in action return types/
      assert error_message =~ "x_1"
      assert error_message =~ "y_2"
      assert error_message =~ "is_valid?"
    end

    test "passes when custom struct has typescript_field_names mappings" do
      defmodule CustomPointStructWithMappings do
        defstruct [:x_1, :y_2, :is_valid?]

        def typed_struct_fields do
          [
            {:x_1, [type: :float]},
            {:y_2, [type: :float]},
            {:is_valid?, [type: :boolean]}
          ]
        end

        def typescript_field_names do
          [
            x_1: :x1,
            y_2: :y2,
            is_valid?: :isValid
          ]
        end
      end

      defmodule TestResourceCustomStructTypeWithMappings do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceCustomStructTypeWithMappings"
        end

        attributes do
          uuid_primary_key :id
        end

        actions do
          action :get_point, :struct do
            constraints instance_of: CustomPointStructWithMappings

            run fn _input, _context ->
              {:ok, %CustomPointStructWithMappings{x_1: 1.0, y_2: 2.0, is_valid?: true}}
            end
          end
        end
      end

      defmodule TestDomainCustomStructTypeWithMappings do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceCustomStructTypeWithMappings do
            rpc_action :get_point, :get_point
          end
        end

        resources do
          resource TestResourceCustomStructTypeWithMappings
        end
      end

      result =
        AshTypescript.VerifierChecker.check_all_verifiers([
          TestDomainCustomStructTypeWithMappings
        ])

      assert result == :ok
    end
  end
end
