# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.TypeDiscoveryTest do
  use ExUnit.Case, async: true

  alias AshTypescript.Codegen.TypeDiscovery

  describe "get_rpc_resources/1" do
    test "returns all RPC resources configured in domains" do
      rpc_resources = TypeDiscovery.get_rpc_resources(:ash_typescript)

      # These are configured in test/support/domain.ex
      assert AshTypescript.Test.Todo in rpc_resources
      assert AshTypescript.Test.TodoComment in rpc_resources
      assert AshTypescript.Test.User in rpc_resources
      assert AshTypescript.Test.UserSettings in rpc_resources
      assert AshTypescript.Test.OrgTodo in rpc_resources
      assert AshTypescript.Test.Task in rpc_resources

      # These are NOT configured as RPC resources
      refute AshTypescript.Test.TodoMetadata in rpc_resources
      refute AshTypescript.Test.NotExposed in rpc_resources
    end
  end

  describe "find_resources_missing_from_rpc_config/1" do
    test "finds resources with extension but not in typescript_rpc" do
      result = TypeDiscovery.find_resources_missing_from_rpc_config(:ash_typescript)

      assert is_list(result)
      assert Enum.all?(result, &is_atom/1)
    end
  end

  describe "build_rpc_warnings/1" do
    test "returns nil when all warnings disabled" do
      original_missing = Application.get_env(:ash_typescript, :warn_on_missing_rpc_config)
      original_non_rpc = Application.get_env(:ash_typescript, :warn_on_non_rpc_references)

      try do
        Application.put_env(:ash_typescript, :warn_on_missing_rpc_config, false)
        Application.put_env(:ash_typescript, :warn_on_non_rpc_references, false)

        assert TypeDiscovery.build_rpc_warnings(:ash_typescript) == nil
      after
        if original_missing do
          Application.put_env(:ash_typescript, :warn_on_missing_rpc_config, original_missing)
        else
          Application.delete_env(:ash_typescript, :warn_on_missing_rpc_config)
        end

        if original_non_rpc do
          Application.put_env(:ash_typescript, :warn_on_non_rpc_references, original_non_rpc)
        else
          Application.delete_env(:ash_typescript, :warn_on_non_rpc_references)
        end
      end
    end

    test "respects warn_on_missing_rpc_config flag" do
      original_missing = Application.get_env(:ash_typescript, :warn_on_missing_rpc_config)
      original_non_rpc = Application.get_env(:ash_typescript, :warn_on_non_rpc_references)

      try do
        Application.put_env(:ash_typescript, :warn_on_missing_rpc_config, false)
        Application.put_env(:ash_typescript, :warn_on_non_rpc_references, true)

        output = TypeDiscovery.build_rpc_warnings(:ash_typescript)

        if output do
          refute output =~ "Found resources with AshTypescript.Resource extension"
        end
      after
        if original_missing do
          Application.put_env(:ash_typescript, :warn_on_missing_rpc_config, original_missing)
        else
          Application.delete_env(:ash_typescript, :warn_on_missing_rpc_config)
        end

        if original_non_rpc do
          Application.put_env(:ash_typescript, :warn_on_non_rpc_references, original_non_rpc)
        else
          Application.delete_env(:ash_typescript, :warn_on_non_rpc_references)
        end
      end
    end

    test "respects warn_on_non_rpc_references flag" do
      original_missing = Application.get_env(:ash_typescript, :warn_on_missing_rpc_config)
      original_non_rpc = Application.get_env(:ash_typescript, :warn_on_non_rpc_references)

      try do
        Application.put_env(:ash_typescript, :warn_on_missing_rpc_config, true)
        Application.put_env(:ash_typescript, :warn_on_non_rpc_references, false)

        output = TypeDiscovery.build_rpc_warnings(:ash_typescript)

        if output do
          refute output =~ "Found non-RPC resources referenced by RPC resources"
        end
      after
        if original_missing do
          Application.put_env(:ash_typescript, :warn_on_missing_rpc_config, original_missing)
        else
          Application.delete_env(:ash_typescript, :warn_on_missing_rpc_config)
        end

        if original_non_rpc do
          Application.put_env(:ash_typescript, :warn_on_non_rpc_references, original_non_rpc)
        else
          Application.delete_env(:ash_typescript, :warn_on_non_rpc_references)
        end
      end
    end

    test "non-RPC references warning states NO types are generated" do
      original_missing = Application.get_env(:ash_typescript, :warn_on_missing_rpc_config)
      original_non_rpc = Application.get_env(:ash_typescript, :warn_on_non_rpc_references)

      try do
        Application.put_env(:ash_typescript, :warn_on_missing_rpc_config, false)
        Application.put_env(:ash_typescript, :warn_on_non_rpc_references, true)

        output = TypeDiscovery.build_rpc_warnings(:ash_typescript)

        if output do
          assert output =~ "Found non-RPC resources referenced by RPC resources"
          assert output =~ "will NOT have TypeScript types or RPC functions generated"
          refute output =~ "will have basic TypeScript types generated"
        end
      after
        if original_missing do
          Application.put_env(:ash_typescript, :warn_on_missing_rpc_config, original_missing)
        else
          Application.delete_env(:ash_typescript, :warn_on_missing_rpc_config)
        end

        if original_non_rpc do
          Application.put_env(:ash_typescript, :warn_on_non_rpc_references, original_non_rpc)
        else
          Application.delete_env(:ash_typescript, :warn_on_non_rpc_references)
        end
      end
    end

    test "warnings are enabled by default" do
      original_missing = Application.get_env(:ash_typescript, :warn_on_missing_rpc_config)
      original_non_rpc = Application.get_env(:ash_typescript, :warn_on_non_rpc_references)

      try do
        Application.delete_env(:ash_typescript, :warn_on_missing_rpc_config)
        Application.delete_env(:ash_typescript, :warn_on_non_rpc_references)

        assert AshTypescript.warn_on_missing_rpc_config?() == true
        assert AshTypescript.warn_on_non_rpc_references?() == true
      after
        if original_missing do
          Application.put_env(:ash_typescript, :warn_on_missing_rpc_config, original_missing)
        else
          Application.delete_env(:ash_typescript, :warn_on_missing_rpc_config)
        end

        if original_non_rpc do
          Application.put_env(:ash_typescript, :warn_on_non_rpc_references, original_non_rpc)
        else
          Application.delete_env(:ash_typescript, :warn_on_non_rpc_references)
        end
      end
    end
  end
end
