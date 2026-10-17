# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# Channel with a static topic (no wildcard) — exercises the no-suffix factory path.
defmodule AshTypescript.Test.TypedChannel.StaticTopicChannel do
  @moduledoc false
  use Phoenix.Channel
  use AshTypescript.TypedChannel

  def join(_topic, _payload, socket), do: {:ok, socket}

  typed_channel do
    topic "notifications"

    resource AshTypescript.Test.ChannelItem do
      publish :item_created
    end
  end
end
