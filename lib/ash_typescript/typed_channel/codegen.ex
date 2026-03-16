# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.TypedChannel.Codegen do
  @moduledoc """
  Generates TypeScript types and functions for typed channel event subscriptions.

  For each declared event in a typed channel module, introspects the matching
  Ash PubSub publication's `returns` type and maps it to a TypeScript type.

  ## Generated Output

  Types (emitted into `ash_types.ts`):

      // Branded channel type — only creatable via createOrgChannel
      export type OrgChannel = {
        readonly __channelType: "OrgChannel";
        on(event: string, callback: (payload: unknown) => void): number;
        off(event: string, ref: number): void;
      };

      // Payload types
      export type ItemCreatedPayload = string;

      // Events map
      export type OrgChannelEvents = { item_created: ItemCreatedPayload; };

      // Utility types for onOrgChannelMessages / unsubscribeOrgChannel
      export type OrgChannelHandlers = { ... };
      export type OrgChannelRefs = { ... };

  Functions (emitted into the typed channels output file, e.g. `ash_typed_channels.ts`):

      // Factory — the only way to obtain an OrgChannel
      export function createOrgChannel(socket, suffix: string): OrgChannel { ... }

      // Single-event subscription
      export function onOrgChannelMessage<E extends keyof OrgChannelEvents>(
        channel: OrgChannel, event: E, handler: ...
      ): number { ... }

      // Multi-event subscription
      export function onOrgChannelMessages(channel: OrgChannel, handlers: OrgChannelHandlers): OrgChannelRefs { ... }

      // Cleanup
      export function unsubscribeOrgChannel(channel: OrgChannel, refs: OrgChannelRefs): void { ... }
  """

  alias AshTypescript.Codegen.TypeMapper
  alias AshTypescript.TypedChannel.Info

  @doc """
  Generates TypeScript type declarations for all configured typed channel modules.

  Accepts a list of `{module, topic}` tuples. The topic (e.g. `"org:*"`) is used
  to generate a branded `OrgChannel` type that prevents mixing channel instances.

  Emits:
  - Deduplicated payload type aliases
  - Per-channel branded type, events map, handlers type, and refs type

  Subscription helper functions are NOT included — use `generate_all_channel_functions/1`.
  """
  @spec generate_all_channel_types([{module(), String.t()}]) :: String.t()
  def generate_all_channel_types(channel_entries) do
    channel_data = collect_all_channel_data(channel_entries)

    if Enum.empty?(channel_data) do
      ""
    else
      all_events = Enum.flat_map(channel_data, fn {_, _, events} -> events end)
      validate_no_payload_type_conflicts!(all_events, channel_data)

      shared_payload_types =
        all_events
        |> Enum.uniq_by(fn %{payload_type_name: name} -> name end)
        |> Enum.sort_by(fn %{payload_type_name: name} -> name end)
        |> Enum.map_join("\n", fn %{payload_type_name: name, ts_type: ts_type} ->
          "export type #{name} = #{ts_type};"
        end)

      per_channel_blocks =
        Enum.map_join(channel_data, "\n\n", fn {mod, _topic, event_data} ->
          channel_name = module_to_channel_name(mod)
          comment = "// Channel types for #{inspect(mod)}"
          brand_type = build_channel_brand_type(channel_name)
          events_map = build_events_map_type(channel_name, event_data)
          handlers_type = build_handlers_type(channel_name)
          refs_type = build_refs_type(channel_name)

          [comment, brand_type, events_map, handlers_type, refs_type]
          |> Enum.join("\n\n")
        end)

      [shared_payload_types, per_channel_blocks]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n\n")
    end
  end

  @doc """
  Generates TypeScript subscription helper functions for all configured typed channel modules.

  Accepts a list of `{module, topic}` tuples. Emits, per channel:
  - `createOrgChannel` factory (uses the topic pattern to construct the Phoenix topic string)
  - `onOrgChannelMessage` single-event subscription
  - `onOrgChannelMessages` multi-event subscription
  - `unsubscribeOrgChannel` cleanup

  Returns only the function bodies without import statements. The caller is
  responsible for prepending imports from `ash_types.ts`.
  """
  @spec generate_all_channel_functions([{module(), String.t()}]) :: String.t()
  def generate_all_channel_functions(channel_entries) do
    channel_data = collect_all_channel_data(channel_entries)

    if Enum.empty?(channel_data) do
      ""
    else
      Enum.map_join(channel_data, "\n\n", fn {mod, topic, _event_data} ->
        channel_name = module_to_channel_name(mod)

        [
          build_channel_factory(channel_name, topic),
          build_subscription_function(channel_name),
          build_on_messages_function(channel_name),
          build_off_messages_function(channel_name)
        ]
        |> Enum.join("\n\n")
      end)
    end
  end

  @doc """
  Generates TypeScript type declarations for a single typed channel module.

  The optional `topic` (e.g. `"org:*"`) causes a branded `OrgChannel` type to be
  emitted. Without a topic only payload aliases, the events map, and utility types
  are emitted — useful for isolated unit tests.
  """
  @spec generate_channel_types(module(), String.t() | nil) :: String.t()
  def generate_channel_types(channel_module, topic \\ nil) do
    channel_resources = Info.typed_channel(channel_module)

    if Enum.empty?(channel_resources) do
      ""
    else
      channel_name = module_to_channel_name(channel_module)
      event_data = collect_event_data(channel_resources)

      if Enum.empty?(event_data) do
        ""
      else
        comment = "// Channel types for #{inspect(channel_module)}"

        payload_types =
          event_data
          |> Enum.sort_by(fn %{payload_type_name: name} -> name end)
          |> Enum.map_join("\n", fn %{payload_type_name: name, ts_type: ts_type} ->
            "export type #{name} = #{ts_type};"
          end)

        brand_type = if topic, do: build_channel_brand_type(channel_name), else: nil
        events_map = build_events_map_type(channel_name, event_data)
        handlers_type = build_handlers_type(channel_name)
        refs_type = build_refs_type(channel_name)

        [comment, payload_types, brand_type, events_map, handlers_type, refs_type]
        |> Enum.reject(&(is_nil(&1) or &1 == ""))
        |> Enum.join("\n\n")
      end
    end
  end

  @doc """
  Generates TypeScript subscription helper functions for a single typed channel module.

  The optional `topic` causes a `create*` factory to be emitted and function
  signatures to use the branded channel type instead of a structural type.
  """
  @spec generate_channel_functions(module(), String.t() | nil) :: String.t()
  def generate_channel_functions(channel_module, topic \\ nil) do
    channel_resources = Info.typed_channel(channel_module)

    if Enum.empty?(channel_resources) do
      ""
    else
      channel_name = module_to_channel_name(channel_module)
      event_data = collect_event_data(channel_resources)

      if Enum.empty?(event_data) do
        ""
      else
        fns = [
          if(topic, do: build_channel_factory(channel_name, topic)),
          build_subscription_function(channel_name),
          build_on_messages_function(channel_name),
          build_off_messages_function(channel_name)
        ]

        fns
        |> Enum.reject(&is_nil/1)
        |> Enum.join("\n\n")
      end
    end
  end

  defp collect_all_channel_data(channel_entries) do
    channel_entries
    |> Enum.map(fn {mod, topic} ->
      resources = Info.typed_channel(mod)
      {mod, topic, collect_event_data(resources)}
    end)
    |> Enum.reject(fn {_, _, events} -> Enum.empty?(events) end)
  end

  defp collect_event_data(channel_resources) do
    channel_resources
    |> Enum.sort_by(fn cr -> inspect(cr.module) end)
    |> Enum.flat_map(fn channel_resource ->
      resource_module = channel_resource.module
      publications = Ash.Notifier.PubSub.Info.publications(resource_module)

      channel_resource.publications
      |> Enum.map(fn pub ->
        event_str = to_string(pub.event)
        matching_pub = find_publication(publications, event_str)

        ts_type = resolve_payload_type(matching_pub, resource_module)

        %{
          event: event_str,
          ts_type: ts_type,
          payload_type_name: event_to_payload_type_name(event_str)
        }
      end)
      |> Enum.sort_by(fn %{event: event} -> event end)
    end)
  end

  defp resolve_payload_type(nil, _resource_module), do: "unknown"

  defp resolve_payload_type(%{returns: returns} = pub, _resource_module)
       when not is_nil(returns) do
    TypeMapper.map_channel_payload_type(returns, pub.constraints || [])
  end

  defp resolve_payload_type(%{transform: calc_name}, resource_module)
       when is_atom(calc_name) and not is_nil(calc_name) do
    case Ash.Resource.Info.calculation(resource_module, calc_name) do
      %{type: type, constraints: constraints} when not is_nil(type) ->
        TypeMapper.map_channel_payload_type(type, constraints)

      _ ->
        "unknown"
    end
  end

  defp resolve_payload_type(_, _), do: "unknown"

  defp build_channel_brand_type(channel_name) do
    """
    export type #{channel_name} = {
      readonly __channelType: "#{channel_name}";
      on(event: string, callback: (payload: unknown) => void): number;
      off(event: string, ref: number): void;
    };\
    """
  end

  defp build_channel_factory(channel_name, topic) do
    case String.split(topic, "*", parts: 2) do
      [prefix, _] ->
        """
        export function create#{channel_name}(
          socket: { channel(topic: string, params?: object): unknown },
          suffix: string
        ): #{channel_name} {
          return socket.channel(`#{prefix}${suffix}`) as #{channel_name};
        }\
        """

      [full_topic] ->
        """
        export function create#{channel_name}(
          socket: { channel(topic: string, params?: object): unknown }
        ): #{channel_name} {
          return socket.channel("#{full_topic}") as #{channel_name};
        }\
        """
    end
  end

  defp build_events_map_type(channel_name, event_data) do
    entries =
      Enum.map_join(event_data, "\n  ", fn %{event: event, payload_type_name: payload_name} ->
        "#{event}: #{payload_name};"
      end)

    """
    export type #{channel_name}Events = {
      #{entries}
    };\
    """
  end

  defp build_handlers_type(channel_name) do
    """
    export type #{channel_name}Handlers = {
      [E in keyof #{channel_name}Events]?: (payload: #{channel_name}Events[E]) => void;
    };\
    """
  end

  defp build_refs_type(channel_name) do
    """
    export type #{channel_name}Refs = {
      [E in keyof #{channel_name}Events]?: number;
    };\
    """
  end

  defp build_subscription_function(channel_name) do
    """
    export function on#{channel_name}Message<E extends keyof #{channel_name}Events>(
      channel: #{channel_name},
      event: E,
      handler: (payload: #{channel_name}Events[E]) => void
    ): number {
      return channel.on(event, (payload: unknown) => handler(payload as #{channel_name}Events[E]));
    }\
    """
  end

  defp build_on_messages_function(channel_name) do
    """
    export function on#{channel_name}Messages(
      channel: #{channel_name},
      handlers: #{channel_name}Handlers
    ): #{channel_name}Refs {
      const refs: #{channel_name}Refs = {};
      for (const event in handlers) {
        const e = event as keyof #{channel_name}Events;
        const handler = handlers[e];
        if (handler) {
          refs[e] = channel.on(event, (payload) => (handler as (p: unknown) => void)(payload));
        }
      }
      return refs;
    }\
    """
  end

  defp build_off_messages_function(channel_name) do
    """
    export function unsubscribe#{channel_name}(
      channel: #{channel_name},
      refs: #{channel_name}Refs
    ): void {
      for (const event in refs) {
        const e = event as keyof #{channel_name}Refs;
        const ref = refs[e];
        if (ref !== undefined) {
          channel.off(event, ref);
        }
      }
    }\
    """
  end

  defp validate_no_payload_type_conflicts!(all_events, channel_data) do
    conflicts =
      all_events
      |> Enum.group_by(fn %{payload_type_name: name} -> name end)
      |> Enum.filter(fn {_name, events} ->
        events |> Enum.map(& &1.ts_type) |> Enum.uniq() |> length() > 1
      end)

    unless conflicts == [] do
      details =
        Enum.map_join(conflicts, "\n\n", fn {type_name, events} ->
          variants =
            events
            |> Enum.uniq_by(& &1.ts_type)
            |> Enum.map_join("\n", fn %{event: event, ts_type: ts_type} ->
              channels =
                channel_data
                |> Enum.filter(fn {_, _, evts} -> Enum.any?(evts, &(&1.event == event)) end)
                |> Enum.map_join(", ", fn {mod, _, _} -> inspect(mod) end)

              "    event #{inspect(event)} (in #{channels}) → #{ts_type}"
            end)

          "  #{type_name}:\n#{variants}"
        end)

      raise """
      Payload type name conflict detected across typed channels.

      The following events produce the same TypeScript type name but map to different types:

      #{details}

      Rename the conflicting events so each event name maps to a unique payload type, \
      or ensure they return the same type.
      """
    end
  end

  defp module_to_channel_name(module) do
    module |> Module.split() |> List.last()
  end

  defp event_to_payload_type_name(event_str) do
    event_str
    |> Macro.camelize()
    |> then(&"#{&1}Payload")
  end

  defp find_publication(publications, event_str) do
    Enum.find(publications, fn pub ->
      event_name = pub.event || pub.action
      to_string(event_name) == event_str
    end)
  end
end
