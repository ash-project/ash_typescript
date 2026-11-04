# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.NameCheck.ReturnTypeFieldNamesTest do
  use ExUnit.Case, async: false

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

      %{message: error_message} =
        assert_raise Spark.Error.DslError, fn ->
          silent_verify_for_domains([TestDomainMapReturn])
        end

      assert error_message =~ "Invalid generated names found."

      assert error_message =~
               ~s{- field :returns.field_1 of action :get_data (RPC actions get_data) → "field1" (formatted), underscore before a digit: wrap it in an Ash.Type.NewType with typescript_field_names/0}

      assert error_message =~
               ~s{- field :returns.is_valid? of action :get_data (RPC actions get_data) → "isValid?" (formatted), not an identifier: wrap it in an Ash.Type.NewType with typescript_field_names/0}
    end

    test "detects a typescript_field_names mapping that isn't a TypeScript identifier" do
      defmodule DashedSwatch do
        use Ash.Type.NewType,
          subtype_of: :map,
          constraints: [fields: [hex_code: [type: :string]]]

        def typescript_field_names, do: [hex_code: "hex-code"]
      end

      defmodule TestResourceDashedMapping do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceDashedMapping"
        end

        attributes do
          uuid_primary_key :id
        end

        actions do
          action :get_swatch, DashedSwatch do
            run fn _input, _context -> {:ok, %{hex_code: "#000000"}} end
          end
        end
      end

      defmodule TestDomainDashedMapping do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceDashedMapping do
            rpc_action :get_swatch, :get_swatch
          end
        end

        resources do
          resource TestResourceDashedMapping
        end
      end

      %{message: error_message} =
        assert_raise Spark.Error.DslError, fn ->
          silent_verify_for_domains([TestDomainDashedMapping])
        end

      assert error_message =~ "Invalid generated names found."

      assert error_message =~
               ~s{- field :hex_code → "hex-code" (typescript_field_names/0), not an identifier: change AshTypescript.Manifest.NameCheck.ReturnTypeFieldNamesTest.DashedSwatch.typescript_field_names/0}
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

      %{message: error_message} =
        assert_raise Spark.Error.DslError, fn ->
          silent_verify_for_domains([TestDomainKeywordReturn])
        end

      assert error_message =~ "Invalid generated names found."

      assert error_message =~
               ~s{- field :returns.enabled? of action :get_options (RPC actions get_options) → "enabled?" (formatted), not an identifier: wrap it in an Ash.Type.NewType with typescript_field_names/0}

      assert error_message =~
               ~s{- field :returns.setting_1 of action :get_options (RPC actions get_options) → "setting1" (formatted), underscore before a digit: wrap it in an Ash.Type.NewType with typescript_field_names/0}
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

      %{message: error_message} =
        assert_raise Spark.Error.DslError, fn ->
          silent_verify_for_domains([TestDomainTupleReturn])
        end

      assert error_message =~ "Invalid generated names found."

      assert error_message =~
               ~s{- field :returns.value_1 of action :get_coords (RPC actions get_coords) → "value1" (formatted), underscore before a digit: wrap it in an Ash.Type.NewType with typescript_field_names/0}

      assert error_message =~
               ~s{- field :returns.value_2 of action :get_coords (RPC actions get_coords) → "value2" (formatted), underscore before a digit: wrap it in an Ash.Type.NewType with typescript_field_names/0}
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

      %{message: error_message} =
        assert_raise Spark.Error.DslError, fn ->
          silent_verify_for_domains([TestDomainUnionReturn])
        end

      assert error_message =~ "Invalid generated names found."

      assert error_message =~
               ~s{- field :returns.error.error_code? of action :get_result (RPC actions get_result) → "errorCode?" (formatted), not an identifier: wrap it in an Ash.Type.NewType with typescript_field_names/0}

      assert error_message =~
               ~s{- field :returns.success.result_1 of action :get_result (RPC actions get_result) → "result1" (formatted), underscore before a digit: wrap it in an Ash.Type.NewType with typescript_field_names/0}
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

      %{message: error_message} =
        assert_raise Spark.Error.DslError, fn ->
          silent_verify_for_domains([TestDomainArrayMapReturn])
        end

      assert error_message =~ "Invalid generated names found."

      assert error_message =~
               ~s{- field :returns[].active? of action :list_items (RPC actions list_items) → "active?" (formatted), not an identifier: wrap it in an Ash.Type.NewType with typescript_field_names/0}

      assert error_message =~
               ~s{- field :returns[].item_1 of action :list_items (RPC actions list_items) → "item1" (formatted), underscore before a digit: wrap it in an Ash.Type.NewType with typescript_field_names/0}
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
