# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.MetadataReportCalculation do
  @moduledoc """
  Returns a typed map containing an array of embedded resources — regression
  coverage for the `__primitiveFields` classification of embedded-resource
  fields inside TypedMaps.
  """
  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context), do: []

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, fn _record ->
      %{
        rows: [
          %AshTypescript.Test.TodoMetadata{category: "work", priority_score: 80},
          %AshTypescript.Test.TodoMetadata{category: "personal", priority_score: 20}
        ],
        total: 2
      }
    end)
  end
end
