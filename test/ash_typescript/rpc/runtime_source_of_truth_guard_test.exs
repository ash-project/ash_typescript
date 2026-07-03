# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.RuntimeSourceOfTruthGuardTest do
  @moduledoc """
  Locks in the single-source-of-truth invariant: runtime request-pipeline
  modules must read ash_typescript-specific derived data only through
  `AshTypescript.Manifest.Custom`, never `AshTypescript.Resource.Info`,
  `AshTypescript.Rpc.Info`, or `Map.get/2` on a raw rpc_action for the
  migrated concerns (load restrictions, filter/sort, metadata exposure).
  """
  use ExUnit.Case, async: true

  @runtime_files [
    "lib/ash_typescript/rpc/pipeline.ex",
    "lib/ash_typescript/rpc/field_processing/atomizer.ex",
    "lib/ash_typescript/rpc/field_processing/field_selector.ex",
    "lib/ash_typescript/rpc/value_formatter.ex",
    "lib/ash_typescript/rpc/output_formatter.ex",
    "lib/ash_typescript/rpc/input_formatter.ex"
  ]

  @forbidden_modules ["AshTypescript.Resource.Info", "AshTypescript.Rpc.Info"]

  @forbidden_rpc_action_reads [
    "Map.get(rpc_action, :allowed_loads",
    "Map.get(rpc_action, :denied_loads",
    "Map.get(rpc_action, :enable_filter?",
    "Map.get(rpc_action, :enable_sort?",
    "Map.get(rpc_action, :show_metadata"
  ]

  for file <- @runtime_files do
    test "#{file} has no retired source-of-truth reads" do
      source = File.read!(unquote(file))

      for needle <- @forbidden_modules ++ @forbidden_rpc_action_reads do
        refute String.contains?(source, needle),
               "#{unquote(file)} must not contain #{inspect(needle)} — read via Manifest.Custom instead"
      end
    end
  end
end
