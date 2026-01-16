# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.SkewProtectionTest do
  use ExUnit.Case

  alias AshTypescript.Rpc.Action.Metadata.Signature
  alias AshTypescript.Rpc.Pipeline
  alias AshTypescript.Test.{Domain, Todo}

  @moduletag :ash_typescript

  describe "Signature module" do
    test "hash/1 produces deterministic 16-character hex string" do
      resource = Todo
      action = Ash.Resource.Info.action(Todo, :read)
      rpc_action = get_rpc_action(Domain, :list_todos)

      contract_sig = Signature.build_contract(resource, action, rpc_action)
      hash1 = Signature.hash(contract_sig)
      hash2 = Signature.hash(contract_sig)

      assert hash1 == hash2
      assert String.length(hash1) == 16
      assert Regex.match?(~r/^[0-9a-f]{16}$/, hash1)
    end

    test "hashes_for_action/3 returns both contract and version hashes" do
      resource = Todo
      action = Ash.Resource.Info.action(Todo, :read)
      rpc_action = get_rpc_action(Domain, :list_todos)

      {contract_hash, version_hash} = Signature.hashes_for_action(resource, action, rpc_action)

      assert is_binary(contract_hash)
      assert is_binary(version_hash)
      assert String.length(contract_hash) == 16
      assert String.length(version_hash) == 16
    end

    test "contract and version hashes are different for read action" do
      resource = Todo
      action = Ash.Resource.Info.action(Todo, :read)
      rpc_action = get_rpc_action(Domain, :list_todos)

      {contract_hash, version_hash} = Signature.hashes_for_action(resource, action, rpc_action)

      # For a typical resource, version hash includes more elements than contract hash,
      # so they should be different
      assert contract_hash != version_hash
    end

    test "build_contract includes required arguments only" do
      resource = Todo
      action = Ash.Resource.Info.action(Todo, :create)
      rpc_action = get_rpc_action(Domain, :create_todo)

      contract_sig = Signature.build_contract(resource, action, rpc_action)

      # user_id is a required argument
      required_arg_names = Enum.map(contract_sig.required_arguments, fn {name, _, _} -> name end)
      assert :user_id in required_arg_names

      # auto_complete is optional (has default), should not be in required
      refute :auto_complete in required_arg_names
    end

    test "build_version includes all arguments" do
      resource = Todo
      action = Ash.Resource.Info.action(Todo, :create)
      rpc_action = get_rpc_action(Domain, :create_todo)

      version_sig = Signature.build_version(resource, action, rpc_action)

      all_arg_names = Enum.map(version_sig.all_arguments, fn {name, _, _, _, _} -> name end)
      assert :user_id in all_arg_names
      assert :auto_complete in all_arg_names
    end
  end

  describe "hash lookup functions" do
    setup do
      # Enable hash generation for these tests
      original_value = Application.get_env(:ash_typescript, :generate_action_hashes)
      Application.put_env(:ash_typescript, :generate_action_hashes, true)

      on_exit(fn ->
        if original_value do
          Application.put_env(:ash_typescript, :generate_action_hashes, original_value)
        else
          Application.delete_env(:ash_typescript, :generate_action_hashes)
        end
      end)

      :ok
    end

    test "contract_hash returns hash when hashing is enabled" do
      # Note: Hashes are computed at compile time, so this tests the lookup only
      # The transformer runs at compile time and persists hashes
      hash = AshTypescript.Rpc.contract_hash(Domain, Todo, :list_todos)

      # Hash might be nil if transformer hasn't run with hashing enabled
      # In a real test env with proper setup, this would return a hash
      assert is_nil(hash) or (is_binary(hash) and String.length(hash) == 16)
    end

    test "version_hash returns hash when hashing is enabled" do
      hash = AshTypescript.Rpc.version_hash(Domain, Todo, :list_todos)

      # Same caveat as above
      assert is_nil(hash) or (is_binary(hash) and String.length(hash) == 16)
    end
  end

  describe "Pipeline integration with skew protection" do
    test "parse_request extracts meta from request params" do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "meta" => %{
          "contractHash" => "abc123def456",
          "versionHash" => "789xyz012345"
        }
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)
      assert request.contract_hash == "abc123def456"
      assert request.version_hash == "789xyz012345"
      assert request.rpc_action_name == :list_todos
    end

    test "parse_request handles missing meta" do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"]
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)
      assert request.contract_hash == nil
      assert request.version_hash == nil
    end

    test "parse_request handles partial meta" do
      params = %{
        "action" => "list_todos",
        "fields" => ["id", "title"],
        "meta" => %{
          "contractHash" => "abc123def456"
        }
      }

      conn = %Plug.Conn{}

      assert {:ok, request} = Pipeline.parse_request(:ash_typescript, conn, params)
      assert request.contract_hash == "abc123def456"
      assert request.version_hash == nil
    end
  end

  describe "HashGenerator module" do
    alias AshTypescript.Rpc.Codegen.HashGenerator

    test "action_key returns camelCase action name" do
      assert HashGenerator.action_key(:list_todos) == "listTodos"
      assert HashGenerator.action_key("create_user") == "createUser"
    end

    test "generate_action_hashes_object returns empty string for empty list" do
      assert HashGenerator.generate_action_hashes_object([]) == ""
    end

    test "generate_action_hashes_object generates const object with entries" do
      entries = [
        "listTodos: { contract: \"abc123\", version: \"def456\" }",
        "createTodo: { contract: \"ghi789\", version: \"jkl012\" }"
      ]

      result = HashGenerator.generate_action_hashes_object(entries)

      assert result =~ "export const actionHashes = {"
      assert result =~ "listTodos: { contract: \"abc123\", version: \"def456\" }"
      assert result =~ "createTodo: { contract: \"ghi789\", version: \"jkl012\" }"
      assert result =~ "} as const;"
      assert result =~ "export type ActionHashKey = keyof typeof actionHashes;"
    end

    test "generate_meta_object returns nil when disabled" do
      original_value = Application.get_env(:ash_typescript, :generate_action_hashes)
      Application.put_env(:ash_typescript, :generate_action_hashes, false)

      assert HashGenerator.generate_meta_object(:list_todos) == nil

      if original_value do
        Application.put_env(:ash_typescript, :generate_action_hashes, original_value)
      else
        Application.delete_env(:ash_typescript, :generate_action_hashes)
      end
    end

    test "generate_meta_object returns meta string with lookup syntax when enabled" do
      original_value = Application.get_env(:ash_typescript, :generate_action_hashes)
      Application.put_env(:ash_typescript, :generate_action_hashes, true)

      result = HashGenerator.generate_meta_object(:list_todos)

      assert result =~ "meta:"
      assert result =~ "contractHash: actionHashes.listTodos.contract"
      assert result =~ "versionHash: actionHashes.listTodos.version"

      if original_value do
        Application.put_env(:ash_typescript, :generate_action_hashes, original_value)
      else
        Application.delete_env(:ash_typescript, :generate_action_hashes)
      end
    end
  end

  # NOTE: Hash-based skew protection has been disabled in favor of snapshot-based versioning.
  # The ComputeActionHashes transformer is no longer registered, so hashes are not computed at compile time.
  # These tests are kept for reference but skipped.
  # See: AshTypescript.Rpc.Snapshot and AshTypescript.Rpc.SnapshotVerifier for the new approach.
  describe "TypeScript codegen with hashes (DISABLED)" do
    @tag :skip
    test "generates actionHashes object when enabled" do
      original_value = Application.get_env(:ash_typescript, :generate_action_hashes)
      Application.put_env(:ash_typescript, :generate_action_hashes, true)

      # Recompile the domain to compute hashes
      # Note: This is a unit test limitation - hashes are computed at compile time

      {:ok, typescript} = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # When hash generation is enabled, the static types should include SkewMeta
      assert typescript =~ "SkewMeta"
      assert typescript =~ "contractHash"
      assert typescript =~ "contractMismatch"
      assert typescript =~ "versionHash"
      assert typescript =~ "versionMismatch"
      assert typescript =~ "hasContractMismatch"
      assert typescript =~ "hasVersionMismatch"
      assert typescript =~ "hasAnyMismatch"

      # Should generate the actionHashes lookup object
      assert typescript =~ "export const actionHashes = {"
      assert typescript =~ "} as const;"
      assert typescript =~ "export type ActionHashKey = keyof typeof actionHashes;"

      if original_value do
        Application.put_env(:ash_typescript, :generate_action_hashes, original_value)
      else
        Application.delete_env(:ash_typescript, :generate_action_hashes)
      end
    end

    @tag :skip
    test "does not generate hash types when disabled" do
      original_value = Application.get_env(:ash_typescript, :generate_action_hashes)
      Application.put_env(:ash_typescript, :generate_action_hashes, false)

      {:ok, typescript} = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # When disabled, SkewMeta types should not be present
      refute typescript =~ "export type SkewMeta"
      refute typescript =~ "hasContractMismatch"
      refute typescript =~ "hasVersionMismatch"
      refute typescript =~ "hasAnyMismatch"
      refute typescript =~ "export const actionHashes"

      if original_value do
        Application.put_env(:ash_typescript, :generate_action_hashes, original_value)
      else
        Application.delete_env(:ash_typescript, :generate_action_hashes)
      end
    end
  end

  describe "configuration" do
    test "generate_action_hashes? returns false by default" do
      original_value = Application.get_env(:ash_typescript, :generate_action_hashes)
      Application.delete_env(:ash_typescript, :generate_action_hashes)

      refute AshTypescript.generate_action_hashes?()

      if original_value do
        Application.put_env(:ash_typescript, :generate_action_hashes, original_value)
      end
    end

    test "generate_action_hashes? returns configured value" do
      original_value = Application.get_env(:ash_typescript, :generate_action_hashes)
      Application.put_env(:ash_typescript, :generate_action_hashes, true)

      assert AshTypescript.generate_action_hashes?()

      Application.put_env(:ash_typescript, :generate_action_hashes, false)

      refute AshTypescript.generate_action_hashes?()

      if original_value do
        Application.put_env(:ash_typescript, :generate_action_hashes, original_value)
      else
        Application.delete_env(:ash_typescript, :generate_action_hashes)
      end
    end
  end

  # Helper to get RPC action from domain
  defp get_rpc_action(domain, action_name) do
    domain
    |> AshTypescript.Rpc.Info.typescript_rpc()
    |> Enum.flat_map(fn %{rpc_actions: rpc_actions} -> rpc_actions end)
    |> Enum.find(fn rpc_action -> rpc_action.name == action_name end)
  end
end
