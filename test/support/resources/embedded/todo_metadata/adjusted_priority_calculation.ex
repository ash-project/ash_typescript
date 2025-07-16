defmodule AshTypescript.Test.TodoMetadata.AdjustedPriorityCalculation do
  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context) do
    [:priority_score, :is_urgent, :deadline]
  end

  @impl true
  def calculate(records, opts, _context) do
    urgency_multiplier = opts[:urgency_multiplier] || 1.0
    deadline_factor = opts[:deadline_factor] || true
    user_bias = opts[:user_bias] || 0

    Enum.map(records, fn record ->
      base_priority = record.priority_score || 0

      # Apply urgency multiplier
      adjusted =
        if record.is_urgent do
          round(base_priority * urgency_multiplier)
        else
          base_priority
        end

      # Apply deadline factor
      adjusted =
        if deadline_factor && record.deadline do
          days_until_deadline = Date.diff(record.deadline, Date.utc_today())

          case days_until_deadline do
            # Very urgent
            days when days <= 1 -> adjusted + 20
            # Urgent
            days when days <= 7 -> adjusted + 10
            # Somewhat urgent
            days when days <= 30 -> adjusted + 5
            _ -> adjusted
          end
        else
          adjusted
        end

      # Apply user bias
      final_priority = adjusted + user_bias

      # Ensure within bounds [0, 100]
      max(0, min(100, final_priority))
    end)
  end
end
