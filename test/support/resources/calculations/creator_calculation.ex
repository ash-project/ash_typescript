# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.CreatorCalculation do
  @moduledoc """
  Returns the todo's creator (user) as a calculation without arguments.
  Used to test load-through on calculation_complex returning a resource.
  """
  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context) do
    [:user]
  end

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, fn record ->
      record.user
    end)
  end
end
