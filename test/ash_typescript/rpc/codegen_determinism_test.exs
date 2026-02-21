# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.CodegenDeterminismTest do
  @moduledoc """
  Regression test to ensure TypeScript code generation is deterministic.

  Runs the codegen multiple times and verifies that the output is identical
  across all runs. Non-determinism typically comes from iterating over maps,
  MapSets, or unsorted collections derived from Ash.Info.domains().
  """
  use ExUnit.Case, async: false

  @moduletag :ash_typescript

  setup do
    Application.put_env(:ash_typescript, :enable_namespace_files, false)
    :ok
  end

  describe "codegen determinism" do
    test "generating TypeScript types 10 times produces identical output" do
      hashes =
        Enum.map(1..10, fn _i ->
          {:ok, typescript} =
            AshTypescript.Rpc.Codegen.generate_typescript_types(:ash_typescript)

          :crypto.hash(:sha256, typescript) |> Base.encode16()
        end)

      unique_hashes = Enum.uniq(hashes)

      assert length(unique_hashes) == 1,
             "Expected all 10 runs to produce identical output, but got #{length(unique_hashes)} distinct outputs"
    end
  end
end
