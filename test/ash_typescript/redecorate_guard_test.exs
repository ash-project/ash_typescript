# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.RedecorateGuardTest do
  @moduledoc """
  `AshRpc.Manifest.redecorate/2` re-decorates `custom.ash_rpc` only, and leaves
  the typed controller routes and channel publications under
  `custom.ash_typescript` in the old output formatter. Everything that varies the
  formatter goes through `AshTypescript.Manifest.redecorate/2`, which rebuilds
  both; its own body is the one legitimate caller.
  """
  use ExUnit.Case, async: true

  @moduletag :ash_typescript

  @root Path.expand("../..", __DIR__)
  @needle "AshRpc.Manifest" <> ".redecorate"
  @allowed ["lib/ash_typescript/manifest.ex", "test/ash_typescript/redecorate_guard_test.exs"]

  test "only AshTypescript.Manifest.redecorate/2 calls AshRpc.Manifest.redecorate/2" do
    callers =
      ["lib/**/*.ex", "test/**/*.ex", "test/**/*.exs"]
      |> Enum.flat_map(&Path.wildcard(Path.join(@root, &1)))
      |> Enum.map(&Path.relative_to(&1, @root))
      |> Enum.reject(&(&1 in @allowed))
      |> Enum.filter(&(@root |> Path.join(&1) |> File.read!() =~ @needle))
      |> Enum.sort()

    assert callers == [],
           "use AshTypescript.Manifest.redecorate/2 instead of #{@needle}/2 in:\n" <>
             Enum.join(callers, "\n")
  end
end
