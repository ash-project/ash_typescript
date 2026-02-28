# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.TypedChannel.Dsl do
  @moduledoc """
  Spark DSL extension for defining typed Phoenix channel event subscriptions.

  Declares which Ash PubSub publications a channel intercepts. For each declared
  event, AshTypescript reads the publication's `returns` Ash.Type and generates
  a typed TypeScript payload type. An event map and typed subscription helper
  are also generated for the channel.

  ## Usage

      defmodule MyAppWeb.OrgAdminChannel do
        use AshTypescript.TypedChannel

        @impl true
        def join("org_admin:" <> org_id, _payload, socket) do
          {:ok, socket}
        end

        typed_channel do
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

  defmodule Publication do
    @moduledoc "Represents a declared channel event subscription."
    defstruct [:event, __spark_metadata__: nil]
  end

  defmodule ChannelResource do
    @moduledoc "Represents an Ash resource whose publications are subscribed to."
    defstruct [:module, publications: [], __spark_metadata__: nil]
  end

  @publication %Spark.Dsl.Entity{
    name: :publish,
    target: Publication,
    describe: """
    Declare a PubSub event to intercept on this channel.

    The event name must match the `event` option (or action name fallback) of
    a publication on the resource. The publication must have `returns` set for
    TypeScript type generation.
    """,
    args: [:event],
    schema: [
      event: [
        type: {:or, [:atom, :string]},
        required: true,
        doc: "The event name to intercept (atom or string)."
      ]
    ]
  }

  @channel_resource %Spark.Dsl.Entity{
    name: :resource,
    target: ChannelResource,
    describe: """
    Declare an Ash resource whose publications this channel subscribes to.

    Each `publish` child declares a specific event to intercept.
    """,
    args: [:module],
    entities: [publications: [@publication]],
    schema: [
      module: [
        type: :atom,
        required: true,
        doc: "The Ash resource module containing the PubSub publications."
      ]
    ]
  }

  @typed_channel %Spark.Dsl.Section{
    name: :typed_channel,
    describe: "Configure typed channel subscriptions from Ash PubSub publications.",
    entities: [@channel_resource],
    schema: [
      topic: [
        type: :string,
        required: true,
        doc: "The Phoenix channel topic pattern (e.g. \"org:*\")."
      ]
    ]
  }

  use Spark.Dsl.Extension,
    sections: [@typed_channel],
    verifiers: [AshTypescript.TypedChannel.Verifiers.VerifyTypedChannel]
end
