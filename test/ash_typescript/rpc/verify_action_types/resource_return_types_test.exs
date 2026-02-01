# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.VerifyActionTypes.ResourceReturnTypesTest do
  use ExUnit.Case, async: true

  @moduletag :generates_warnings

  describe "verify/1 - regular Ash resource return types" do
    test "detects invalid field names in regular Ash resource returned by generic action" do
      # Referenced resource without AshTypescript.Resource extension
      # to avoid resource-level verifier catching the invalid names first
      defmodule ReferencedResourceNoExt do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets

        attributes do
          uuid_primary_key :id
          attribute :field_1, :string, public?: true
          attribute :is_valid?, :boolean, public?: true
        end

        actions do
          defaults [:read]
        end
      end

      defmodule TestResourceReturnsResource do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceReturnsResource"
        end

        attributes do
          uuid_primary_key :id
        end

        actions do
          action :get_referenced, :struct do
            constraints instance_of: ReferencedResourceNoExt

            run fn _input, _context ->
              {:ok,
               %ReferencedResourceNoExt{id: Ash.UUID.generate(), field_1: "test", is_valid?: true}}
            end
          end
        end
      end

      defmodule TestDomainReturnsResource do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceReturnsResource do
            rpc_action :get_referenced, :get_referenced
          end
        end

        resources do
          resource ReferencedResourceNoExt
          resource TestResourceReturnsResource
        end
      end

      result = AshTypescript.VerifierChecker.check_all_verifiers([TestDomainReturnsResource])

      assert {:error, error_message} = result
      assert error_message =~ ~r/Invalid field names found in action return types/
      assert error_message =~ "field_1"
      assert error_message =~ "is_valid?"
    end

    test "passes when regular Ash resource has field_names mappings" do
      defmodule ReferencedResourceWithMappings do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "ReferencedResourceWithMappings"
          field_names field_1: "field1", is_valid?: "isValid"
        end

        attributes do
          uuid_primary_key :id
          attribute :field_1, :string, public?: true
          attribute :is_valid?, :boolean, public?: true
        end

        actions do
          defaults [:read]
        end
      end

      defmodule TestResourceReturnsResourceWithMappings do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceReturnsResourceWithMappings"
        end

        attributes do
          uuid_primary_key :id
        end

        actions do
          action :get_referenced, :struct do
            constraints instance_of: ReferencedResourceWithMappings

            run fn _input, _context ->
              {:ok,
               %ReferencedResourceWithMappings{
                 id: Ash.UUID.generate(),
                 field_1: "test",
                 is_valid?: true
               }}
            end
          end
        end
      end

      defmodule TestDomainReturnsResourceWithMappings do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceReturnsResourceWithMappings do
            rpc_action :get_referenced, :get_referenced
          end
        end

        resources do
          resource ReferencedResourceWithMappings
          resource TestResourceReturnsResourceWithMappings
        end
      end

      result =
        AshTypescript.VerifierChecker.check_all_verifiers([TestDomainReturnsResourceWithMappings])

      assert result == :ok
    end

    test "detects invalid field names in array of regular Ash resources" do
      # Referenced resource without AshTypescript.Resource extension
      defmodule ReferencedResourceForArrayNoExt do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets

        attributes do
          uuid_primary_key :id
          attribute :item_1, :string, public?: true
        end

        actions do
          defaults [:read]
        end
      end

      defmodule TestResourceReturnsArrayOfResources do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceReturnsArrayOfResources"
        end

        attributes do
          uuid_primary_key :id
        end

        actions do
          action :list_referenced, {:array, :struct} do
            constraints items: [instance_of: ReferencedResourceForArrayNoExt]

            run fn _input, _context ->
              {:ok, [%ReferencedResourceForArrayNoExt{id: Ash.UUID.generate(), item_1: "test"}]}
            end
          end
        end
      end

      defmodule TestDomainReturnsArrayOfResources do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceReturnsArrayOfResources do
            rpc_action :list_referenced, :list_referenced
          end
        end

        resources do
          resource ReferencedResourceForArrayNoExt
          resource TestResourceReturnsArrayOfResources
        end
      end

      result =
        AshTypescript.VerifierChecker.check_all_verifiers([TestDomainReturnsArrayOfResources])

      assert {:error, error_message} = result
      assert error_message =~ ~r/Invalid field names found in action return types/
      assert error_message =~ "item_1"
    end
  end
end
