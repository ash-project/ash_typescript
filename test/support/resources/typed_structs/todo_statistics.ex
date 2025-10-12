# SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.TodoStatistics do
  @moduledoc """
  Test TypedStruct for todo statistics and performance metrics.
  """
  use Ash.TypedStruct

  def typescript_field_names do
    [all_completed?: :all_completed]
  end

  typed_struct do
    field(:view_count, :integer, default: 0)
    field(:edit_count, :integer, default: 0)
    field(:completion_time_seconds, :integer)
    field(:difficulty_rating, :float)
    field(:all_completed?, :boolean)

    # Composite type field - map with constrained fields for performance metrics
    field(:performance_metrics, :map,
      constraints: [
        fields: [
          focus_time_seconds: [type: :integer, allow_nil?: false],
          interruption_count: [type: :integer, allow_nil?: false],
          efficiency_score: [type: :float, allow_nil?: false],
          task_complexity: [type: :string, allow_nil?: true]
        ]
      ]
    )
  end
end
