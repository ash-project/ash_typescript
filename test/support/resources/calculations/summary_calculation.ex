# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.SummaryCalculation do
  @moduledoc """
  Summary calculation for todos.
  """
  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context) do
    []
  end

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, fn _record ->
      # Return a sample TodoStatistics struct for testing
      %AshTypescript.Test.TodoStatistics{
        view_count: 42,
        edit_count: 7,
        completion_time_seconds: 1800,
        difficulty_rating: 3.5
      }
    end)
  end
end
