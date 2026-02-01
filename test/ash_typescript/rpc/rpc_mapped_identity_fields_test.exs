# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.RpcMappedIdentityFieldsTest do
  @moduledoc """
  Tests for identity field name mapping in RPC actions.

  This tests that identity fields with `field_names` mappings (for invalid
  TypeScript characters like `?`) are correctly:
  - Generated in TypeScript with the mapped names
  - Parsed from client input using reverse mapping
  """
  use ExUnit.Case, async: false

  alias AshTypescript.Rpc
  alias AshTypescript.Test.TestHelpers

  setup do
    Application.put_env(:ash_typescript, :enable_namespace_files, false)
    :ok
  end

  setup_all do
    # Generate the TypeScript code programmatically
    {:ok, generated_content} =
      AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

    {:ok, generated: generated_content}
  end

  describe "identity with mapped field names - runtime" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      # Create a test subscription using Ash directly to avoid field name issues
      user_id = Ash.UUID.generate()

      subscription =
        AshTypescript.Test.Subscription
        |> Ash.Changeset.for_create(:create, %{
          user_id: user_id,
          plan: "premium",
          is_active?: true,
          is_trial?: false
        })
        |> Ash.create!()

      %{conn: conn, subscription: subscription, user_id: user_id}
    end

    test "update by identity with mapped field names", %{
      conn: conn,
      subscription: subscription,
      user_id: user_id
    } do
      # The identity :by_user_and_status uses [:user_id, :is_active?]
      # is_active? is mapped to isActive in TypeScript
      # Client sends: { userId: "...", isActive: true }
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "update_subscription_by_user_status",
          "identity" => %{
            "userId" => user_id,
            "isActive" => true
          },
          "input" => %{"plan" => "enterprise"},
          "fields" => ["id", "plan"]
        })

      assert %{"success" => true, "data" => data} = result
      assert data["id"] == subscription.id
      assert data["plan"] == "enterprise"
    end

    test "destroy by identity with mapped field names", %{conn: conn, user_id: user_id} do
      # Create another subscription to destroy using Ash directly
      sub_to_destroy =
        AshTypescript.Test.Subscription
        |> Ash.Changeset.for_create(:create, %{
          user_id: user_id,
          plan: "basic",
          is_active?: false,
          is_trial?: true
        })
        |> Ash.create!()

      # Destroy using identity with mapped field name
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "destroy_subscription_by_user_status",
          "identity" => %{
            "userId" => user_id,
            "isActive" => false
          }
        })

      assert %{"success" => true} = result

      # Verify subscription was destroyed
      assert {:error, _} =
               Ash.get(AshTypescript.Test.Subscription, sub_to_destroy.id, action: :get_by_id)
    end
  end

  describe "TypeScript codegen generates correct identity types" do
    test "update_subscription_by_user_status has identity with mapped field names", %{
      generated: generated
    } do
      # Identity should use the TypeScript field names (userId, isActive)
      # not the Elixir names (user_id, is_active?)
      assert generated =~
               ~r/function updateSubscriptionByUserStatus.*identity: \{ userId: UUID; isActive: boolean \};/s
    end

    test "destroy_subscription_by_user_status has identity with mapped field names", %{
      generated: generated
    } do
      assert generated =~
               ~r/function destroySubscriptionByUserStatus.*identity: \{ userId: UUID; isActive: boolean \};/s
    end
  end
end
