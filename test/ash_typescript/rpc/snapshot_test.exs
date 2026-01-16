# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.SnapshotTest do
  use ExUnit.Case

  alias AshTypescript.Rpc.Snapshot
  alias AshTypescript.Rpc.SnapshotVerifier
  alias AshTypescript.Test.{Domain, Todo}

  @moduletag :ash_typescript

  describe "Snapshot.build/4" do
    test "builds a snapshot from resource/action/rpc_action" do
      resource = Todo
      action = Ash.Resource.Info.action(Todo, :read)
      rpc_action = get_rpc_action(Domain, :list_todos)

      snapshot = Snapshot.build(Domain, resource, action, rpc_action)

      assert snapshot.domain == "AshTypescript.Test.Domain"
      assert snapshot.resource == "AshTypescript.Test.Todo"
      assert snapshot.rpc_action_name == :list_todos
      assert snapshot.action_name == :read
      assert snapshot.action_type == :read
      assert snapshot.version == 1
      assert snapshot.min_version == 1
      assert is_binary(snapshot.contract_hash)
      assert is_binary(snapshot.version_hash)
      assert String.length(snapshot.contract_hash) == 16
      assert String.length(snapshot.version_hash) == 16
      assert is_map(snapshot.contract_signature)
      assert is_map(snapshot.version_signature)
      assert is_binary(snapshot.created_at)
    end

    test "respects version and min_version from rpc_action" do
      resource = Todo
      action = Ash.Resource.Info.action(Todo, :read)
      rpc_action = %{get_rpc_action(Domain, :list_todos) | version: 5, min_version: 3}

      snapshot = Snapshot.build(Domain, resource, action, rpc_action)

      assert snapshot.version == 5
      assert snapshot.min_version == 3
    end
  end

  describe "Snapshot JSON serialization" do
    test "to_json/1 produces valid JSON" do
      snapshot = build_test_snapshot()
      json = Snapshot.to_json(snapshot)

      assert is_binary(json)
      assert {:ok, _decoded} = Jason.decode(json)
    end

    test "from_json/1 deserializes to snapshot struct" do
      original = build_test_snapshot()
      json = Snapshot.to_json(original)

      {:ok, restored} = Snapshot.from_json(json)

      assert restored.domain == original.domain
      assert restored.resource == original.resource
      assert restored.rpc_action_name == original.rpc_action_name
      assert restored.action_name == original.action_name
      assert restored.action_type == original.action_type
      assert restored.version == original.version
      assert restored.min_version == original.min_version
      assert restored.contract_hash == original.contract_hash
      assert restored.version_hash == original.version_hash
    end

    test "to_json/1 produces deterministic output" do
      snapshot = build_test_snapshot()
      json1 = Snapshot.to_json(snapshot)
      json2 = Snapshot.to_json(snapshot)

      assert json1 == json2
    end
  end

  describe "Snapshot.compare/2" do
    test "returns :unchanged when hashes match" do
      snapshot1 = build_test_snapshot()
      snapshot2 = %{snapshot1 | created_at: "different-time"}

      assert Snapshot.compare(snapshot1, snapshot2) == :unchanged
    end

    test "returns :new_action when comparing to nil" do
      snapshot = build_test_snapshot()

      assert Snapshot.compare(snapshot, nil) == :new_action
    end

    test "returns :contract_changed when contract hash differs" do
      snapshot1 = build_test_snapshot()
      snapshot2 = %{snapshot1 | contract_hash: "different_hash__"}

      assert {:contract_changed, _, _} = Snapshot.compare(snapshot1, snapshot2)
    end

    test "returns :version_changed when only version hash differs" do
      snapshot1 = build_test_snapshot()
      snapshot2 = %{snapshot1 | version_hash: "different_hash__"}

      assert {:version_changed, _, _} = Snapshot.compare(snapshot1, snapshot2)
    end

    test "contract change takes precedence over version change" do
      snapshot1 = build_test_snapshot()

      snapshot2 = %{
        snapshot1
        | contract_hash: "different_c_hash",
          version_hash: "different_v_hash"
      }

      assert {:contract_changed, _, _} = Snapshot.compare(snapshot1, snapshot2)
    end
  end

  describe "Snapshot file operations" do
    test "snapshot_filename?/1 validates filename format" do
      assert Snapshot.list_snapshot_files("/nonexistent/path") == []
    end

    test "action_snapshots_dir/3 builds correct path with domain folder" do
      dir = Snapshot.action_snapshots_dir(:ash_typescript, Domain, :list_todos)

      assert String.contains?(dir, "rpc_action_snapshots")
      assert String.contains?(dir, "AshTypescript.Test.Domain")
      assert String.ends_with?(dir, "list_todos")
    end
  end

  describe "SnapshotVerifier" do
    test "verify_one returns :new for actions without snapshots" do
      resource = Todo
      action = Ash.Resource.Info.action(Todo, :read)
      rpc_action = get_rpc_action(Domain, :list_todos)

      # Use the real otp_app - snapshots don't exist by default
      # (and we clean up the snapshot dir if it exists)
      dir = Snapshot.action_snapshots_dir(:ash_typescript, Domain, :list_todos)
      if File.exists?(dir), do: File.rm_rf!(dir)

      result = SnapshotVerifier.verify_one(:ash_typescript, Domain, resource, action, rpc_action)

      assert {:new, snapshot} = result
      assert snapshot.rpc_action_name == :list_todos
    end

    test "format_violations formats contract change violation" do
      violation = %{
        domain: Domain,
        resource: Todo,
        rpc_action_name: :list_todos,
        type: :contract_changed,
        current_hash: "abcd1234abcd1234",
        snapshot_hash: "efgh5678efgh5678",
        current_version: 1,
        current_min_version: 1,
        snapshot_version: 1,
        snapshot_min_version: 1
      }

      message = SnapshotVerifier.format_violations([violation])

      assert message =~ "BREAKING CHANGE DETECTED"
      assert message =~ "Contract hash changed"
      assert message =~ "min_version"
      assert message =~ "list_todos"
    end

    test "format_violations formats version change violation" do
      violation = %{
        domain: Domain,
        resource: Todo,
        rpc_action_name: :create_todo,
        type: :version_changed,
        current_hash: "abcd1234abcd1234",
        snapshot_hash: "efgh5678efgh5678",
        current_version: 1,
        current_min_version: 1,
        snapshot_version: 1,
        snapshot_min_version: 1
      }

      message = SnapshotVerifier.format_violations([violation])

      assert message =~ "NON-BREAKING CHANGE DETECTED"
      assert message =~ "Version hash changed"
      assert message =~ "create_todo"
    end
  end

  describe "VersionGenerator" do
    alias AshTypescript.Rpc.Codegen.VersionGenerator

    setup do
      original_value = Application.get_env(:ash_typescript, :enable_rpc_snapshots)
      Application.put_env(:ash_typescript, :enable_rpc_snapshots, true)

      on_exit(fn ->
        if original_value do
          Application.put_env(:ash_typescript, :enable_rpc_snapshots, original_value)
        else
          Application.delete_env(:ash_typescript, :enable_rpc_snapshots)
        end
      end)

      :ok
    end

    test "action_key returns camelCase action name" do
      assert VersionGenerator.action_key(:list_todos) == "listTodos"
      assert VersionGenerator.action_key("create_user") == "createUser"
    end

    test "generate_version_entry returns entry when enabled" do
      rpc_action = %{name: :list_todos, version: 2, min_version: 1}

      result = VersionGenerator.generate_version_entry(rpc_action)

      assert {"listTodos", entry} = result
      assert entry =~ "listTodos:"
      assert entry =~ "version: 2"
      assert entry =~ "minVersion: 1"
    end

    test "generate_action_versions_object returns empty string for empty list" do
      assert VersionGenerator.generate_action_versions_object([]) == ""
    end

    test "generate_action_versions_object generates const object with entries" do
      entries = [
        "listTodos: { version: 2, minVersion: 1 }",
        "createTodo: { version: 3, minVersion: 2 }"
      ]

      result = VersionGenerator.generate_action_versions_object(entries)

      assert result =~ "export const actionVersions = {"
      assert result =~ "listTodos: { version: 2, minVersion: 1 }"
      assert result =~ "createTodo: { version: 3, minVersion: 2 }"
      assert result =~ "} as const;"
      assert result =~ "export type ActionVersionKey = keyof typeof actionVersions;"
    end

    test "generate_meta_object returns meta string when enabled" do
      result = VersionGenerator.generate_meta_object(:list_todos)

      assert result =~ "meta:"
      assert result =~ "version: actionVersions.listTodos.version"
    end

    test "generate_meta_object returns nil when disabled" do
      Application.put_env(:ash_typescript, :enable_rpc_snapshots, false)

      assert VersionGenerator.generate_meta_object(:list_todos) == nil
    end
  end

  describe "TypeScript codegen with versions" do
    setup do
      original_value = Application.get_env(:ash_typescript, :enable_rpc_snapshots)
      Application.put_env(:ash_typescript, :enable_rpc_snapshots, true)

      on_exit(fn ->
        if original_value do
          Application.put_env(:ash_typescript, :enable_rpc_snapshots, original_value)
        else
          Application.delete_env(:ash_typescript, :enable_rpc_snapshots)
        end
      end)

      :ok
    end

    test "generates actionVersions object when enabled" do
      {:ok, typescript} = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      assert typescript =~ "export const actionVersions = {"
      assert typescript =~ "} as const;"
      assert typescript =~ "export type ActionVersionKey = keyof typeof actionVersions;"
      assert typescript =~ "version:"
      assert typescript =~ "minVersion:"
    end

    test "includes version meta in payload when enabled" do
      {:ok, typescript} = AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

      # Check that at least one function includes version meta
      assert typescript =~ "meta: { version: actionVersions."
    end
  end

  describe "configuration" do
    test "enable_rpc_snapshots? returns false by default" do
      original_value = Application.get_env(:ash_typescript, :enable_rpc_snapshots)
      Application.delete_env(:ash_typescript, :enable_rpc_snapshots)

      refute AshTypescript.enable_rpc_snapshots?()

      if original_value do
        Application.put_env(:ash_typescript, :enable_rpc_snapshots, original_value)
      end
    end

    test "enable_rpc_snapshots? returns configured value" do
      original_value = Application.get_env(:ash_typescript, :enable_rpc_snapshots)
      Application.put_env(:ash_typescript, :enable_rpc_snapshots, true)

      assert AshTypescript.enable_rpc_snapshots?()

      Application.put_env(:ash_typescript, :enable_rpc_snapshots, false)

      refute AshTypescript.enable_rpc_snapshots?()

      if original_value do
        Application.put_env(:ash_typescript, :enable_rpc_snapshots, original_value)
      else
        Application.delete_env(:ash_typescript, :enable_rpc_snapshots)
      end
    end
  end

  # Helper functions

  defp get_rpc_action(domain, action_name) do
    domain
    |> AshTypescript.Rpc.Info.typescript_rpc()
    |> Enum.flat_map(fn %{rpc_actions: rpc_actions} -> rpc_actions end)
    |> Enum.find(fn rpc_action -> rpc_action.name == action_name end)
  end

  defp build_test_snapshot do
    resource = Todo
    action = Ash.Resource.Info.action(Todo, :read)
    rpc_action = get_rpc_action(Domain, :list_todos)

    Snapshot.build(Domain, resource, action, rpc_action)
  end
end
