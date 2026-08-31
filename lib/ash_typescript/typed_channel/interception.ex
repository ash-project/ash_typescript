# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.TypedChannel.Interception do
  @moduledoc """
  Compile-time injection of Phoenix channel event interception for typed
  channels.

  `use AshTypescript.TypedChannel` arranges (via Spark's
  `handle_before_compile/1`) for `inject/0` to expand in the channel module
  right before compilation. When the module is also a `Phoenix.Channel`, the
  injected code registers every declared typed-channel event as an intercepted
  event and defines `handle_out/3` clauses that format the broadcast payload
  through `AshTypescript.TypedChannel.PayloadFormatter` before pushing — so
  the wire format matches the generated TypeScript payload types.

  Events the module already handles with its own `handle_out/3` clause are left
  alone — the developer's clause owns the push for those events.

  When the module is not a `Phoenix.Channel`, a compile warning is emitted
  instead: the typed channel DSL only has meaning for the module that actually
  serves the channel topic.

  Interception disables Phoenix's fastlane for the declared events (payloads
  are encoded per subscriber instead of once per broadcast) — the standard
  cost of `Phoenix.Channel.intercept/1`.
  """

  # The quoted block runs at module-body evaluation time (Spark's DSL state
  # and all body-registered attributes are only available then, not at macro
  # expansion time), so `unquote: false` keeps the inner unquotes as unquote
  # fragments resolved against eval-time bindings.
  @doc false
  defmacro inject do
    quote generated: true, unquote: false do
      if AshTypescript.TypedChannel.Interception.phoenix_channel?(__MODULE__) do
        entries = AshTypescript.TypedChannel.Interception.channel_event_entries(__MODULE__)
        events = entries |> Enum.map(&elem(&1, 1)) |> Enum.uniq()

        if events != [] do
          # The attribute write must come first: Phoenix's __on_definition__
          # checks each handle_out clause's event against @phoenix_intercepts
          # at definition time. It also merges with any intercept/1 call the
          # user made themselves.
          @phoenix_intercepts Enum.uniq(events ++ (@phoenix_intercepts || []))

          if Module.defines?(__MODULE__, {:__intercepts__, 0}) do
            # `use Phoenix.Channel` came before `use AshTypescript.TypedChannel`,
            # so Phoenix's __before_compile__ has already baked __intercepts__/0
            # from the attribute — merge by overriding it.
            defoverridable __intercepts__: 0

            @doc false
            def __intercepts__, do: Enum.uniq(unquote(events) ++ super())
          end

          # Clauses injected from `before_compile` shadow an identical clause
          # head already present in the module body, so a developer-written
          # `handle_out/3` would silently become dead code. Skip those events
          # and let their clause handle the push.
          user_handled =
            AshTypescript.TypedChannel.Interception.user_handled_events(__MODULE__)

          for {resource, event} <- entries, event not in user_handled do
            def handle_out(unquote(event), payload, socket) do
              AshTypescript.TypedChannel.PayloadFormatter.push_formatted(
                socket,
                unquote(resource),
                unquote(event),
                payload
              )

              {:noreply, socket}
            end
          end
        end
      else
        IO.warn(
          "AshTypescript.TypedChannel is being used in module #{inspect(__MODULE__)} without " <>
            "`use Phoenix.Channel`, you must add `use Phoenix.Channel` in order for your " <>
            "typed channel to work as expected",
          Macro.Env.stacktrace(__ENV__)
        )
      end
    end
  end

  @doc false
  def phoenix_channel?(module) do
    module
    |> Module.get_attribute(:behaviour)
    |> List.wrap()
    |> Enum.member?(Phoenix.Channel)
  end

  @doc false
  def user_handled_events(module) do
    case Module.get_definition(module, {:handle_out, 3}) do
      {:v1, :def, _meta, clauses} ->
        for {_meta, [event, _payload, _socket], _guards, _body} <- clauses,
            is_binary(event),
            do: event

      _ ->
        []
    end
  end

  @doc false
  def channel_event_entries(module) do
    module
    |> Module.get_attribute(:spark_dsl_config)
    |> AshTypescript.TypedChannel.Info.typed_channel()
    |> Enum.flat_map(fn channel_resource ->
      Enum.map(channel_resource.publications, fn pub ->
        {channel_resource.module, to_string(pub.event)}
      end)
    end)
    |> Enum.uniq()
  end
end
