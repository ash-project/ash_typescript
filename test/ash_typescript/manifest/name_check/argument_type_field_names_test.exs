# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.NameCheck.ArgumentTypeFieldNamesTest do
  use ExUnit.Case, async: false

  describe "verify/1 - argument type field names" do
    test "detects invalid field names in map argument type" do
      defmodule TestResourceMapArg do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceMapArg"
        end

        attributes do
          uuid_primary_key :id
        end

        actions do
          action :process_data, :boolean do
            argument :data, :map do
              constraints fields: [
                            field_1: [type: :string],
                            is_valid?: [type: :boolean]
                          ]
            end

            run fn _input, _context ->
              {:ok, true}
            end
          end
        end
      end

      defmodule TestDomainMapArg do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceMapArg do
            rpc_action :process_data, :process_data
          end
        end

        resources do
          resource TestResourceMapArg
        end
      end

      %{message: error_message} =
        assert_raise Spark.Error.DslError, fn -> silent_verify_for_domains([TestDomainMapArg]) end

      assert error_message =~ "Invalid generated names found."

      assert error_message =~
               ~s{- field :data.field_1 of action :process_data (RPC actions process_data) → "field1" (formatted), underscore before a digit: wrap it in an Ash.Type.NewType with typescript_field_names/0}

      assert error_message =~
               ~s{- field :data.is_valid? of action :process_data (RPC actions process_data) → "isValid?" (formatted), not an identifier: wrap it in an Ash.Type.NewType with typescript_field_names/0}
    end

    test "detects invalid field names in union argument type" do
      defmodule TestResourceUnionArg do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceUnionArg"
        end

        attributes do
          uuid_primary_key :id
        end

        actions do
          action :handle_input, :boolean do
            argument :input, :union do
              constraints types: [
                            option_a: [
                              type: :map,
                              constraints: [
                                fields: [
                                  value_1: [type: :string]
                                ]
                              ]
                            ]
                          ]
            end

            run fn _input, _context ->
              {:ok, true}
            end
          end
        end
      end

      defmodule TestDomainUnionArg do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceUnionArg do
            rpc_action :handle_input, :handle_input
          end
        end

        resources do
          resource TestResourceUnionArg
        end
      end

      %{message: error_message} =
        assert_raise Spark.Error.DslError, fn ->
          silent_verify_for_domains([TestDomainUnionArg])
        end

      assert error_message =~ "Invalid generated names found."

      assert error_message =~
               ~s{- field :input.option_a.value_1 of action :handle_input (RPC actions handle_input) → "value1" (formatted), underscore before a digit: wrap it in an Ash.Type.NewType with typescript_field_names/0}
    end

    test "detects invalid field names in array of maps argument type" do
      defmodule TestResourceArrayMapArg do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceArrayMapArg"
        end

        attributes do
          uuid_primary_key :id
        end

        actions do
          action :process_items, :boolean do
            argument :items, {:array, :map} do
              constraints items: [
                            fields: [
                              item_1: [type: :string]
                            ]
                          ]
            end

            run fn _input, _context ->
              {:ok, true}
            end
          end
        end
      end

      defmodule TestDomainArrayMapArg do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceArrayMapArg do
            rpc_action :process_items, :process_items
          end
        end

        resources do
          resource TestResourceArrayMapArg
        end
      end

      %{message: error_message} =
        assert_raise Spark.Error.DslError, fn ->
          silent_verify_for_domains([TestDomainArrayMapArg])
        end

      assert error_message =~ "Invalid generated names found."

      assert error_message =~
               ~s{- field :items[].item_1 of action :process_items (RPC actions process_items) → "item1" (formatted), underscore before a digit: wrap it in an Ash.Type.NewType with typescript_field_names/0}
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
