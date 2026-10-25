# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.ChannelReview do
  @moduledoc """
  Test resource for TypedChannel multi-resource stress testing.

  Declares two map publications whose fields cover integer and boolean types.
  """
  use Ash.Resource,
    domain: nil,
    notifiers: [Ash.Notifier.PubSub]

  pub_sub do
    module AshTypescript.Test.TestEndpoint
    prefix "reviews"

    publish :create, [:id],
      event: "review_submitted",
      public?: true,
      returns: :map,
      constraints: [fields: [rating: [type: :integer, allow_nil?: false]]],
      transform: fn _notification -> %{rating: 0} end

    publish :update, [:id],
      event: "review_approved",
      public?: true,
      returns: :map,
      constraints: [fields: [approved: [type: :boolean, allow_nil?: false]]],
      transform: fn _notification -> %{approved: true} end
  end

  attributes do
    uuid_primary_key :id
    attribute :score, :integer, public?: true
    attribute :approved, :boolean, public?: true, default: false
  end

  actions do
    defaults [:read, :create, :update, :destroy]
  end
end
