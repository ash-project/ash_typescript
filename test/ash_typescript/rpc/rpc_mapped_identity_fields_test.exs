# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.RpcMappedIdentityFieldsTest do
  @moduledoc """
  Tests for identity field name mapping in RPC actions, ensuring `field_names`
  mappings (e.g. `is_active?` -> `isActive`) are applied in both codegen and runtime.
  """
  use ExUnit.Case, async: false

  alias AshTypescript.Rpc
  alias AshTypescript.Test.TestHelpers

  setup do
    Application.put_env(:ash_typescript, :enable_namespace_files, false)
    :ok
  end

  setup_all do
    {:ok, generated_content} =
      AshTypescript.Test.CodegenTestHelper.generate_all_content()

    {:ok, generated: generated_content}
  end

  describe "identity with mapped field names - runtime" do
    setup do
      conn = TestHelpers.build_rpc_conn()
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
      sub_to_destroy =
        AshTypescript.Test.Subscription
        |> Ash.Changeset.for_create(:create, %{
          user_id: user_id,
          plan: "basic",
          is_active?: false,
          is_trial?: true
        })
        |> Ash.create!()

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "destroy_subscription_by_user_status",
          "identity" => %{
            "userId" => user_id,
            "isActive" => false
          }
        })

      assert %{"success" => true} = result

      assert {:error, _} =
               Ash.get(AshTypescript.Test.Subscription, sub_to_destroy.id, action: :get_by_id)
    end
  end

  describe "TypeScript codegen generates correct identity types" do
    test "update_subscription_by_user_status has identity with mapped field names", %{
      generated: generated
    } do
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
