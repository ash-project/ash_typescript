# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.TypedChannel.Verifiers.VerifyTypedChannel do
  @moduledoc """
  Verifies that typed channel configurations are valid.

  Checks:
  1. All declared events exist as publications on their respective resources.
  2. Event names are unique across all resources in the channel.
  3. Publications are marked `public?: true` (warning if not).
  4. Publications have `returns` set — either auto-derived via `transform :calc`
     or explicitly declared (warning if not — TypeScript type falls back to `unknown`).

  Checks 1 and 2 are hard errors. Checks 3 and 4 write to stderr and are each
  gated by an application-level toggle (mirroring `VerifyRpcWarnings`):

    * `config :ash_typescript, warn_on_non_public_publications: true` (default)
    * `config :ash_typescript, warn_on_missing_channel_returns: true` (default)

  Checks 3 and 4 deliberately use `IO.puts(:stderr, ...)` rather than `IO.warn/1`.
  This verifier runs during compilation of the channel module, where `IO.warn/1`
  would register a compiler diagnostic and so fail `mix compile
  --warnings-as-errors`. A non-`public?` publication or a missing `returns` may
  well be intentional, so it must not break the build.
  """

  use Spark.Dsl.Verifier

  @impl true
  def verify(dsl) do
    channel_resources = Spark.Dsl.Verifier.get_entities(dsl, [:typed_channel])

    with :ok <- verify_events_exist(channel_resources),
         :ok <- verify_unique_event_names(channel_resources) do
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

          if find_publication(publications, event_str) do
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
        case find_publication(publications, to_string(pub.event)) do
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

  defp find_publication(publications, event_str) do
    Enum.find(publications, fn pub ->
      event_name = pub.event || pub.action
      to_string(event_name) == event_str
    end)
  end
end
