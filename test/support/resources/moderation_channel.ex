# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.ModerationChannel do
  @moduledoc """
  Channel for moderation events: article archival, review approval, and alert broadcasts.

  Mixes events from all three resources: ChannelArticle, ChannelReview, and ChannelAlert.
  """
  use AshTypescript.TypedChannel

  typed_channel do
    topic("moderation:*")

    resource AshTypescript.Test.ChannelArticle do
      publish(:article_archived)
    end

    resource AshTypescript.Test.ChannelReview do
      publish(:review_approved)
    end

    resource AshTypescript.Test.ChannelAlert do
      publish(:alert_sent)
    end
  end
end
