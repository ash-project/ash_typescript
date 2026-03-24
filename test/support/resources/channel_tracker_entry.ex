# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.ChannelTrackerEntry do
  @moduledoc """
  Related resource for ChannelTracker — used to test relationship traversal
  in :auto calculations and complex expression type inference.

  Has a belongs_to :author for nested relationship traversal tests.
  """
  use Ash.Resource, domain: nil, data_layer: Ash.DataLayer.Ets

  attributes do
    uuid_primary_key :id
    attribute :body, :string, public?: true
    attribute :score, :integer, public?: true, default: 0
    attribute :channel_tracker_id, :uuid, public?: true
    attribute :channel_tracker_author_id, :uuid, public?: true
  end

  relationships do
    belongs_to :channel_tracker, AshTypescript.Test.ChannelTracker do
      attribute_writable? true
      public? true
    end

    belongs_to :channel_tracker_author, AshTypescript.Test.ChannelTrackerAuthor do
      attribute_writable? true
      public? true
    end
  end

  actions do
    defaults [:read, :create, :update, :destroy]
  end
end
