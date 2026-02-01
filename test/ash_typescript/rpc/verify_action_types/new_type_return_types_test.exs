# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.VerifyActionTypes.NewTypeReturnTypesTest do
  use ExUnit.Case, async: true

  @moduletag :generates_warnings

  describe "verify/1 - Ash.Type.NewType return types (Ash.TypedStruct)" do
    test "detects invalid field names in Ash.TypedStruct returned by generic action" do
      # Define a TypedStruct with invalid field names (no mappings)
      defmodule InvalidFieldsTypedStruct do
        use Ash.TypedStruct

        typed_struct do
          field(:total_count, :integer, default: 0)
          field(:completed?, :boolean)
          field(:is_urgent?, :boolean, default: false)
        end
      end

      defmodule TestResourceReturnsTypedStruct do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceReturnsTypedStruct"
        end

        attributes do
          uuid_primary_key :id
        end

        actions do
          action :get_stats, :struct do
            constraints instance_of: InvalidFieldsTypedStruct

            run fn _input, _context ->
              {:ok, %InvalidFieldsTypedStruct{total_count: 10, completed?: true}}
            end
          end
        end
      end

      defmodule TestDomainReturnsTypedStruct do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceReturnsTypedStruct do
            rpc_action :get_stats, :get_stats
          end
        end

        resources do
          resource TestResourceReturnsTypedStruct
        end
      end

      result = AshTypescript.VerifierChecker.check_all_verifiers([TestDomainReturnsTypedStruct])

      assert {:error, error_message} = result
      assert error_message =~ ~r/Invalid field names found in action return types/
      assert error_message =~ "completed?"
      assert error_message =~ "is_urgent?"
    end

    test "passes when Ash.TypedStruct has typescript_field_names mappings" do
      # AshTypescript.Test.TaskStats has typescript_field_names/0 callback
      defmodule TestResourceReturnsTaskStats do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceReturnsTaskStats"
        end

        attributes do
          uuid_primary_key :id
        end

        actions do
          action :get_stats, :struct do
            constraints instance_of: AshTypescript.Test.TaskStats

            run fn _input, _context ->
              {:ok, %AshTypescript.Test.TaskStats{total_count: 10, completed?: true}}
            end
          end
        end
      end

      defmodule TestDomainReturnsTaskStats do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceReturnsTaskStats do
            rpc_action :get_stats, :get_stats
          end
        end

        resources do
          resource TestResourceReturnsTaskStats
        end
      end

      result = AshTypescript.VerifierChecker.check_all_verifiers([TestDomainReturnsTaskStats])

      assert result == :ok
    end
  end

  describe "verify/1 - Struct types with typed_struct_fields" do
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

  describe "verify/1 - NewType-based custom types" do
    test "detects invalid field names in NewType-based custom type as argument" do
      defmodule CustomConfigType do
        use Ash.Type.NewType,
          subtype_of: :map,
          constraints: [
            fields: [
              setting_1: [type: :string],
              option_2: [type: :integer],
              enabled?: [type: :boolean]
            ]
          ]
      end

      defmodule TestResourceCustomTypeArgument do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceCustomTypeArgument"
        end

        attributes do
          uuid_primary_key :id
        end

        actions do
          action :configure, :boolean do
            argument :config, CustomConfigType

            run fn _input, _context ->
              {:ok, true}
            end
          end
        end
      end

      defmodule TestDomainCustomTypeArgument do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceCustomTypeArgument do
            rpc_action :configure, :configure
          end
        end

        resources do
          resource TestResourceCustomTypeArgument
        end
      end

      result = AshTypescript.VerifierChecker.check_all_verifiers([TestDomainCustomTypeArgument])

      assert {:error, error_message} = result
      assert error_message =~ ~r/Invalid field names found in action return types or argument/
      assert error_message =~ "setting_1"
      assert error_message =~ "option_2"
      assert error_message =~ "enabled?"
    end

    test "passes when NewType-based custom type has typescript_field_names" do
      defmodule CustomConfigTypeWithMappings do
        use Ash.Type.NewType,
          subtype_of: :map,
          constraints: [
            fields: [
              setting_1: [type: :string],
              option_2: [type: :integer],
              enabled?: [type: :boolean]
            ]
          ]

        def typescript_field_names do
          [
            setting_1: :setting1,
            option_2: :option2,
            enabled?: :enabled
          ]
        end
      end

      defmodule TestResourceCustomTypeArgWithMappings do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceCustomTypeArgWithMappings"
        end

        attributes do
          uuid_primary_key :id
        end

        actions do
          action :configure, :boolean do
            argument :config, CustomConfigTypeWithMappings

            run fn _input, _context ->
              {:ok, true}
            end
          end
        end
      end

      defmodule TestDomainCustomTypeArgWithMappings do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceCustomTypeArgWithMappings do
            rpc_action :configure, :configure
          end
        end

        resources do
          resource TestResourceCustomTypeArgWithMappings
        end
      end

      result =
        AshTypescript.VerifierChecker.check_all_verifiers([TestDomainCustomTypeArgWithMappings])

      assert result == :ok
    end

    test "detects invalid field names in nested NewType-based custom types" do
      defmodule InnerCustomType do
        use Ash.Type.NewType,
          subtype_of: :map,
          constraints: [
            fields: [
              value_1: [type: :string],
              count_2: [type: :integer]
            ]
          ]
      end

      defmodule OuterCustomType do
        use Ash.Type.NewType,
          subtype_of: :map,
          constraints: [
            fields: [
              name: [type: :string],
              inner: [type: InnerCustomType]
            ]
          ]
      end

      defmodule TestResourceNestedCustomType do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceNestedCustomType"
        end

        attributes do
          uuid_primary_key :id
        end

        actions do
          action :get_nested, OuterCustomType do
            run fn _input, _context ->
              {:ok, %{name: "test", inner: %{value_1: "val", count_2: 5}}}
            end
          end
        end
      end

      defmodule TestDomainNestedCustomType do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceNestedCustomType do
            rpc_action :get_nested, :get_nested
          end
        end

        resources do
          resource TestResourceNestedCustomType
        end
      end

      result = AshTypescript.VerifierChecker.check_all_verifiers([TestDomainNestedCustomType])

      assert {:error, error_message} = result
      assert error_message =~ ~r/Invalid field names found in action return types/
      assert error_message =~ "value_1"
      assert error_message =~ "count_2"
    end

    test "detects invalid field names in array of NewType-based custom type" do
      defmodule CustomItemType do
        use Ash.Type.NewType,
          subtype_of: :map,
          constraints: [
            fields: [
              item_id_1: [type: :string],
              quantity_2: [type: :integer],
              in_stock?: [type: :boolean]
            ]
          ]
      end

      defmodule TestResourceArrayCustomType do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceArrayCustomType"
        end

        attributes do
          uuid_primary_key :id
        end

        actions do
          action :list_items, {:array, CustomItemType} do
            run fn _input, _context ->
              {:ok, [%{item_id_1: "abc", quantity_2: 10, in_stock?: true}]}
            end
          end
        end
      end

      defmodule TestDomainArrayCustomType do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceArrayCustomType do
            rpc_action :list_items, :list_items
          end
        end

        resources do
          resource TestResourceArrayCustomType
        end
      end

      result = AshTypescript.VerifierChecker.check_all_verifiers([TestDomainArrayCustomType])

      assert {:error, error_message} = result
      assert error_message =~ ~r/Invalid field names found in action return types/
      assert error_message =~ "item_id_1"
      assert error_message =~ "quantity_2"
      assert error_message =~ "in_stock?"
    end
  end
end
