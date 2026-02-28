# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.ContentFeedChannel do
  @moduledoc """
  Channel that subscribes to article publish/update events and new review submissions.

  Mixes events from two resources: ChannelArticle and ChannelReview.
  """
  use AshTypescript.TypedChannel

  typed_channel do
    topic("content_feed:*")

    resource AshTypescript.Test.ChannelArticle do
      publish(:article_published)
      publish(:article_updated)
    end

    resource AshTypescript.Test.ChannelReview do
      publish(:review_submitted)
    end
  end
end
