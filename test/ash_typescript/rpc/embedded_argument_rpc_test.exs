# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.EmbeddedArgumentRpcTest do
  @moduledoc """
  Integration tests for RPC actions with embedded resources as direct argument types.

  Tests that the RPC pipeline correctly handles embedded resources when they are
  used directly as action argument types (not wrapped in Ash.Type.Struct). The
  client sends plain maps which must be correctly processed by the pipeline.
  """
  use ExUnit.Case, async: false

  alias AshTypescript.Rpc
  alias AshTypescript.Test.TestHelpers

  @process_metadata_fields ["processed", "priority", "source"]

  describe "process_metadata_todo action" do
    test "accepts embedded resource as plain map input" do
      conn = TestHelpers.build_rpc_conn()

      params = %{
        "action" => "process_metadata_todo",
        "input" => %{
          "metadata" => %{
            "category" => "work",
            "priorityScore" => 85,
            "isUrgent" => true,
            "tags" => ["urgent", "important"]
          }
        },
        "fields" => @process_metadata_fields
      }

      result = Rpc.run_action(:ash_typescript, conn, params)

      assert result["success"] == true
      assert result["data"]["processed"] == true
      assert result["data"]["source"] == "direct_embedded_argument"
    end

    test "accepts embedded resource with minimal fields" do
      conn = TestHelpers.build_rpc_conn()

      params = %{
        "action" => "process_metadata_todo",
        "input" => %{
          "metadata" => %{
            "category" => "personal"
          }
        },
        "fields" => @process_metadata_fields
      }

      result = Rpc.run_action(:ash_typescript, conn, params)

      assert result["success"] == true
      assert result["data"]["processed"] == true
      assert result["data"]["source"] == "direct_embedded_argument"
    end

    test "fails when metadata is missing" do
      conn = TestHelpers.build_rpc_conn()

      params = %{
        "action" => "process_metadata_todo",
        "input" => %{},
        "fields" => @process_metadata_fields
      }

      result = Rpc.run_action(:ash_typescript, conn, params)

      assert result["success"] == false
      assert is_list(result["errors"])
    end
  end

  @process_metadata_batch_fields ["processed", "priority"]

  describe "process_metadata_batch_todo action" do
    test "accepts array of embedded resources as plain map input" do
      conn = TestHelpers.build_rpc_conn()

      params = %{
        "action" => "process_metadata_batch_todo",
        "input" => %{
          "metadataItems" => [
            %{"category" => "work", "priorityScore" => 5},
            %{"category" => "personal", "priorityScore" => 2},
            %{"category" => "urgent", "priorityScore" => 10}
          ]
        },
        "fields" => @process_metadata_batch_fields
      }

      result = Rpc.run_action(:ash_typescript, conn, params)

      assert result["success"] == true
      assert is_list(result["data"])
      assert length(result["data"]) == 3

      Enum.each(result["data"], fn item ->
        assert item["processed"] == true
      end)
    end

    test "accepts empty array" do
      conn = TestHelpers.build_rpc_conn()

      params = %{
        "action" => "process_metadata_batch_todo",
        "input" => %{
          "metadataItems" => []
        },
        "fields" => @process_metadata_batch_fields
      }

      result = Rpc.run_action(:ash_typescript, conn, params)

      assert result["success"] == true
      assert result["data"] == []
    end

    test "accepts single item array" do
      conn = TestHelpers.build_rpc_conn()

      params = %{
        "action" => "process_metadata_batch_todo",
        "input" => %{
          "metadataItems" => [
            %{"category" => "solo", "priorityScore" => 7}
          ]
        },
        "fields" => @process_metadata_batch_fields
      }

      result = Rpc.run_action(:ash_typescript, conn, params)

      assert result["success"] == true
      assert length(result["data"]) == 1
      assert hd(result["data"])["processed"] == true
    end

    test "fails when metadataItems is missing" do
      conn = TestHelpers.build_rpc_conn()

      params = %{
        "action" => "process_metadata_batch_todo",
        "input" => %{},
        "fields" => @process_metadata_batch_fields
      }

      result = Rpc.run_action(:ash_typescript, conn, params)

      assert result["success"] == false
      assert is_list(result["errors"])
    end
  end
end
