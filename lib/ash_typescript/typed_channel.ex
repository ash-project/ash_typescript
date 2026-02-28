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

  Register typed channels in application config:

      config :ash_typescript,
        typed_channels: [MyApp.OrgAdminChannel]

  ## Usage

      defmodule MyApp.OrgAdminChannel do
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
      end
  """

  use Spark.Dsl,
    default_extensions: [extensions: [AshTypescript.TypedChannel.Dsl]]
end
