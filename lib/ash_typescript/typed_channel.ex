# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.TypedChannel do
  @moduledoc """
  Standalone Spark DSL for typed Phoenix channel event subscriptions from
  Ash PubSub publications.

  Declares which publications a channel intercepts, enabling AshTypescript to
  generate typed TypeScript payload types and a subscription helper for each
  channel. The developer owns authorization (via `join/3`).

  The module using this DSL must also be a Phoenix channel (`use
  Phoenix.Channel`) — a compile warning is emitted otherwise. For every
  declared event, an intercept and a `handle_out/3` clause are injected that
  format the broadcast payload with the configured `output_field_formatter`
  (via `AshTypescript.TypedChannel.PayloadFormatter`) before pushing, so the
  wire payload matches the generated TypeScript types. Note that intercepting
  disables Phoenix's fastlane optimization for those events (see
  `Phoenix.Channel.intercept/1`).

  Publications should use `transform :some_calc` to reference a resource
  calculation. When the calculation uses `:auto` typing, Ash automatically
  derives the `returns` type from the expression, giving AshTypescript the
  type information it needs without manual `returns` declarations. You can
  also use explicit `returns:` with an anonymous function transform.

  Register typed channels in application config:

      config :ash_typescript,
        typed_channels: [MyApp.OrgAdminChannel]

  ## Usage

      # Resource with calculation transforms (recommended)
      defmodule MyApp.Post do
        use Ash.Resource, notifiers: [Ash.Notifier.PubSub]

        pub_sub do
          module MyApp.Endpoint
          prefix "posts"

          publish :create, [:id], event: "post_created", public?: true, transform: :post_summary
          publish :update, [:id], event: "post_updated", public?: true, transform: :post_summary
        end

        calculations do
          calculate :post_summary, :auto, expr(%{id: id, title: title}) do
            public? true
          end
        end
      end

      # Channel definition — the module must also be a Phoenix channel
      defmodule MyAppWeb.OrgAdminChannel do
        use Phoenix.Channel
        use AshTypescript.TypedChannel

        typed_channel do
          topic "org_admin:*"

          resource MyApp.Post do
            publish :post_created
            publish :post_updated
          end

          resource MyApp.Comment do
            publish :comment_created
          end
        end

        @impl true
        def join("org_admin:" <> _org_id, _payload, socket) do
          {:ok, socket}
        end
      end
  """

  use Spark.Dsl,
    default_extensions: [extensions: [AshTypescript.TypedChannel.Dsl]]

  @impl Spark.Dsl
  def handle_before_compile(_opts) do
    quote do
      require AshTypescript.TypedChannel.Interception
      AshTypescript.TypedChannel.Interception.inject()
    end
  end
end
