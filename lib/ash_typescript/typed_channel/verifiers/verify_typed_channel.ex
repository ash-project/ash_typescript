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

  Checks 1 and 2 are hard errors. Check 3 writes to stderr and is gated by an
  application-level toggle (mirroring `VerifyRpcWarnings`):

    * `config :ash_typescript, warn_on_non_public_publications: true` (default)

  Check 3 deliberately uses `IO.puts(:stderr, ...)` rather than `IO.warn/1`.
  This verifier runs during compilation of the channel module, where `IO.warn/1`
  would register a compiler diagnostic and so fail `mix compile
  --warnings-as-errors`. A non-`public?` publication may well be intentional,
  so it must not break the build.

  A publication's `returns` (required, a typed map) is checked when the
  manifest compiles (`AshTypescript.Manifest.PlainData`).
  """

  use Spark.Dsl.Verifier

  alias AshTypescript.TypedChannel.Info

  @impl true
  def verify(dsl) do
    channel_resources = Spark.Dsl.Verifier.get_entities(dsl, [:typed_channel])

    with :ok <- verify_events_exist(channel_resources),
         :ok <- verify_unique_event_names(channel_resources) do
      warn_non_public(channel_resources)
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

  defp warn_non_public(channel_resources) do
    if AshTypescript.warn_on_non_public_publications?() do
      case non_public_publications(channel_resources) do
        [] -> :ok
        non_public -> IO.puts(:stderr, build_non_public_warning(non_public))
      end
    end

    :ok
  end

  # Every declared publication that isn't `public?`, so they can be reported as
  # a single grouped block rather than one line per publication.
  defp non_public_publications(channel_resources) do
    Enum.reduce(channel_resources, [], fn channel_resource, acc ->
      resource_module = channel_resource.module
      publications = Ash.Notifier.PubSub.Info.publications(resource_module)

      Enum.reduce(channel_resource.publications, acc, fn pub, non_public ->
        case Info.find_publication(publications, to_string(pub.event)) do
          nil -> non_public
          %{public?: true} -> non_public
          _not_public -> [{resource_module, pub.event} | non_public]
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
