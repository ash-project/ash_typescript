# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.VerifyMetadataFieldNamesTest do
  use ExUnit.Case, async: true

  @moduletag :generates_warnings

  describe "metadata field name validation - invalid TypeScript names" do
    test "detects metadata fields with underscores followed by digits" do
      defmodule TestResourceWithInvalidMetadataName do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceWithInvalidMetadataName"
        end

        attributes do
          uuid_primary_key :id
          attribute :name, :string, public?: true
        end

        actions do
          defaults [:read, :destroy, create: [:name], update: [:name]]

          read :read_with_metadata do
            metadata :field_1, :string
            metadata :valid_field, :integer
          end
        end
      end

      defmodule TestDomainWithInvalidMetadataName do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceWithInvalidMetadataName do
            rpc_action :read_data, :read_with_metadata, show_metadata: [:field_1, :valid_field]
          end
        end

        resources do
          resource TestResourceWithInvalidMetadataName
        end
      end

      result =
        AshTypescript.VerifierChecker.check_all_verifiers([TestDomainWithInvalidMetadataName])

      assert {:error, error_message} = result
      assert error_message =~ ~r/Invalid metadata field name/
      assert error_message =~ ~r/field_1/
      assert error_message =~ ~r/field1/
    end

    test "detects metadata fields with question marks" do
      defmodule TestResourceWithQuestionMarkMetadata do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceWithQuestionMarkMetadata"
        end

        attributes do
          uuid_primary_key :id
          attribute :name, :string, public?: true
        end

        actions do
          defaults [:read, :destroy, create: [:name], update: [:name]]

          read :read_with_metadata do
            metadata :is_valid?, :boolean
            metadata :status, :string
          end
        end
      end

      defmodule TestDomainWithQuestionMarkMetadata do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceWithQuestionMarkMetadata do
            rpc_action :read_data, :read_with_metadata, show_metadata: [:is_valid?, :status]
          end
        end

        resources do
          resource TestResourceWithQuestionMarkMetadata
        end
      end

      result =
        AshTypescript.VerifierChecker.check_all_verifiers([
          TestDomainWithQuestionMarkMetadata
        ])

      assert {:error, error_message} = result
      assert error_message =~ ~r/Invalid metadata field name/
      assert error_message =~ ~r/is_valid\?/
      assert error_message =~ ~r/is_valid/
    end

    test "detects metadata fields with combined invalid patterns" do
      defmodule TestResourceWithCombinedInvalidMetadata do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceWithCombinedInvalidMetadata"
        end

        attributes do
          uuid_primary_key :id
          attribute :name, :string, public?: true
        end

        actions do
          defaults [:read, :destroy, create: [:name], update: [:name]]

          read :read_with_metadata do
            metadata :field_1?, :string
            metadata :item__2, :integer
          end
        end
      end

      defmodule TestDomainWithCombinedInvalidMetadata do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceWithCombinedInvalidMetadata do
            rpc_action :read_data, :read_with_metadata, show_metadata: [:field_1?, :item__2]
          end
        end

        resources do
          resource TestResourceWithCombinedInvalidMetadata
        end
      end

      result =
        AshTypescript.VerifierChecker.check_all_verifiers([
          TestDomainWithCombinedInvalidMetadata
        ])

      assert {:error, error_message} = result
      assert error_message =~ ~r/Invalid metadata field name/
      assert error_message =~ ~r/field_1\?/
      assert error_message =~ ~r/item__2/
    end
  end

  describe "metadata field name validation - conflicts with resource fields" do
    test "detects conflict with attribute name" do
      defmodule TestResourceWithAttributeConflict do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceWithAttributeConflict"
        end

        attributes do
          uuid_primary_key :id
          attribute :title, :string, public?: true
          attribute :status, :string, public?: true
        end

        actions do
          defaults [:read, :destroy, create: [:title, :status], update: [:title, :status]]

          read :read_with_metadata do
            metadata :title, :string
            metadata :processing_time, :integer
          end
        end
      end

      defmodule TestDomainWithAttributeConflict do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceWithAttributeConflict do
            rpc_action :read_data, :read_with_metadata, show_metadata: [:title, :processing_time]
          end
        end

        resources do
          resource TestResourceWithAttributeConflict
        end
      end

      result =
        AshTypescript.VerifierChecker.check_all_verifiers([TestDomainWithAttributeConflict])

      assert {:error, error_message} = result
      assert error_message =~ ~r/Metadata field conflicts with resource field/
      assert error_message =~ ~r/title/
    end

    test "detects conflict with calculation name" do
      defmodule TestResourceWithCalculationConflict do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceWithCalculationConflict"
        end

        attributes do
          uuid_primary_key :id
          attribute :value, :integer, public?: true
        end

        calculations do
          calculate :computed_value, :integer, expr(value * 2) do
            public? true
          end
        end

        actions do
          defaults [:read, :destroy, create: [:value], update: [:value]]

          read :read_with_metadata do
            metadata :computed_value, :string
            metadata :status, :string
          end
        end
      end

      defmodule TestDomainWithCalculationConflict do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceWithCalculationConflict do
            rpc_action :read_data, :read_with_metadata, show_metadata: [:computed_value, :status]
          end
        end

        resources do
          resource TestResourceWithCalculationConflict
        end
      end

      result =
        AshTypescript.VerifierChecker.check_all_verifiers([TestDomainWithCalculationConflict])

      assert {:error, error_message} = result
      assert error_message =~ ~r/Metadata field conflicts with resource field/
      assert error_message =~ ~r/computed_value/
    end

    test "detects conflict with mapped field name" do
      defmodule TestResourceWithMappedFieldConflict do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceWithMappedFieldConflict"

          field_names internal_name: "externalName"
        end

        attributes do
          uuid_primary_key :id
          attribute :internal_name, :string, public?: true
        end

        actions do
          defaults [:read, :destroy, create: [:internal_name], update: [:internal_name]]

          read :read_with_metadata do
            # Metadata field has the same name as the mapped field name
            metadata :externalName, :string
          end
        end
      end

      defmodule TestDomainWithMappedFieldConflict do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceWithMappedFieldConflict do
            rpc_action :read_data, :read_with_metadata, show_metadata: [:externalName]
          end
        end

        resources do
          resource TestResourceWithMappedFieldConflict
        end
      end

      result =
        AshTypescript.VerifierChecker.check_all_verifiers([TestDomainWithMappedFieldConflict])

      assert {:error, error_message} = result
      assert error_message =~ ~r/Metadata field conflicts with resource field/
      assert error_message =~ ~r/externalName/
    end
  end

  describe "metadata field name validation - valid configurations" do
    test "allows valid metadata field names with no conflicts" do
      defmodule TestResourceWithValidMetadata do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceWithValidMetadata"
        end

        attributes do
          uuid_primary_key :id
          attribute :title, :string, public?: true
        end

        actions do
          defaults [:read, :destroy, create: [:title], update: [:title]]

          read :read_with_metadata do
            metadata :processing_time, :integer
            metadata :cache_status, :string
            metadata :is_cached, :boolean
          end
        end
      end

      defmodule TestDomainWithValidMetadata do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceWithValidMetadata do
            rpc_action :read_data, :read_with_metadata,
              show_metadata: [:processing_time, :cache_status, :is_cached]
          end
        end

        resources do
          resource TestResourceWithValidMetadata
        end
      end

      result = AshTypescript.VerifierChecker.check_all_verifiers([TestDomainWithValidMetadata])

      assert result == :ok
    end

    test "skips validation when show_metadata is nil" do
      defmodule TestResourceWithNilMetadata do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceWithNilMetadata"
        end

        attributes do
          uuid_primary_key :id
        end

        actions do
          defaults [:read, :destroy]

          read :read_with_metadata do
            metadata :any_field, :string
          end
        end
      end

      defmodule TestDomainWithNilMetadata do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceWithNilMetadata do
            # show_metadata: nil should skip validation
            rpc_action :read_data, :read_with_metadata, show_metadata: nil
          end
        end

        resources do
          resource TestResourceWithNilMetadata
        end
      end

      result = AshTypescript.VerifierChecker.check_all_verifiers([TestDomainWithNilMetadata])

      assert result == :ok
    end

    test "skips validation when show_metadata is false" do
      defmodule TestResourceWithFalseMetadata do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceWithFalseMetadata"
        end

        attributes do
          uuid_primary_key :id
        end

        actions do
          defaults [:read, :destroy]

          read :read_with_metadata do
            metadata :any_field, :string
          end
        end
      end

      defmodule TestDomainWithFalseMetadata do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceWithFalseMetadata do
            # show_metadata: false should skip validation
            rpc_action :read_data, :read_with_metadata, show_metadata: false
          end
        end

        resources do
          resource TestResourceWithFalseMetadata
        end
      end

      result = AshTypescript.VerifierChecker.check_all_verifiers([TestDomainWithFalseMetadata])

      assert result == :ok
    end

    test "skips validation when show_metadata is empty list" do
      defmodule TestResourceWithEmptyMetadata do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceWithEmptyMetadata"
        end

        attributes do
          uuid_primary_key :id
        end

        actions do
          defaults [:read, :destroy]

          read :read_with_metadata do
            metadata :any_field, :string
          end
        end
      end

      defmodule TestDomainWithEmptyMetadata do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceWithEmptyMetadata do
            # show_metadata: [] should skip validation
            rpc_action :read_data, :read_with_metadata, show_metadata: []
          end
        end

        resources do
          resource TestResourceWithEmptyMetadata
        end
      end

      result = AshTypescript.VerifierChecker.check_all_verifiers([TestDomainWithEmptyMetadata])

      assert result == :ok
    end
  end

  describe "metadata_field_names mapping" do
    test "allows invalid metadata field names with proper mapping" do
      defmodule TestResourceWithMappedMetadata do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceWithMappedMetadata"
        end

        attributes do
          uuid_primary_key :id
          attribute :name, :string, public?: true
        end

        actions do
          defaults [:read, :destroy, create: [:name], update: [:name]]

          read :read_with_metadata do
            metadata :field_1, :string
            metadata :is_valid?, :boolean
          end
        end
      end

      defmodule TestDomainWithMappedMetadata do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceWithMappedMetadata do
            rpc_action :read_data, :read_with_metadata,
              show_metadata: [:field_1, :is_valid?],
              metadata_field_names: [field_1: "field1", is_valid?: "isValid"]
          end
        end

        resources do
          resource TestResourceWithMappedMetadata
        end
      end

      result = AshTypescript.VerifierChecker.check_all_verifiers([TestDomainWithMappedMetadata])

      assert result == :ok
    end

    test "detects conflicts even with metadata_field_names mapping" do
      defmodule TestResourceWithMappedConflict do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceWithMappedConflict"
        end

        attributes do
          uuid_primary_key :id
          attribute :title, :string, public?: true
        end

        actions do
          defaults [:read, :destroy, create: [:title], update: [:title]]

          read :read_with_metadata do
            metadata :meta_title, :string
          end
        end
      end

      defmodule TestDomainWithMappedConflict do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceWithMappedConflict do
            # Mapping meta_title to title conflicts with the attribute
            rpc_action :read_data, :read_with_metadata,
              show_metadata: [:meta_title],
              metadata_field_names: [meta_title: "title"]
          end
        end

        resources do
          resource TestResourceWithMappedConflict
        end
      end

      result = AshTypescript.VerifierChecker.check_all_verifiers([TestDomainWithMappedConflict])

      assert {:error, error_message} = result
      assert error_message =~ ~r/Mapped metadata field conflicts with resource field/
      assert error_message =~ ~r/meta_title/
      assert error_message =~ ~r/title/
    end

    test "detects invalid TypeScript names even after mapping" do
      defmodule TestResourceWithInvalidMappedName do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceWithInvalidMappedName"
        end

        attributes do
          uuid_primary_key :id
        end

        actions do
          defaults [:read, :destroy]

          read :read_with_metadata do
            metadata :field_a, :string
          end
        end
      end

      defmodule TestDomainWithInvalidMappedName do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceWithInvalidMappedName do
            # Mapping to an invalid name should still fail
            rpc_action :read_data, :read_with_metadata,
              show_metadata: [:field_a],
              metadata_field_names: [field_a: "field_1"]
          end
        end

        resources do
          resource TestResourceWithInvalidMappedName
        end
      end

      result =
        AshTypescript.VerifierChecker.check_all_verifiers([TestDomainWithInvalidMappedName])

      assert {:error, error_message} = result
      assert error_message =~ ~r/Invalid metadata field name/
      assert error_message =~ ~r/field_a/
      assert error_message =~ ~r/field_1/
    end
  end
end
