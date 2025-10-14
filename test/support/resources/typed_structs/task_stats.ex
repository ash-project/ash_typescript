# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.TaskStats do
  @moduledoc """
  Test TypedStruct for task statistics with field name mappings.
  Demonstrates field mappings in typed structs for testing.
  """
  use Ash.TypedStruct

  def typescript_field_names do
    [
      completed?: :completed,
      is_urgent?: :is_urgent
    ]
  end

  typed_struct do
    field(:total_count, :integer, default: 0)
    field(:completed?, :boolean)
    field(:is_urgent?, :boolean, default: false)
    field(:average_duration, :float)
  end
end
