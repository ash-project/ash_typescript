# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.RemovedEntryPointsTest do
  use ExUnit.Case, async: true

  test "the clean break removes the old runtime entry points" do
    Code.ensure_loaded!(AshTypescript.Rpc)
    refute function_exported?(AshTypescript.Rpc, :run_action, 3)
    refute function_exported?(AshTypescript.Rpc, :validate_action, 3)
  end
end
