# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.ResultProcessorDurationTest do
  use ExUnit.Case, async: true

  alias AshTypescript.Rpc.ResultProcessor

  describe "Duration struct handling" do
    test "converts Duration to ISO 8601 string" do
      duration = %Duration{hour: 1, minute: 30, second: 45}

      result = ResultProcessor.normalize_value_for_json(duration)

      assert result == "PT1H30M45S"
    end

    test "converts Duration with days to ISO 8601 string" do
      duration = %Duration{day: 2, hour: 5}

      result = ResultProcessor.normalize_value_for_json(duration)

      # ISO 8601 duration format: P[n]D T[n]H[n]M[n]S
      assert result == "P2DT5H"
    end

    test "converts zero Duration to ISO 8601 string" do
      duration = %Duration{}

      result = ResultProcessor.normalize_value_for_json(duration)

      assert result == "PT0S"
    end

    test "converts Duration with microseconds to ISO 8601 string" do
      duration = %Duration{second: 30, microsecond: {500_000, 6}}

      result = ResultProcessor.normalize_value_for_json(duration)

      assert result == "PT30.500000S"
    end

    test "handles nil Duration" do
      result = ResultProcessor.normalize_value_for_json(nil)
      assert result == nil
    end

    test "processes Duration field in extraction template" do
      data = %{
        id: "123",
        title: "Test Task",
        estimated_duration: %Duration{hour: 2, minute: 15}
      }

      extraction_template = [:id, :title, :estimated_duration]

      result = ResultProcessor.process(data, extraction_template)

      expected = %{
        id: "123",
        title: "Test Task",
        estimated_duration: "PT2H15M"
      }

      assert result == expected
    end

    test "processes Duration in nested structures" do
      data = %{
        task: %{
          name: "Build feature",
          duration: %Duration{day: 1, hour: 4}
        },
        breaks: [
          %Duration{minute: 15},
          %Duration{minute: 30}
        ]
      }

      result = ResultProcessor.normalize_value_for_json(data)

      assert result.task.duration == "P1DT4H"
      assert result.breaks == ["PT15M", "PT30M"]
    end
  end
end
