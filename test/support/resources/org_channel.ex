# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.OrgChannel do
  @moduledoc """
  Test TypedChannel module for codegen testing.

  Subscribes to item events published by AshTypescript.Test.ChannelItem.
  """
  use AshTypescript.TypedChannel

  typed_channel do
    topic("org:*")

    resource AshTypescript.Test.ChannelItem do
      publish(:item_created)
      publish(:item_updated)
      publish(:item_deleted)
    end
  end
end
