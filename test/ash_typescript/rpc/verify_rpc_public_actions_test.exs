# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# Resources for relationship read action tests — must be defined at top level
# so Spark DSL fully compiles them (defmodule inside test doesn't work for
# Ash.Resource.Info.public_relationships/1).

defmodule AshTypescript.Rpc.VerifyRpcPublicActionsTest.RelDestNonPublicRead do
  @moduledoc false
  use Ash.Resource, domain: nil, extensions: [AshTypescript.Resource]

  typescript do
    type_name "RelDestNonPublicRead"
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end

  actions do
    read :read do
      primary? true
      public? false
    end
  end
end

defmodule AshTypescript.Rpc.VerifyRpcPublicActionsTest.RelSourceNonPublicDest do
  @moduledoc false
  use Ash.Resource, domain: nil, extensions: [AshTypescript.Resource]

  typescript do
    type_name "RelSourceNonPublicDest"
  end

  attributes do
    uuid_primary_key :id
    attribute :dest_id, :uuid, public?: true
  end

  relationships do
    belongs_to :dest, AshTypescript.Rpc.VerifyRpcPublicActionsTest.RelDestNonPublicRead,
      public?: true
  end

  actions do
    defaults [:read]
  end
end

defmodule AshTypescript.Rpc.VerifyRpcPublicActionsTest.RelDestPublicRead do
  @moduledoc false
  use Ash.Resource, domain: nil, extensions: [AshTypescript.Resource]

  typescript do
    type_name "RelDestPublicRead"
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end

  actions do
    read :read do
      primary? true
      public? true
    end
  end
end

defmodule AshTypescript.Rpc.VerifyRpcPublicActionsTest.RelSourcePublicDest do
  @moduledoc false
  use Ash.Resource, domain: nil, extensions: [AshTypescript.Resource]

  typescript do
    type_name "RelSourcePublicDest"
  end

  attributes do
    uuid_primary_key :id
    attribute :dest_id, :uuid, public?: true
  end

  relationships do
    belongs_to :dest, AshTypescript.Rpc.VerifyRpcPublicActionsTest.RelDestPublicRead,
      public?: true
  end

  actions do
    defaults [:read]
  end
end

defmodule AshTypescript.Rpc.VerifyRpcPublicActionsTest.PlainDest do
  @moduledoc false
  use Ash.Resource, domain: nil

  attributes do
    uuid_primary_key :id
  end

  actions do
    defaults [:read]
  end
end

defmodule AshTypescript.Rpc.VerifyRpcPublicActionsTest.RelSourcePlainDest do
  @moduledoc false
  use Ash.Resource, domain: nil, extensions: [AshTypescript.Resource]

  typescript do
    type_name "RelSourcePlainDest"
  end

  attributes do
    uuid_primary_key :id
    attribute :dest_id, :uuid, public?: true
  end

  relationships do
    belongs_to :dest, AshTypescript.Rpc.VerifyRpcPublicActionsTest.PlainDest, public?: true
  end

  actions do
    defaults [:read]
  end
end

defmodule AshTypescript.Rpc.VerifyRpcPublicActionsTest do
  @moduledoc """
  Integration tests for the `not public?` checks in `AshTypescript.Manifest.Verifiers.VerifyRpc`.

  Each test defines an inline domain and invokes `check_all_verifiers/1`, which
  routes through the manifest-based verifier. We assert against the public error
  message rather than the implementation details of any specific helper.
  """
  use ExUnit.Case, async: true

  @moduletag :generates_warnings

  describe "rpc actions reject non-public destination actions" do
    test "returns error when rpc_action references a non-`public?` action" do
      defmodule NonPublicActionResource do
        @moduledoc false
        use Ash.Resource, domain: nil, extensions: [AshTypescript.Resource]

        typescript do
          type_name "NonPublicActionResource"
        end

        attributes do
          uuid_primary_key :id
          attribute :name, :string, public?: true
        end

        actions do
          defaults [:read]

          read :private_read do
            public? false
          end
        end
      end

      defmodule NonPublicActionDomain do
        use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource NonPublicActionResource do
            rpc_action :list_private, :private_read
          end
        end

        resources do
          resource NonPublicActionResource
        end
      end

      assert {:error, message} =
               AshTypescript.Manifest.verify_for_domains([NonPublicActionDomain])

      assert message =~ "not `public?`"
      assert message =~ "private_read"
      assert message =~ "list_private"
    end

    test "passes when rpc_action references a `public?` action" do
      defmodule PublicActionResource do
        @moduledoc false
        use Ash.Resource, domain: nil, extensions: [AshTypescript.Resource]

        typescript do
          type_name "PublicActionResource"
        end

        attributes do
          uuid_primary_key :id
          attribute :name, :string, public?: true
        end

        actions do
          read :public_read do
            public? true
          end
        end
      end

      defmodule PublicActionDomain do
        use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource PublicActionResource do
            rpc_action :list_public, :public_read
          end
        end

        resources do
          resource PublicActionResource
        end
      end

      assert :ok = AshTypescript.Manifest.verify_for_domains([PublicActionDomain])
    end

    test "returns error when read_action override is not `public?`" do
      defmodule ReadActionNotPublicResource do
        @moduledoc false
        use Ash.Resource, domain: nil, extensions: [AshTypescript.Resource]

        typescript do
          type_name "ReadActionNotPublicResource"
        end

        attributes do
          uuid_primary_key :id
          attribute :name, :string, public?: true
        end

        actions do
          defaults [:read]

          read :private_lookup do
            public? false
          end

          update :update_thing do
            public? true
          end
        end
      end

      defmodule ReadActionNotPublicDomain do
        use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource ReadActionNotPublicResource do
            rpc_action :update_thing, :update_thing, read_action: :private_lookup
          end
        end

        resources do
          resource ReadActionNotPublicResource
        end
      end

      assert {:error, message} =
               AshTypescript.Manifest.verify_for_domains([ReadActionNotPublicDomain])

      assert message =~ "not `public?`"
      assert message =~ "private_lookup"
      assert message =~ "read_action"
    end
  end

  describe "relationship destination read actions must be public" do
    test "returns error when relationship destination has non-public read action" do
      defmodule RelSourceNonPublicDestDomain do
        use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource AshTypescript.Rpc.VerifyRpcPublicActionsTest.RelSourceNonPublicDest do
            rpc_action :list_src, :read
          end
        end

        resources do
          resource AshTypescript.Rpc.VerifyRpcPublicActionsTest.RelSourceNonPublicDest
          resource AshTypescript.Rpc.VerifyRpcPublicActionsTest.RelDestNonPublicRead
        end
      end

      assert {:error, message} =
               AshTypescript.Manifest.verify_for_domains([RelSourceNonPublicDestDomain])

      assert message =~ "not `public?`"
      assert message =~ "dest"
      assert message =~ "RelDestNonPublicRead"
    end

    test "passes when relationship destination has public read action" do
      defmodule RelSourcePublicDestDomain do
        use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource AshTypescript.Rpc.VerifyRpcPublicActionsTest.RelSourcePublicDest do
            rpc_action :list_src, :read
          end
        end

        resources do
          resource AshTypescript.Rpc.VerifyRpcPublicActionsTest.RelSourcePublicDest
          resource AshTypescript.Rpc.VerifyRpcPublicActionsTest.RelDestPublicRead
        end
      end

      assert :ok =
               AshTypescript.Manifest.verify_for_domains([RelSourcePublicDestDomain])
    end

    test "skips relationships to non-typescript destinations" do
      defmodule RelSourcePlainDestDomain do
        use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource AshTypescript.Rpc.VerifyRpcPublicActionsTest.RelSourcePlainDest do
            rpc_action :list_src, :read
          end
        end

        resources do
          resource AshTypescript.Rpc.VerifyRpcPublicActionsTest.RelSourcePlainDest
          resource AshTypescript.Rpc.VerifyRpcPublicActionsTest.PlainDest
        end
      end

      assert :ok = AshTypescript.Manifest.verify_for_domains([RelSourcePlainDestDomain])
    end
  end

  describe "typed queries reject non-public actions" do
    test "returns error when typed query references a non-public action" do
      defmodule TypedQueryNonPublicResource do
        @moduledoc false
        use Ash.Resource, domain: nil, extensions: [AshTypescript.Resource]

        typescript do
          type_name "TypedQueryNonPublicResource"
        end

        attributes do
          uuid_primary_key :id
          attribute :name, :string, public?: true
        end

        actions do
          read :private_read do
            public? false
          end
        end
      end

      defmodule TypedQueryNonPublicDomain do
        use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TypedQueryNonPublicResource do
            typed_query :my_query, :private_read do
              ts_result_type_name "MyQueryResult"
              ts_fields_const_name "myQuery"
              fields([:id, :name])
            end
          end
        end

        resources do
          resource TypedQueryNonPublicResource
        end
      end

      assert {:error, message} =
               AshTypescript.Manifest.verify_for_domains([TypedQueryNonPublicDomain])

      assert message =~ "not `public?`"
      assert message =~ "private_read"
      assert message =~ "my_query"
    end

    test "passes when typed query references a public action" do
      defmodule TypedQueryPublicResource do
        @moduledoc false
        use Ash.Resource, domain: nil, extensions: [AshTypescript.Resource]

        typescript do
          type_name "TypedQueryPublicResource"
        end

        attributes do
          uuid_primary_key :id
          attribute :name, :string, public?: true
        end

        actions do
          read :public_read do
            public? true
          end
        end
      end

      defmodule TypedQueryPublicDomain do
        use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource TypedQueryPublicResource do
            typed_query :my_query, :public_read do
              ts_result_type_name "MyQueryResult"
              ts_fields_const_name "myQuery"
              fields([:id, :name])
            end
          end
        end

        resources do
          resource TypedQueryPublicResource
        end
      end

      assert :ok = AshTypescript.Manifest.verify_for_domains([TypedQueryPublicDomain])
    end
  end
end
