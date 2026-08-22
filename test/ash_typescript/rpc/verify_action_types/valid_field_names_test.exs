# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.VerifyActionTypes.ValidFieldNamesTest do
  use ExUnit.Case, async: false

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

      result = silent_verify_for_domains([TestDomainValidReturn])

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

      result = silent_verify_for_domains([TestDomainValidArg])

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

      result = silent_verify_for_domains([TestDomainCrud])

      assert result == :ok
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
