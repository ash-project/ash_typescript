# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.ChannelAlert do
  @moduledoc """
  Test resource for TypedChannel multi-resource stress testing.

  Declares two map publications: alert_sent and alert_cleared (a utc_datetime field).
  """
  use Ash.Resource,
    domain: nil,
    notifiers: [Ash.Notifier.PubSub]

  pub_sub do
    module AshTypescript.Test.TestEndpoint
    prefix "alerts"

    publish :create, [:id],
      event: "alert_sent",
      public?: true,
      returns: :map,
      constraints: [
        fields: [
          id: [type: :uuid, allow_nil?: false],
          message: [type: :string, allow_nil?: true],
          severity: [type: :string, allow_nil?: true]
        ]
      ],
      transform: fn notification ->
        %{
          id: notification.data.id,
          message: notification.data.message,
          severity: notification.data.severity
        }
      end

    publish :destroy, [:id],
      event: "alert_cleared",
      public?: true,
      returns: :map,
      constraints: [fields: [cleared_at: [type: :utc_datetime, allow_nil?: false]]],
      transform: fn _notification -> %{cleared_at: DateTime.utc_now()} end
  end

  attributes do
    uuid_primary_key :id
    attribute :message, :string, public?: true
    attribute :severity, :string, public?: true
  end

  actions do
    defaults [:read, :create, :update, :destroy]
  end
end
