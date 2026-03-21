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
    belongs_to :dest, AshTypescript.Rpc.VerifyRpcPublicActionsTest.RelDestPublicRead, public?: true
  end

  actions do
    defaults [:read]
  end
end

defmodule AshTypescript.Rpc.VerifyRpcPublicActionsTest.PlainDestination do
  @moduledoc false
  use Ash.Resource, domain: nil

  attributes do
    uuid_primary_key :id
  end

  actions do
    read :read do
      public? false
    end
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
    attribute :plain_id, :uuid, public?: true
  end

  relationships do
    belongs_to :plain, AshTypescript.Rpc.VerifyRpcPublicActionsTest.PlainDestination, public?: true
  end

  actions do
    defaults [:read]
  end
end

defmodule AshTypescript.Rpc.VerifyRpcPublicActionsTest do
  use ExUnit.Case, async: true

  alias AshTypescript.Rpc.VerifyRpc

  describe "verify_rpc_actions/2 rejects non-public actions" do
    test "returns error when action is not public?" do
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

      rpc_action = %AshTypescript.Rpc.RpcAction{
        name: :list_private,
        action: :private_read
      }

      result = VerifyRpc.verify_rpc_actions(NonPublicActionResource, [rpc_action])

      assert {:error, %Spark.Error.DslError{message: message}} = result
      assert message =~ "not `public?`"
      assert message =~ "private_read"
      assert message =~ "list_private"
    end

    test "passes when action is public?" do
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

      rpc_action = %AshTypescript.Rpc.RpcAction{
        name: :list_public,
        action: :public_read,
        get?: false
      }

      assert :ok = VerifyRpc.verify_rpc_actions(PublicActionResource, [rpc_action])
    end

    test "returns error when read_action is not public?" do
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

      rpc_action = %AshTypescript.Rpc.RpcAction{
        name: :update_thing,
        action: :update_thing,
        read_action: :private_lookup
      }

      result = VerifyRpc.verify_rpc_actions(ReadActionNotPublicResource, [rpc_action])

      assert {:error, %Spark.Error.DslError{message: message}} = result
      assert message =~ "not `public?`"
      assert message =~ "private_lookup"
      assert message =~ "read_action"
    end
  end

  describe "verify_relationship_read_actions/1" do
    test "returns error when relationship destination has non-public read action" do
      result =
        VerifyRpc.verify_relationship_read_actions(
          AshTypescript.Rpc.VerifyRpcPublicActionsTest.RelSourceNonPublicDest
        )

      assert {:error, %Spark.Error.DslError{message: message}} = result
      assert message =~ "not `public?`"
      assert message =~ "dest"
      assert message =~ "RelDestNonPublicRead"
    end

    test "passes when relationship destination has public read action" do
      assert :ok =
               VerifyRpc.verify_relationship_read_actions(
                 AshTypescript.Rpc.VerifyRpcPublicActionsTest.RelSourcePublicDest
               )
    end

    test "skips non-typescript destination resources" do
      assert :ok =
               VerifyRpc.verify_relationship_read_actions(
                 AshTypescript.Rpc.VerifyRpcPublicActionsTest.RelSourcePlainDest
               )
    end
  end

  describe "verify_typed_queries/2 rejects non-public actions" do
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

      typed_query = %AshTypescript.Rpc.TypedQuery{
        name: :my_query,
        action: :private_read
      }

      result = VerifyRpc.verify_typed_queries(TypedQueryNonPublicResource, [typed_query])

      assert {:error, %Spark.Error.DslError{message: message}} = result
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

      typed_query = %AshTypescript.Rpc.TypedQuery{
        name: :my_query,
        action: :public_read
      }

      assert :ok = VerifyRpc.verify_typed_queries(TypedQueryPublicResource, [typed_query])
    end
  end
end
