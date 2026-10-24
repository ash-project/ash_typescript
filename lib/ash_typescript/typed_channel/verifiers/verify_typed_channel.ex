# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.TypedChannel.Verifiers.VerifyTypedChannel do
  @moduledoc """
  Verifies that typed channel configurations are valid.

  Checks:
  1. All declared events exist as publications on their respective resources.
  2. Event names are unique across all resources in the channel.
  3. Publications whose `returns` type is known are pushed as a JSON object.
     Phoenix only pushes map payloads (`Phoenix.Socket.V2.JSONSerializer`
     raises for anything else), so a string, number, boolean, date, atom, enum
     or array payload would crash the channel when broadcast. Maps, structs,
     resources, embedded resources, unions, keywords and tuples (and NewTypes
     of them) are all formatted to a map before the push. Types whose shape is
     not known (`:term`, hand-rolled custom types) are not checked.
  4. Publications are marked `public?: true` (warning if not).
  5. Publications have `returns` set — either auto-derived via `transform :calc`
     or explicitly declared (warning if not — TypeScript type falls back to `unknown`).

  Checks 1 to 3 are hard errors. Checks 4 and 5 write to stderr and are each
  gated by an application-level toggle (mirroring `VerifyRpcWarnings`):

    * `config :ash_typescript, warn_on_non_public_publications: true` (default)
    * `config :ash_typescript, warn_on_missing_channel_returns: true` (default)

  Checks 4 and 5 deliberately use `IO.puts(:stderr, ...)` rather than `IO.warn/1`.
  This verifier runs during compilation of the channel module, where `IO.warn/1`
  would register a compiler diagnostic and so fail `mix compile
  --warnings-as-errors`. A non-`public?` publication or a missing `returns` may
  well be intentional, so it must not break the build.
  """

  use Spark.Dsl.Verifier

  alias Ash.Info.Manifest.Generator.TypeResolver
  alias AshTypescript.TypedChannel.Info

  # Resolved type kinds that `ValueFormatter` turns into a map on output.
  @object_kinds [:map, :struct, :keyword, :tuple, :resource, :embedded_resource, :union]

  # Kinds whose runtime shape is not known from the type, so they cannot be
  # refused (`:unknown` covers hand-rolled custom types).
  @unknown_shape_kinds [:term, :any, :unknown]

  @impl true
  def verify(dsl) do
    channel_resources = Spark.Dsl.Verifier.get_entities(dsl, [:typed_channel])
    channel = Spark.Dsl.Verifier.get_persisted(dsl, :module)

    with :ok <- verify_events_exist(channel_resources),
         :ok <- verify_unique_event_names(channel_resources),
         :ok <- verify_object_payloads(channel_resources, channel) do
      warn_missing_returns(channel_resources)
      :ok
    end
  end

  defp verify_events_exist(channel_resources) do
    errors =
      Enum.flat_map(channel_resources, fn channel_resource ->
        resource_module = channel_resource.module
        publications = Ash.Notifier.PubSub.Info.publications(resource_module)

        Enum.flat_map(channel_resource.publications, fn pub ->
          event_str = to_string(pub.event)

          if Info.find_publication(publications, event_str) do
            []
          else
            [
              Spark.Error.DslError.exception(
                message: """
                No publication with event #{inspect(pub.event)} found on #{inspect(resource_module)}.

                Make sure the resource has a `publish` or `publish_all` entry with \
                `event: #{inspect(pub.event)}` in its `pub_sub` block.
                """
              )
            ]
          end
        end)
      end)

    case errors do
      [] -> :ok
      [error | _] -> {:error, error}
    end
  end

  defp verify_unique_event_names(channel_resources) do
    all_events =
      Enum.flat_map(channel_resources, fn channel_resource ->
        Enum.map(channel_resource.publications, fn pub -> to_string(pub.event) end)
      end)

    duplicates =
      all_events
      |> Enum.frequencies()
      |> Enum.filter(fn {_, count} -> count > 1 end)
      |> Enum.map(fn {event, _} -> event end)

    if duplicates == [] do
      :ok
    else
      {:error,
       Spark.Error.DslError.exception(
         message: """
         Duplicate event names found in typed_channel: #{Enum.join(duplicates, ", ")}.

         Each event name must be unique across all resources in a single channel.
         """
       )}
    end
  end

  defp verify_object_payloads(channel_resources, channel) do
    channel_resources
    |> Enum.flat_map(fn channel_resource ->
      resource_module = channel_resource.module
      publications = Ash.Notifier.PubSub.Info.publications(resource_module)

      Enum.flat_map(channel_resource.publications, fn pub ->
        case Info.find_publication(publications, to_string(pub.event)) do
          %{returns: returns} = matching_pub when not is_nil(returns) ->
            if object_payload?(TypeResolver.resolve(returns, matching_pub.constraints || [])) do
              []
            else
              [{pub, resource_module, returns}]
            end

          _ ->
            []
        end
      end)
    end)
    |> case do
      [] ->
        :ok

      [{pub, resource_module, returns} | _] ->
        {:error, non_object_error(pub, resource_module, returns, channel)}
    end
  end

  defp object_payload?(%{kind: :type_ref, module: module}),
    do: object_payload?(TypeResolver.resolve_definition(module))

  defp object_payload?(%{kind: kind}), do: kind in @object_kinds or kind in @unknown_shape_kinds

  defp non_object_error(pub, resource_module, returns, channel) do
    Spark.Error.DslError.exception(
      module: channel,
      path: [:typed_channel, :resource, :publish, pub.event],
      location: Spark.Dsl.Entity.anno(pub),
      message: """
      Event #{inspect(pub.event)} on #{inspect(resource_module)} in typed channel \
      #{inspect(channel)} has payload type #{inspect(Ash.Type.get_type(returns))}, \
      which is not pushed as a JSON object.

      Phoenix channels can only push map payloads, so broadcasting this event \
      would raise and crash every subscribed channel. Return a map instead, for \
      example a calculation such as `calculate :title_payload, :auto, \
      expr(%{title: title})` used as `transform: :title_payload`, or \
      `returns: :map` with `fields` constraints.
      """
    )
  end

  defp warn_missing_returns(channel_resources) do
    warn_non_public? = AshTypescript.warn_on_non_public_publications?()
    warn_missing_returns? = AshTypescript.warn_on_missing_channel_returns?()

    if warn_non_public? or warn_missing_returns? do
      {non_public, missing_returns} = collect_publication_warnings(channel_resources)

      if warn_non_public? and non_public != [] do
        IO.puts(:stderr, build_non_public_warning(non_public))
      end

      if warn_missing_returns? and missing_returns != [] do
        IO.puts(:stderr, build_missing_returns_warning(missing_returns))
      end
    end

    :ok
  end

  # Walks every declared publication once and buckets the offenders by warning
  # kind, so each kind can be reported as a single grouped block rather than one
  # line per publication.
  defp collect_publication_warnings(channel_resources) do
    Enum.reduce(channel_resources, {[], []}, fn channel_resource, acc ->
      resource_module = channel_resource.module
      publications = Ash.Notifier.PubSub.Info.publications(resource_module)

      Enum.reduce(channel_resource.publications, acc, fn pub, {non_public, missing_returns} ->
        case Info.find_publication(publications, to_string(pub.event)) do
          nil ->
            {non_public, missing_returns}

          matching_pub ->
            non_public =
              if matching_pub.public?,
                do: non_public,
                else: [{resource_module, pub.event} | non_public]

            missing_returns =
              if is_nil(matching_pub.returns),
                do: [{resource_module, pub.event} | missing_returns],
                else: missing_returns

            {non_public, missing_returns}
        end
      end)
    end)
  end

  defp build_non_public_warning(entries) do
    build_warning_block(
      "⚠️  Found typed channel publications that are not marked `public?: true`:",
      entries,
      [
        "   Each publication listed above is referenced by a typed_channel but",
        "   is not marked `public?: true` in its resource's `pub_sub` block.",
        "   Consider adding `public?: true` to the publication.",
        "",
        "   Otherwise, you can ignore this warning."
      ]
    )
  end

  defp build_missing_returns_warning(entries) do
    build_warning_block(
      "⚠️  Found typed channel publications with no `returns` type:",
      entries,
      [
        "   Each publication listed above does not have `returns` set, so its",
        "   generated TypeScript payload type falls back to `unknown`.",
        "",
        "   Use `transform :some_calc` with an `:auto`-typed calculation",
        "   (recommended), or add explicit `returns: SomeAshType` to get a typed",
        "   payload."
      ]
    )
  end

  # Mirrors the layout of `AshTypescript.Codegen.TypeDiscovery`'s RPC warnings:
  # a header, offenders grouped one bullet per resource, then the explanation.
  defp build_warning_block(header, entries, explanation_lines) do
    entry_lines =
      entries
      |> Enum.reverse()
      |> Enum.group_by(fn {resource, _event} -> resource end, fn {_resource, event} -> event end)
      |> Enum.sort_by(fn {resource, _events} -> inspect(resource) end)
      |> Enum.flat_map(fn {resource, events} ->
        ["   • #{inspect(resource)}"] ++
          Enum.map(Enum.uniq(events), &"       - #{&1}") ++ [""]
      end)

    # Trailing "" keeps consecutive blocks (and anything printed after) visually
    # separated, matching the "\n\n" join the RPC warnings use.
    ([header, ""] ++ entry_lines ++ explanation_lines ++ [""]) |> Enum.join("\n")
  end
end
