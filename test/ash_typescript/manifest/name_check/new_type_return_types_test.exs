# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.NameCheck.NewTypeReturnTypesTest do
  use ExUnit.Case, async: false

  describe "verify/1 - Ash.Type.NewType return types (Ash.TypedStruct)" do
    test "detects invalid field names in Ash.TypedStruct returned by generic action" do
      # Define a TypedStruct with invalid field names (no mappings)
      defmodule InvalidFieldsTypedStruct do
        use Ash.TypedStruct

        typed_struct do
          field :total_count, :integer, default: 0
          field :completed?, :boolean
          field :is_urgent?, :boolean, default: false
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
          action :get_stats, InvalidFieldsTypedStruct do
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

      %{message: error_message} =
        assert_raise Spark.Error.DslError, fn ->
          silent_verify_for_domains([TestDomainReturnsTypedStruct])
        end

      assert error_message =~ "Invalid generated names found."

      assert error_message =~
               ~s{- field :completed? → "completed?" (formatted), not an identifier: add typescript_field_names/0 to AshTypescript.Manifest.NameCheck.NewTypeReturnTypesTest.InvalidFieldsTypedStruct, e.g. completed?: "completed"}

      assert error_message =~
               ~s{- field :is_urgent? → "isUrgent?" (formatted), not an identifier: add typescript_field_names/0 to AshTypescript.Manifest.NameCheck.NewTypeReturnTypesTest.InvalidFieldsTypedStruct, e.g. is_urgent?: "isUrgent"}
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
          action :get_stats, AshTypescript.Test.TaskStats do
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

      result = silent_verify_for_domains([TestDomainReturnsTaskStats])

      assert result == :ok
    end
  end

  describe "verify/1 - :struct with instance_of an Ash.TypedStruct" do
    test "rejects it with the hint to use the TypedStruct as the type" do
      defmodule TestResourceInstanceOfTaskStats do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceInstanceOfTaskStats"
        end

        attributes do
          uuid_primary_key :id
        end

        actions do
          action :get_point, :struct do
            constraints instance_of: AshTypescript.Test.TaskStats

            run fn _input, _context ->
              {:ok, %AshTypescript.Test.TaskStats{total_count: 10, completed?: true}}
            end
          end
        end
      end

      defmodule TestDomainInstanceOfTaskStats do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceInstanceOfTaskStats do
            rpc_action :get_point, :get_point
          end
        end

        resources do
          resource TestResourceInstanceOfTaskStats
        end
      end

      message =
        assert_untyped_struct_rejected(
          [TestDomainInstanceOfTaskStats],
          TestResourceInstanceOfTaskStats,
          AshTypescript.Test.TaskStats
        )

      assert message =~
               "* AshTypescript.Test.TaskStats is an Ash type: use it as the type instead of " <>
                 "`:struct` with `instance_of`"
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

      %{message: error_message} =
        assert_raise Spark.Error.DslError, fn ->
          silent_verify_for_domains([TestDomainCustomTypeArgument])
        end

      assert error_message =~ "Invalid generated names found."

      assert error_message =~
               ~s{- field :enabled? → "enabled?" (formatted), not an identifier: add typescript_field_names/0 to AshTypescript.Manifest.NameCheck.NewTypeReturnTypesTest.CustomConfigType, e.g. enabled?: "enabled"}

      assert error_message =~
               ~s{- field :option_2 → "option2" (formatted), underscore before a digit: add typescript_field_names/0 to AshTypescript.Manifest.NameCheck.NewTypeReturnTypesTest.CustomConfigType, e.g. option_2: "option2"}

      assert error_message =~
               ~s{- field :setting_1 → "setting1" (formatted), underscore before a digit: add typescript_field_names/0 to AshTypescript.Manifest.NameCheck.NewTypeReturnTypesTest.CustomConfigType, e.g. setting_1: "setting1"}
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
        silent_verify_for_domains([TestDomainCustomTypeArgWithMappings])

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

      %{message: error_message} =
        assert_raise Spark.Error.DslError, fn ->
          silent_verify_for_domains([TestDomainNestedCustomType])
        end

      assert error_message =~ "Invalid generated names found."

      assert error_message =~
               ~s{- field :count_2 → "count2" (formatted), underscore before a digit: add typescript_field_names/0 to AshTypescript.Manifest.NameCheck.NewTypeReturnTypesTest.InnerCustomType, e.g. count_2: "count2"}

      assert error_message =~
               ~s{- field :value_1 → "value1" (formatted), underscore before a digit: add typescript_field_names/0 to AshTypescript.Manifest.NameCheck.NewTypeReturnTypesTest.InnerCustomType, e.g. value_1: "value1"}
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

      %{message: error_message} =
        assert_raise Spark.Error.DslError, fn ->
          silent_verify_for_domains([TestDomainArrayCustomType])
        end

      assert error_message =~ "Invalid generated names found."

      assert error_message =~
               ~s{- field :in_stock? → "inStock?" (formatted), not an identifier: add typescript_field_names/0 to AshTypescript.Manifest.NameCheck.NewTypeReturnTypesTest.CustomItemType, e.g. in_stock?: "inStock"}

      assert error_message =~
               ~s{- field :item_id_1 → "itemId1" (formatted), underscore before a digit: add typescript_field_names/0 to AshTypescript.Manifest.NameCheck.NewTypeReturnTypesTest.CustomItemType, e.g. item_id_1: "itemId1"}

      assert error_message =~
               ~s{- field :quantity_2 → "quantity2" (formatted), underscore before a digit: add typescript_field_names/0 to AshTypescript.Manifest.NameCheck.NewTypeReturnTypesTest.CustomItemType, e.g. quantity_2: "quantity2"}
    end
  end

  # A `:struct` with `instance_of` and no `fields` constraint is untyped to the
  # manifest, so ash_rpc's decorator rejects the RPC action while the manifest
  # compiles.
  defp assert_untyped_struct_rejected(domains, resource, struct_module) do
    error = assert_raise RuntimeError, fn -> silent_verify_for_domains(domains) end
    message = Exception.message(error)

    assert message =~
             ~s[Entrypoint "get_point" (#{inspect(resource)}, action :get_point) returns ] <>
               "an untyped struct, #{inspect(struct_module)}, at returns."

    assert message =~ "* an Ash.TypedStruct"
    message
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
