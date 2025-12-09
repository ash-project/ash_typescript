# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.VerifyActionTypes.ValidFieldNamesTest do
  use ExUnit.Case, async: true

  @moduletag :generates_warnings

  describe "verify/1 - valid field names pass" do
    test "passes for valid field names in return type" do
      defmodule TestResourceValidReturn do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceValidReturn"
        end

        attributes do
          uuid_primary_key :id
        end

        actions do
          action :get_valid_data, :map do
            constraints fields: [
                          total: [type: :integer],
                          completed: [type: :integer],
                          is_active: [type: :boolean]
                        ]

            run fn _input, _context ->
              {:ok, %{total: 10, completed: 5, is_active: true}}
            end
          end
        end
      end

      defmodule TestDomainValidReturn do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceValidReturn do
            rpc_action :get_valid_data, :get_valid_data
          end
        end

        resources do
          resource TestResourceValidReturn
        end
      end

      result = AshTypescript.VerifierChecker.check_all_verifiers([TestDomainValidReturn])

      assert result == :ok
    end

    test "passes for valid field names in argument type" do
      defmodule TestResourceValidArg do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceValidArg"
        end

        attributes do
          uuid_primary_key :id
        end

        actions do
          action :process_valid_data, :boolean do
            argument :data, :map do
              constraints fields: [
                            field_name: [type: :string],
                            count: [type: :integer],
                            is_enabled: [type: :boolean]
                          ]
            end

            run fn _input, _context ->
              {:ok, true}
            end
          end
        end
      end

      defmodule TestDomainValidArg do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceValidArg do
            rpc_action :process_valid_data, :process_valid_data
          end
        end

        resources do
          resource TestResourceValidArg
        end
      end

      result = AshTypescript.VerifierChecker.check_all_verifiers([TestDomainValidArg])

      assert result == :ok
    end

    test "passes for CRUD actions (return type is resource)" do
      defmodule TestResourceCrud do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceCrud"
        end

        attributes do
          uuid_primary_key :id
          attribute :title, :string, public?: true
        end

        actions do
          defaults [:read, :create]
        end
      end

      defmodule TestDomainCrud do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceCrud do
            rpc_action :list_items, :read
            rpc_action :create_item, :create
          end
        end

        resources do
          resource TestResourceCrud
        end
      end

      result = AshTypescript.VerifierChecker.check_all_verifiers([TestDomainCrud])

      assert result == :ok
    end
  end

  describe "invalid_name?/1" do
    test "returns true for names with underscores followed by digits" do
      invalid_names = [
        "field_1",
        "address_line_2",
        "item__3"
      ]

      for name <- invalid_names do
        assert AshTypescript.Rpc.Verifiers.VerifyActionTypes.invalid_name?(name),
               "#{name} should be invalid"
      end
    end

    test "returns true for names with question marks" do
      invalid_names = [
        "field?",
        "is_valid?",
        "enabled?"
      ]

      for name <- invalid_names do
        assert AshTypescript.Rpc.Verifiers.VerifyActionTypes.invalid_name?(name),
               "#{name} should be invalid"
      end
    end

    test "returns false for valid names" do
      valid_names = [
        "normal_field",
        "camelCase",
        "field1",
        "is_active"
      ]

      for name <- valid_names do
        refute AshTypescript.Rpc.Verifiers.VerifyActionTypes.invalid_name?(name),
               "#{name} should be valid"
      end
    end
  end

  describe "make_name_better/1" do
    test "removes underscores before digits" do
      test_cases = [
        {"field_1", "field1"},
        {"address_line_2", "address_line2"}
      ]

      for {input, expected} <- test_cases do
        assert AshTypescript.Rpc.Verifiers.VerifyActionTypes.make_name_better(input) == expected
      end
    end

    test "removes question marks" do
      test_cases = [
        {"field?", "field"},
        {"is_valid?", "is_valid"}
      ]

      for {input, expected} <- test_cases do
        assert AshTypescript.Rpc.Verifiers.VerifyActionTypes.make_name_better(input) == expected
      end
    end
  end
end
