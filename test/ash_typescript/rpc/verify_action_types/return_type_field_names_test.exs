# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.VerifyActionTypes.ReturnTypeFieldNamesTest do
  use ExUnit.Case, async: true

  @moduletag :generates_warnings

  describe "verify/1 - return type field names" do
    test "detects invalid field names in map return type" do
      defmodule TestResourceMapReturn do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceMapReturn"
        end

        attributes do
          uuid_primary_key :id
        end

        actions do
          action :get_data, :map do
            constraints fields: [
                          field_1: [type: :string],
                          is_valid?: [type: :boolean]
                        ]

            run fn _input, _context ->
              {:ok, %{field_1: "test", is_valid?: true}}
            end
          end
        end
      end

      defmodule TestDomainMapReturn do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceMapReturn do
            rpc_action :get_data, :get_data
          end
        end

        resources do
          resource TestResourceMapReturn
        end
      end

      result = AshTypescript.VerifierChecker.check_all_verifiers([TestDomainMapReturn])

      assert {:error, error_message} = result
      assert error_message =~ ~r/Invalid field names found in action return types/
      assert error_message =~ "field_1"
      assert error_message =~ "is_valid?"
    end

    test "detects invalid field names in keyword return type" do
      defmodule TestResourceKeywordReturn do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceKeywordReturn"
        end

        attributes do
          uuid_primary_key :id
        end

        actions do
          action :get_options, :keyword do
            constraints fields: [
                          setting_1: [type: :string],
                          enabled?: [type: :boolean]
                        ]

            run fn _input, _context ->
              {:ok, [setting_1: "test", enabled?: true]}
            end
          end
        end
      end

      defmodule TestDomainKeywordReturn do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceKeywordReturn do
            rpc_action :get_options, :get_options
          end
        end

        resources do
          resource TestResourceKeywordReturn
        end
      end

      result = AshTypescript.VerifierChecker.check_all_verifiers([TestDomainKeywordReturn])

      assert {:error, error_message} = result
      assert error_message =~ ~r/Invalid field names found in action return types/
      assert error_message =~ "setting_1"
      assert error_message =~ "enabled?"
    end

    test "detects invalid field names in tuple return type" do
      defmodule TestResourceTupleReturn do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceTupleReturn"
        end

        attributes do
          uuid_primary_key :id
        end

        actions do
          action :get_coords, :tuple do
            constraints fields: [
                          value_1: [type: :float],
                          value_2: [type: :float]
                        ]

            run fn _input, _context ->
              {:ok, {1.0, 2.0}}
            end
          end
        end
      end

      defmodule TestDomainTupleReturn do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceTupleReturn do
            rpc_action :get_coords, :get_coords
          end
        end

        resources do
          resource TestResourceTupleReturn
        end
      end

      result = AshTypescript.VerifierChecker.check_all_verifiers([TestDomainTupleReturn])

      assert {:error, error_message} = result
      assert error_message =~ ~r/Invalid field names found in action return types/
      assert error_message =~ "value_1"
      assert error_message =~ "value_2"
    end

    test "detects invalid field names in union return type members" do
      defmodule TestResourceUnionReturn do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceUnionReturn"
        end

        attributes do
          uuid_primary_key :id
        end

        actions do
          action :get_result, :union do
            constraints types: [
                          success: [
                            type: :map,
                            constraints: [
                              fields: [
                                result_1: [type: :string]
                              ]
                            ]
                          ],
                          error: [
                            type: :map,
                            constraints: [
                              fields: [
                                error_code?: [type: :integer]
                              ]
                            ]
                          ]
                        ]

            run fn _input, _context ->
              {:ok, %{result_1: "success"}}
            end
          end
        end
      end

      defmodule TestDomainUnionReturn do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceUnionReturn do
            rpc_action :get_result, :get_result
          end
        end

        resources do
          resource TestResourceUnionReturn
        end
      end

      result = AshTypescript.VerifierChecker.check_all_verifiers([TestDomainUnionReturn])

      assert {:error, error_message} = result
      assert error_message =~ ~r/Invalid field names found in action return types/
      assert error_message =~ "result_1"
      assert error_message =~ "error_code?"
    end

    test "detects invalid field names in array of maps return type" do
      defmodule TestResourceArrayMapReturn do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceArrayMapReturn"
        end

        attributes do
          uuid_primary_key :id
        end

        actions do
          action :list_items, {:array, :map} do
            constraints items: [
                          fields: [
                            item_1: [type: :string],
                            active?: [type: :boolean]
                          ]
                        ]

            run fn _input, _context ->
              {:ok, [%{item_1: "test", active?: true}]}
            end
          end
        end
      end

      defmodule TestDomainArrayMapReturn do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceArrayMapReturn do
            rpc_action :list_items, :list_items
          end
        end

        resources do
          resource TestResourceArrayMapReturn
        end
      end

      result = AshTypescript.VerifierChecker.check_all_verifiers([TestDomainArrayMapReturn])

      assert {:error, error_message} = result
      assert error_message =~ ~r/Invalid field names found in action return types/
      assert error_message =~ "item_1"
      assert error_message =~ "active?"
    end
  end
end
