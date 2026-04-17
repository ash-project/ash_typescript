# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.TrackerChannel do
  @moduledoc """
  Test TypedChannel for ash automagic features.

  Subscribes to events from ChannelTracker which uses:
  - `transform: :calc_name` (atom-based transforms)
  - `:auto` type calculations (string, map, boolean, aggregate)
  - relationship traversal in map expressions
  """
  use AshTypescript.TypedChannel

  typed_channel do
    topic("tracker:*")

    resource AshTypescript.Test.ChannelTracker do
      publish(:tracker_summary)
      publish(:tracker_label)
      publish(:tracker_status_changed)
      publish(:tracker_snapshot)
      publish(:tracker_ordered_card)
      publish(:tracker_detail)
      publish(:tracker_entry_count)
      publish(:tracker_is_active)
      publish(:tracker_top_score)
      publish(:tracker_deep_detail)
      publish(:tracker_report)
    end
  end
end
