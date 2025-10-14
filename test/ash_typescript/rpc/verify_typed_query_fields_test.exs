# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.VerifyTypedQueryFieldsTest do
  use ExUnit.Case, async: true

  @moduletag :generates_warnings

  describe "typed query field validation - invalid fields" do
    test "detects unknown field in typed query" do
      defmodule ResourceWithUnknownField do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "ResourceWithUnknownField"
        end

        attributes do
          uuid_primary_key :id
          attribute :title, :string, public?: true
          attribute :description, :string, public?: true
        end

        actions do
          defaults [:read]
        end
      end

      defmodule DomainWithUnknownField do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource ResourceWithUnknownField do
            typed_query :list_items, :read do
              ts_fields_const_name "listItems"
              ts_result_type_name "ListItemsResult"
              fields [:id, :title, :nonexistent_field]
            end
          end
        end

        resources do
          resource ResourceWithUnknownField
        end
      end

      result = AshTypescript.VerifierChecker.check_all_verifiers([DomainWithUnknownField])

      assert {:error, error_message} = result
      assert error_message =~ ~r/Invalid field selection/i
      assert error_message =~ ~r/nonexistent_field/i
    end

    test "detects private field in typed query" do
      defmodule ResourceWithPrivateField do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "ResourceWithPrivateField"
        end

        attributes do
          uuid_primary_key :id
          attribute :title, :string, public?: true
          attribute :internal_data, :string, public?: false
        end

        actions do
          defaults [:read]
        end
      end

      defmodule DomainWithPrivateField do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource ResourceWithPrivateField do
            typed_query :list_items, :read do
              ts_fields_const_name "listItems"
              ts_result_type_name "ListItemsResult"
              fields [:id, :title, :internal_data]
            end
          end
        end

        resources do
          resource ResourceWithPrivateField
        end
      end

      result = AshTypescript.VerifierChecker.check_all_verifiers([DomainWithPrivateField])

      assert {:error, error_message} = result
      assert error_message =~ ~r/Invalid field selection/i
      assert error_message =~ ~r/internal_data/i
    end

    test "detects duplicate fields in typed query" do
      defmodule ResourceWithDuplicateFields do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "ResourceWithDuplicateFields"
        end

        attributes do
          uuid_primary_key :id
          attribute :title, :string, public?: true
        end

        actions do
          defaults [:read]
        end
      end

      defmodule DomainWithDuplicateFields do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource ResourceWithDuplicateFields do
            typed_query :list_items, :read do
              ts_fields_const_name "listItems"
              ts_result_type_name "ListItemsResult"
              fields [:id, :title, :title]
            end
          end
        end

        resources do
          resource ResourceWithDuplicateFields
        end
      end

      result = AshTypescript.VerifierChecker.check_all_verifiers([DomainWithDuplicateFields])

      assert {:error, error_message} = result
      assert error_message =~ ~r/Duplicate field/i
    end
  end

  describe "typed query field validation - relationships" do
    test "detects relationship without nested field selection" do
      defmodule ResourceWithRelationship do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "ResourceWithRelationship"
        end

        attributes do
          uuid_primary_key :id
          attribute :title, :string, public?: true
        end

        relationships do
          has_many :comments, __MODULE__.Comment, public?: true, destination_attribute: :parent_id
        end

        actions do
          defaults [:read]
        end

        defmodule Comment do
          use Ash.Resource,
            domain: nil,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshTypescript.Resource]

          typescript do
            type_name "Comment"
          end

          attributes do
            uuid_primary_key :id
            attribute :parent_id, :uuid, public?: false
            attribute :content, :string, public?: true
          end

          actions do
            defaults [:read]
          end
        end
      end

      defmodule DomainWithRelationshipNoNested do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource ResourceWithRelationship do
            typed_query :list_items, :read do
              ts_fields_const_name "listItems"
              ts_result_type_name "ListItemsResult"
              fields [:id, :title, :comments]
            end
          end
        end

        resources do
          resource ResourceWithRelationship
          resource ResourceWithRelationship.Comment
        end
      end

      result =
        AshTypescript.VerifierChecker.check_all_verifiers([DomainWithRelationshipNoNested])

      assert {:error, error_message} = result
      assert error_message =~ ~r/requires nested field selection/i
    end

    test "detects unknown field in nested relationship" do
      defmodule ResourceWithNestedInvalid do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "ResourceWithNestedInvalid"
        end

        attributes do
          uuid_primary_key :id
          attribute :title, :string, public?: true
        end

        relationships do
          has_many :comments, __MODULE__.Comment, public?: true, destination_attribute: :parent_id
        end

        actions do
          defaults [:read]
        end

        defmodule Comment do
          use Ash.Resource,
            domain: nil,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshTypescript.Resource]

          typescript do
            type_name "NestedComment"
          end

          attributes do
            uuid_primary_key :id
            attribute :parent_id, :uuid, public?: false
            attribute :content, :string, public?: true
          end

          actions do
            defaults [:read]
          end
        end
      end

      defmodule DomainWithNestedInvalid do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource ResourceWithNestedInvalid do
            typed_query :list_items, :read do
              ts_fields_const_name "listItems"
              ts_result_type_name "ListItemsResult"
              fields [:id, :title, %{comments: [:id, :nonexistent]}]
            end
          end
        end

        resources do
          resource ResourceWithNestedInvalid
          resource ResourceWithNestedInvalid.Comment
        end
      end

      result = AshTypescript.VerifierChecker.check_all_verifiers([DomainWithNestedInvalid])

      assert {:error, error_message} = result
      assert error_message =~ ~r/Invalid field selection/i
      assert error_message =~ ~r/nonexistent/i
    end
  end

  describe "typed query field validation - complex types" do
    test "detects calculation requiring arguments but not provided" do
      defmodule ResourceWithCalcArgs do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "ResourceWithCalcArgs"
        end

        attributes do
          uuid_primary_key :id
          attribute :title, :string, public?: true
        end

        calculations do
          calculate :prefixed, :string, {__MODULE__.PrefixCalc, []} do
            public? true
            argument :prefix, :string, allow_nil?: false
          end
        end

        actions do
          defaults [:read]
        end

        defmodule PrefixCalc do
          use Ash.Resource.Calculation

          def calculate(records, _opts, %{arguments: %{prefix: prefix}}) do
            Enum.map(records, fn record ->
              "#{prefix}: #{record.title}"
            end)
          end
        end
      end

      defmodule DomainWithCalcNoArgs do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource ResourceWithCalcArgs do
            typed_query :list_items, :read do
              ts_fields_const_name "listItems"
              ts_result_type_name "ListItemsResult"
              fields [:id, :title, :prefixed]
            end
          end
        end

        resources do
          resource ResourceWithCalcArgs
        end
      end

      result = AshTypescript.VerifierChecker.check_all_verifiers([DomainWithCalcNoArgs])

      assert {:error, error_message} = result
      assert error_message =~ ~r/requires arguments/i
    end
  end

  describe "typed query field validation - valid cases" do
    test "accepts valid typed query with simple fields" do
      defmodule ValidResource do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "ValidResource"
        end

        attributes do
          uuid_primary_key :id
          attribute :title, :string, public?: true
          attribute :description, :string, public?: true
        end

        actions do
          defaults [:read]
        end
      end

      defmodule ValidDomain do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource ValidResource do
            typed_query :list_items, :read do
              ts_fields_const_name "listItems"
              ts_result_type_name "ListItemsResult"
              fields [:id, :title, :description]
            end
          end
        end

        resources do
          resource ValidResource
        end
      end

      result = AshTypescript.VerifierChecker.check_all_verifiers([ValidDomain])

      assert :ok = result
    end

    test "accepts valid typed query with nested relationships" do
      defmodule ValidResourceWithRel do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "ValidResourceWithRel"
        end

        attributes do
          uuid_primary_key :id
          attribute :title, :string, public?: true
        end

        relationships do
          has_many :comments, __MODULE__.Comment, public?: true, destination_attribute: :parent_id
        end

        actions do
          defaults [:read]
        end

        defmodule Comment do
          use Ash.Resource,
            domain: nil,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshTypescript.Resource]

          typescript do
            type_name "ValidComment"
          end

          attributes do
            uuid_primary_key :id
            attribute :parent_id, :uuid, public?: false
            attribute :content, :string, public?: true
          end

          actions do
            defaults [:read]
          end
        end
      end

      defmodule ValidDomainWithRel do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource ValidResourceWithRel do
            typed_query :list_items, :read do
              ts_fields_const_name "listItems"
              ts_result_type_name "ListItemsResult"
              fields [:id, :title, %{comments: [:id, :content]}]
            end
          end
        end

        resources do
          resource ValidResourceWithRel
          resource ValidResourceWithRel.Comment
        end
      end

      result = AshTypescript.VerifierChecker.check_all_verifiers([ValidDomainWithRel])

      assert :ok = result
    end
  end
end
