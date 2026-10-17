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

  The type comes only from the manifest: the `%AshTypescript.Manifest.Publication{}`
  stored for `{channel_module, resource, event}`. The channel must be listed in
  the manifest module's `typed_channels:` option. When the manifest has no entry
  for the event, the payload is pushed unchanged and a warning is logged.
  """

  require Logger

  alias AshRpc.ValueFormatter
  alias AshTypescript.Manifest.{Custom, Publication}

  @doc """
  Formats `payload` with `format_payload/4` and pushes it to the socket under
  `event`.
  """
  @spec push_formatted(Phoenix.Socket.t(), module(), module(), String.t(), term()) :: :ok
  def push_formatted(socket, channel_module, resource, event, payload) do
    Phoenix.Channel.push(socket, event, format_payload(channel_module, resource, event, payload))
  end

  @doc """
  Formats a broadcast payload for the client against the decorated `returns`
  type of the manifest publication stored for `{channel_module, resource, event}`.

  Returns the payload unchanged when the publication declares no `returns`.
  When the manifest has no publication for the key (the channel is not listed
  in the manifest module's `typed_channels:` option, or the manifest is stale),
  returns it unchanged and logs a warning.
  """
  @spec format_payload(module(), module(), String.t(), term()) :: term()
  def format_payload(channel_module, resource, event, payload) do
    manifest = AshTypescript.manifest()

    case Custom.publication(manifest, channel_module, resource, event) do
      # No `returns` declared: nothing to format against, so push as-is
      %Publication{returns: nil} ->
        payload

      %Publication{returns: returns} ->
        ValueFormatter.format(
          payload,
          returns,
          [],
          :output,
          AshRpc.Runtime.from_manifest(manifest)
        )

      nil ->
        warn_missing(channel_module, resource, event)
        payload
    end
  end

  # Reads only the manifest. Every DSL-declared event of a manifest channel is
  # stored, so a miss means the channel isn't listed in the manifest or the
  # manifest is stale. Injected handle_out clauses exist only for declared
  # events, so nothing else reaches this; a direct call with an undeclared
  # event warns too.
  defp warn_missing(channel_module, resource, event) do
    Logger.warning(
      "#{inspect(channel_module)} event #{inspect(event)} (#{inspect(resource)}) is not in " <>
        "the manifest; add the channel to the manifest module's `typed_channels:` " <>
        "option and recompile."
    )
  end
end
