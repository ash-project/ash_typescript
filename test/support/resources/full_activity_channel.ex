# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.FullActivityChannel do
  @moduledoc """
  Channel that subscribes to every event across all three test resources.

  Used to stress-test generation with all event/type combinations:
  - article_published: :map → {id: UUID, title: string | null}
  - article_updated: :string → string
  - article_archived: :boolean → boolean
  - review_submitted: :integer → number
  - review_approved: :boolean → boolean
  - alert_sent: :map → {id: UUID, message: string | null, severity: string | null}
  - alert_cleared: :utc_datetime → UtcDateTime
  """
  use AshTypescript.TypedChannel

  typed_channel do
    topic("activity:*")

    resource AshTypescript.Test.ChannelArticle do
      publish(:article_published)
      publish(:article_updated)
      publish(:article_archived)
    end

    resource AshTypescript.Test.ChannelReview do
      publish(:review_submitted)
      publish(:review_approved)
    end

    resource AshTypescript.Test.ChannelAlert do
      publish(:alert_sent)
      publish(:alert_cleared)
    end
  end
end
