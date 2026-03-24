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
    Enum.each(channel_resources, fn channel_resource ->
      resource_module = channel_resource.module
      publications = Ash.Notifier.PubSub.Info.publications(resource_module)

      Enum.each(channel_resource.publications, fn pub ->
        event_str = to_string(pub.event)
        matching_pub = find_publication(publications, event_str)

        if matching_pub do
          unless matching_pub.public? do
            IO.warn(
              "Publication #{inspect(pub.event)} on #{inspect(resource_module)} is not marked " <>
                "`public?: true`. Consider adding `public?: true` to the publication."
            )
          end

          unless matching_pub.returns do
            IO.warn(
              "Publication #{inspect(pub.event)} on #{inspect(resource_module)} does not have " <>
                "`returns` set. The TypeScript payload type will be `unknown`. " <>
                "Use `transform :some_calc` with an `:auto`-typed calculation (recommended), " <>
                "or add explicit `returns: SomeAshType` to get a typed payload."
            )
          end
        end
      end)
    end)
  end

  defp find_publication(publications, event_str) do
    Enum.find(publications, fn pub ->
      event_name = pub.event || pub.action
      to_string(event_name) == event_str
    end)
  end
end
