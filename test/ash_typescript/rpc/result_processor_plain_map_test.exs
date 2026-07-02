# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.ResultProcessorPlainMapTest do
  use ExUnit.Case, async: true

  alias AshTypescript.Rpc.ResultProcessor

  describe "plain map extraction (untyped maps with a field template)" do
    test "preserves false values under atom keys" do
      assert %{enabled: false} =
               ResultProcessor.extract_value(%{enabled: false}, nil, [], [:enabled])
    end

    test "preserves false values under string keys" do
      assert %{enabled: false} =
               ResultProcessor.extract_value(%{"enabled" => false}, nil, [], [:enabled])
    end

    test "preserves false values in nested templates" do
      assert %{settings: %{enabled: false}} =
               ResultProcessor.extract_value(
                 %{settings: %{enabled: false}},
                 nil,
                 [],
                 [{:settings, [:enabled]}]
               )
    end

    test "missing atom key still falls back to the string key" do
      assert %{count: 3} =
               ResultProcessor.extract_value(%{"count" => 3}, nil, [], [:count])
    end
  end
end
