# SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.Todo.OwnerCalculation do
  @moduledoc """
  Calculation for todo owner information.
  """
  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context) do
    [:user]
  end

  @impl true
  def calculate(records, _opts, _context) do
    # Return the owner (user) for each todo
    Enum.map(records, fn record ->
      record.user
    end)
  end
end
