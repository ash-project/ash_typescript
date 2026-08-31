# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.TypedChannel.PayloadFormatter do
  @moduledoc """
  Formats typed channel payloads at the websocket boundary.

  Ash PubSub broadcasts carry the publication's `transform` result verbatim
  (snake_case atom keys), while the generated TypeScript payload types use the
  configured `output_field_formatter` — so without intervention the types would
  not match the wire for multi-word fields.

  The interception code injected by `use AshTypescript.TypedChannel` (see
  `AshTypescript.TypedChannel.Interception`) routes intercepted events through
  this module, which formats the payload with the same type-driven
  `ValueFormatter` the RPC pipeline uses before pushing to the client.
  """

  alias AshTypescript.Rpc.ValueFormatter
  alias AshTypescript.TypedChannel.Info

  @doc """
  Formats `payload` according to the publication's `returns` type and pushes
  it to the socket under `event`.
  """
  @spec push_formatted(Phoenix.Socket.t(), module(), String.t(), term()) :: :ok
  def push_formatted(socket, resource, event, payload) do
    Phoenix.Channel.push(socket, event, format_payload(resource, event, payload))
  end

  @doc """
  Formats a broadcast payload for the client using the publication's `returns`
  type and the configured `output_field_formatter`.

  Returns the payload unchanged when the resource has no publication matching
  `event` or the publication declares no `returns` type.
  """
  @spec format_payload(module(), String.t(), term()) :: term()
  def format_payload(resource, event, payload) do
    case Info.find_publication(resource, event) do
      %{returns: returns, constraints: constraints} when not is_nil(returns) ->
        ValueFormatter.format(
          payload,
          returns,
          constraints || [],
          AshTypescript.Rpc.output_field_formatter(),
          :output,
          AshTypescript.resource_lookup()
        )

      _ ->
        payload
    end
  end
end
