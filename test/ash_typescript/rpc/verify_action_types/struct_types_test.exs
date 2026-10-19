# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.VerifyActionTypes.StructTypesTest do
  use ExUnit.Case, async: false

  describe "verify/1 - Struct types with typed_struct_fields" do
    # Plain Elixir structs used via :struct with an instance_of constraint. Defining
    # typed_struct_fields/0 doesn't make them typed: the manifest has no field types
    # for them, so the RPC action is rejected when the manifest compiles.

    test "rejects a plain struct with typed_struct_fields/0 via instance_of" do
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

      assert_untyped_struct_rejected(
        [TestDomainCustomStructType],
        TestResourceCustomStructType,
        CustomPointStruct
      )
    end

    test "rejects it even with typescript_field_names mappings" do
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

      assert_untyped_struct_rejected(
        [TestDomainCustomStructTypeWithMappings],
        TestResourceCustomStructTypeWithMappings,
        CustomPointStructWithMappings
      )
    end
  end

  # A plain struct is untyped to the manifest (`typed_struct_fields/0` isn't read),
  # so ash_rpc's decorator rejects the RPC action while the manifest compiles.
  defp assert_untyped_struct_rejected(domains, resource, struct_module) do
    error = assert_raise RuntimeError, fn -> silent_verify_for_domains(domains) end
    message = Exception.message(error)

    assert message =~
             ~s[Entrypoint "get_point" (#{inspect(resource)}, action :get_point) returns ] <>
               "an untyped struct, #{inspect(struct_module)}, at returns."

    assert message =~ "* an Ash.TypedStruct"
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
