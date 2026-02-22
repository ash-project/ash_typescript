# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.RpcIdentitiesTest do
  @moduledoc """
  Tests for identity-based record lookups in update/destroy actions.
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

  describe "identity-based update actions" do
    setup do
      conn = TestHelpers.build_rpc_conn()

      %{"success" => true, "data" => user} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_user",
          "input" => %{
            "name" => "Identity Test User",
            "email" => "identity-test-#{:rand.uniform(100_000)}@example.com"
          },
          "fields" => ["id", "name", "email"]
        })

      %{conn: conn, user: user}
    end

    test "update_user uses primary key identity directly", %{conn: conn, user: user} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "update_user",
          "identity" => user["id"],
          "input" => %{"name" => "Updated via PK"},
          "fields" => ["id", "name"]
        })

      assert %{"success" => true, "data" => data} = result
      assert data["name"] == "Updated via PK"
      assert data["id"] == user["id"]
    end

    test "update_user_by_identity can use primary key", %{conn: conn, user: user} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "update_user_by_identity",
          "identity" => user["id"],
          "input" => %{"name" => "Updated via PK in multi-identity"},
          "fields" => ["id", "name"]
        })

      assert %{"success" => true, "data" => data} = result
      assert data["name"] == "Updated via PK in multi-identity"
      assert data["id"] == user["id"]
    end

    test "update_user_by_identity can use email identity", %{conn: conn, user: user} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "update_user_by_identity",
          "identity" => %{"email" => user["email"]},
          "input" => %{"name" => "Updated via Email"},
          "fields" => ["id", "name", "email"]
        })

      assert %{"success" => true, "data" => data} = result
      assert data["name"] == "Updated via Email"
      assert data["email"] == user["email"]
    end

    test "update_user_by_email only accepts email identity", %{conn: conn, user: user} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "update_user_by_email",
          "identity" => %{"email" => user["email"]},
          "input" => %{"name" => "Updated by Email Only"},
          "fields" => ["id", "name", "email"]
        })

      assert %{"success" => true, "data" => data} = result
      assert data["name"] == "Updated by Email Only"
      assert data["email"] == user["email"]
    end

    test "update_user_by_email with non-matching email returns not found", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "update_user_by_email",
          "identity" => %{"email" => "nonexistent@example.com"},
          "input" => %{"name" => "Should Fail"},
          "fields" => ["id", "name"]
        })

      assert %{"success" => false} = result
    end

    test "update_user_by_email with wrong identity field name returns invalid_identity error", %{
      conn: conn
    } do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "update_user_by_email",
          "identity" => %{"emai" => "test@example.com"},
          "input" => %{"name" => "Should Fail"},
          "fields" => ["id", "name"]
        })

      assert %{"success" => false, "errors" => [error]} = result
      assert error["type"] == "invalid_identity"
      assert error["shortMessage"] == "Invalid identity"
    end

    test "update_user_by_email with extra identity fields still matches valid identity", %{
      conn: conn,
      user: user
    } do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "update_user_by_email",
          "identity" => %{"email" => user["email"], "extraField" => "value"},
          "input" => %{"name" => "Updated with extra fields"},
          "fields" => ["id", "name"]
        })

      assert %{"success" => true, "data" => data} = result
      assert data["name"] == "Updated with extra fields"
    end

    test "update_user_by_identity with completely wrong fields returns invalid_identity error", %{
      conn: conn
    } do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "update_user_by_identity",
          "identity" => %{"wrongField" => "value"},
          "input" => %{"name" => "Should Fail"},
          "fields" => ["id", "name"]
        })

      assert %{"success" => false, "errors" => [error]} = result
      assert error["type"] == "invalid_identity"
      assert is_map(error["details"])
    end

    test "invalid_identity error message uses client-facing field names", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "update_user_by_email",
          "identity" => %{"emai" => "test@example.com"},
          "input" => %{"name" => "Should Fail"},
          "fields" => ["id", "name"]
        })

      assert %{"success" => false, "errors" => [error]} = result
      assert error["type"] == "invalid_identity"

      assert error["vars"]["expectedKeys"] == "email"
      assert error["vars"]["providedKeys"] == "emai"

      assert "email" in error["details"]["expectedKeys"]
      assert "emai" in error["details"]["providedKeys"]
    end

    test "update action without identity when identity is required returns missing_identity error",
         %{
           conn: conn
         } do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "update_user",
          "input" => %{"name" => "Should Fail Without Identity"},
          "fields" => ["id", "name"]
        })

      assert %{"success" => false, "errors" => [error]} = result
      assert error["type"] == "missing_identity"
      assert error["shortMessage"] == "Missing identity"
      assert error["message"] =~ "Identity is required"
      assert error["message"] =~ "id"

      assert is_map(error["details"])
      assert is_list(error["details"]["expectedKeys"])
    end

    test "update action with empty map identity returns missing_identity error", %{conn: conn} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "update_user_by_email",
          "identity" => %{},
          "input" => %{"name" => "Should Fail"},
          "fields" => ["id", "name"]
        })

      assert %{"success" => false, "errors" => [error]} = result
      assert error["type"] in ["missing_identity", "invalid_identity"]
    end

    test "destroy action without identity when identity is required returns missing_identity error",
         %{
           conn: conn
         } do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "destroy_user",
          "fields" => ["id"]
        })

      assert %{"success" => false, "errors" => [error]} = result
      assert error["type"] == "missing_identity"
      assert error["shortMessage"] == "Missing identity"
    end

    test "invalid_identity error applies field_names mapping for client-facing names", %{
      conn: conn,
      user: user
    } do
      %{"success" => true, "data" => _subscription} =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "create_subscription",
          "input" => %{
            "userId" => user["id"],
            "plan" => "premium",
            "isActive" => true,
            "isTrial" => false
          },
          "fields" => ["id", "userId", "isActive"]
        })

      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "update_subscription_by_user_status",
          "identity" => %{
            "userId" => user["id"],
            "isActiv" => true
          },
          "input" => %{"plan" => "basic"},
          "fields" => ["id", "plan"]
        })

      assert %{"success" => false, "errors" => [error]} = result
      assert error["type"] == "invalid_identity"

      assert error["vars"]["expectedKeys"] == "userId, isActive"
      assert error["vars"]["providedKeys"] == "userId, isActiv"

      assert "userId" in error["details"]["expectedKeys"]
      assert "isActive" in error["details"]["expectedKeys"]
      refute "isActive?" in error["details"]["expectedKeys"]
      refute "is_active?" in error["details"]["expectedKeys"]
    end
  end

  describe "actor-scoped actions (no identity)" do
    setup do
      {:ok, actor} =
        Ash.create(
          AshTypescript.Test.User,
          %{
            name: "Actor User",
            email: "actor-#{:rand.uniform(100_000)}@example.com"
          },
          action: :create
        )

      conn =
        TestHelpers.build_rpc_conn()
        |> Plug.Conn.put_private(:ash, %{actor: actor})
        |> Ash.PlugHelpers.set_actor(actor)

      %{conn: conn, actor: actor}
    end

    test "update_me works without identity when actor is set", %{conn: conn, actor: actor} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "update_me",
          "input" => %{"name" => "Updated My Name"},
          "fields" => ["id", "name"]
        })

      assert %{"success" => true, "data" => data} = result
      assert data["name"] == "Updated My Name"
      assert data["id"] == actor.id
    end

    test "destroy_me works without identity when actor is set", %{conn: conn, actor: actor} do
      result =
        Rpc.run_action(:ash_typescript, conn, %{
          "action" => "destroy_me",
          "fields" => ["id"]
        })

      assert %{"success" => true, "data" => data} = result
      assert data["id"] == actor.id

      assert {:error, _} = Ash.get(AshTypescript.Test.User, actor.id, action: :get_by_id)
    end
  end

  describe "TypeScript codegen generates correct types" do
    test "update_user has identity: UUID", %{generated: generated} do
      assert generated =~ ~r/function updateUser.*identity: UUID;/s
    end

    test "update_user_by_identity has identity union type", %{generated: generated} do
      assert generated =~
               ~r/function updateUserByIdentity.*identity: UUID \| \{ email: string \};/s
    end

    test "update_user_by_email has identity: { email: string }", %{generated: generated} do
      assert generated =~ ~r/function updateUserByEmail.*identity: \{ email: string \};/s
    end

    test "update_me has no identity field", %{generated: generated} do
      if match = Regex.run(~r/function updateMe[^{]+\{([^}]+)\}/, generated) do
        config_content = Enum.at(match, 1)
        refute config_content =~ "identity"
      end
    end
  end
end
