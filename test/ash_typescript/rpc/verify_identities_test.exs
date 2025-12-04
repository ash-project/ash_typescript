# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.VerifyIdentitiesTest do
  use ExUnit.Case, async: true

  @moduletag :generates_warnings

  describe "identity validation - non-existent identities" do
    test "detects identity that doesn't exist on resource" do
      defmodule TestResourceWithMissingIdentity do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceWithMissingIdentity"
        end

        attributes do
          uuid_primary_key :id
          attribute :name, :string, public?: true
          attribute :email, :string, public?: true
        end

        identities do
          identity :email, [:email]
        end

        actions do
          defaults [:read, :destroy, create: [:name, :email], update: [:name]]
        end
      end

      defmodule TestDomainWithMissingIdentity do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceWithMissingIdentity do
            rpc_action :update_resource, :update, identities: [:non_existent_identity]
          end
        end

        resources do
          resource TestResourceWithMissingIdentity
        end
      end

      result =
        AshTypescript.VerifierChecker.check_all_verifiers([TestDomainWithMissingIdentity])

      assert {:error, error_message} = result
      assert error_message =~ ~r/Identity not found on resource/
      assert error_message =~ ~r/non_existent_identity/
      assert error_message =~ ~r/Available identities.*:email/
    end

    test "detects multiple non-existent identities" do
      defmodule TestResourceWithMultipleMissingIdentities do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceWithMultipleMissingIdentities"
        end

        attributes do
          uuid_primary_key :id
          attribute :name, :string, public?: true
        end

        actions do
          defaults [:read, :destroy, create: [:name], update: [:name]]
        end
      end

      defmodule TestDomainWithMultipleMissingIdentities do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceWithMultipleMissingIdentities do
            rpc_action :update_resource, :update, identities: [:foo, :bar]
          end
        end

        resources do
          resource TestResourceWithMultipleMissingIdentities
        end
      end

      result =
        AshTypescript.VerifierChecker.check_all_verifiers([
          TestDomainWithMultipleMissingIdentities
        ])

      assert {:error, error_message} = result
      assert error_message =~ ~r/Identity not found on resource/
      assert error_message =~ ~r/:foo/
      assert error_message =~ ~r/:bar/
      assert error_message =~ ~r/No identities are defined on this resource/
    end

    test "shows available identities in error message" do
      defmodule TestResourceWithAvailableIdentities do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceWithAvailableIdentities"
        end

        attributes do
          uuid_primary_key :id
          attribute :email, :string, public?: true
          attribute :username, :string, public?: true
        end

        identities do
          identity :email, [:email]
          identity :username, [:username]
        end

        actions do
          defaults [:read, :destroy, create: [:email, :username], update: [:email, :username]]
        end
      end

      defmodule TestDomainWithAvailableIdentities do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceWithAvailableIdentities do
            rpc_action :update_resource, :update, identities: [:wrong_identity]
          end
        end

        resources do
          resource TestResourceWithAvailableIdentities
        end
      end

      result =
        AshTypescript.VerifierChecker.check_all_verifiers([TestDomainWithAvailableIdentities])

      assert {:error, error_message} = result

      assert error_message =~ ~r/Available identities.*:email.*:username/s or
               error_message =~ ~r/Available identities.*:username.*:email/s
    end

    test "detects :_primary_key used on resource without primary key" do
      defmodule TestResourceWithoutPrimaryKey do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceWithoutPrimaryKey"
        end

        attributes do
          # No primary key defined
          attribute :name, :string, public?: true
        end

        actions do
          defaults [:read, :destroy, create: [:name], update: [:name]]
        end
      end

      defmodule TestDomainWithoutPrimaryKey do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceWithoutPrimaryKey do
            # Using :_primary_key but resource has no primary key
            rpc_action :update_resource, :update, identities: [:_primary_key]
          end
        end

        resources do
          resource TestResourceWithoutPrimaryKey
        end
      end

      result =
        AshTypescript.VerifierChecker.check_all_verifiers([TestDomainWithoutPrimaryKey])

      assert {:error, error_message} = result
      assert error_message =~ ~r/Resource has no primary key/
      assert error_message =~ ~r/:_primary_key identity is configured/
    end
  end

  describe "identity validation - valid configurations" do
    test "allows :_primary_key identity" do
      defmodule TestResourceWithPrimaryKey do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceWithPrimaryKey"
        end

        attributes do
          uuid_primary_key :id
          attribute :name, :string, public?: true
        end

        actions do
          defaults [:read, :destroy, create: [:name], update: [:name]]
        end
      end

      defmodule TestDomainWithPrimaryKey do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceWithPrimaryKey do
            rpc_action :update_resource, :update, identities: [:_primary_key]
          end
        end

        resources do
          resource TestResourceWithPrimaryKey
        end
      end

      result = AshTypescript.VerifierChecker.check_all_verifiers([TestDomainWithPrimaryKey])

      assert result == :ok
    end

    test "allows existing named identity" do
      defmodule TestResourceWithNamedIdentity do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceWithNamedIdentity"
        end

        attributes do
          uuid_primary_key :id
          attribute :email, :string, public?: true
        end

        identities do
          identity :email, [:email]
        end

        actions do
          defaults [:read, :destroy, create: [:email], update: [:email]]
        end
      end

      defmodule TestDomainWithNamedIdentity do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceWithNamedIdentity do
            rpc_action :update_resource, :update, identities: [:email]
          end
        end

        resources do
          resource TestResourceWithNamedIdentity
        end
      end

      result = AshTypescript.VerifierChecker.check_all_verifiers([TestDomainWithNamedIdentity])

      assert result == :ok
    end

    test "allows mix of :_primary_key and named identities" do
      defmodule TestResourceWithMixedIdentities do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceWithMixedIdentities"
        end

        attributes do
          uuid_primary_key :id
          attribute :email, :string, public?: true
          attribute :username, :string, public?: true
        end

        identities do
          identity :email, [:email]
          identity :username, [:username]
        end

        actions do
          defaults [:read, :destroy, create: [:email, :username], update: [:email, :username]]
        end
      end

      defmodule TestDomainWithMixedIdentities do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceWithMixedIdentities do
            rpc_action :update_resource, :update, identities: [:_primary_key, :email, :username]
          end
        end

        resources do
          resource TestResourceWithMixedIdentities
        end
      end

      result = AshTypescript.VerifierChecker.check_all_verifiers([TestDomainWithMixedIdentities])

      assert result == :ok
    end

    test "allows default identities (not explicitly specified)" do
      defmodule TestResourceWithDefaultIdentities do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceWithDefaultIdentities"
        end

        attributes do
          uuid_primary_key :id
          attribute :name, :string, public?: true
        end

        actions do
          defaults [:read, :destroy, create: [:name], update: [:name]]
        end
      end

      defmodule TestDomainWithDefaultIdentities do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceWithDefaultIdentities do
            # No identities specified - defaults to [:_primary_key]
            rpc_action :update_resource, :update
          end
        end

        resources do
          resource TestResourceWithDefaultIdentities
        end
      end

      result =
        AshTypescript.VerifierChecker.check_all_verifiers([TestDomainWithDefaultIdentities])

      assert result == :ok
    end

    test "allows empty identities list for actor-scoped actions" do
      defmodule TestResourceWithEmptyIdentities do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceWithEmptyIdentities"
        end

        attributes do
          uuid_primary_key :id
          attribute :name, :string, public?: true
        end

        actions do
          defaults [:read, :destroy, create: [:name], update: [:name]]
        end
      end

      defmodule TestDomainWithEmptyIdentities do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceWithEmptyIdentities do
            # Empty identities list for actor-scoped actions
            rpc_action :update_resource, :update, identities: []
          end
        end

        resources do
          resource TestResourceWithEmptyIdentities
        end
      end

      result = AshTypescript.VerifierChecker.check_all_verifiers([TestDomainWithEmptyIdentities])

      assert result == :ok
    end
  end

  describe "identity validation - action type scoping" do
    test "skips validation for read actions" do
      defmodule TestResourceWithReadAction do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceWithReadAction"
        end

        attributes do
          uuid_primary_key :id
          attribute :name, :string, public?: true
        end

        actions do
          defaults [:read, :destroy, create: [:name], update: [:name]]
        end
      end

      defmodule TestDomainWithReadAction do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceWithReadAction do
            # Read actions don't use identities - this should be ignored
            rpc_action :list_resources, :read
          end
        end

        resources do
          resource TestResourceWithReadAction
        end
      end

      result = AshTypescript.VerifierChecker.check_all_verifiers([TestDomainWithReadAction])

      assert result == :ok
    end

    test "skips validation for create actions" do
      defmodule TestResourceWithCreateAction do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceWithCreateAction"
        end

        attributes do
          uuid_primary_key :id
          attribute :name, :string, public?: true
        end

        actions do
          defaults [:read, :destroy, create: [:name], update: [:name]]
        end
      end

      defmodule TestDomainWithCreateAction do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceWithCreateAction do
            # Create actions don't use identities - this should be ignored
            rpc_action :create_resource, :create
          end
        end

        resources do
          resource TestResourceWithCreateAction
        end
      end

      result = AshTypescript.VerifierChecker.check_all_verifiers([TestDomainWithCreateAction])

      assert result == :ok
    end

    test "validates identities for destroy actions" do
      defmodule TestResourceWithDestroyAction do
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypescript.Resource]

        typescript do
          type_name "TestResourceWithDestroyAction"
        end

        attributes do
          uuid_primary_key :id
          attribute :name, :string, public?: true
        end

        actions do
          defaults [:read, :destroy, create: [:name], update: [:name]]
        end
      end

      defmodule TestDomainWithDestroyAction do
        use Ash.Domain,
          otp_app: :ash_typescript,
          extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TestResourceWithDestroyAction do
            rpc_action :destroy_resource, :destroy, identities: [:non_existent]
          end
        end

        resources do
          resource TestResourceWithDestroyAction
        end
      end

      result =
        AshTypescript.VerifierChecker.check_all_verifiers([TestDomainWithDestroyAction])

      assert {:error, error_message} = result
      assert error_message =~ ~r/Identity not found on resource/
      assert error_message =~ ~r/non_existent/
    end
  end
end
