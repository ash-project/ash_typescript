# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.TypedChannel.Info do
  @moduledoc """
  Provides introspection functions for AshTypescript.TypedChannel configuration
  and for the `Ash.Notifier.PubSub` publications typed channels reference.
  """

  use Spark.InfoGenerator,
    extension: AshTypescript.TypedChannel.Dsl,
    sections: [:typed_channel]

  @doc """
  Finds the `Ash.Notifier.PubSub` publication matching `event`.

  Accepts either the resource module or an already-fetched publication list.
  Matching falls back to the action name for publications with no `event:`.
  """
  @spec find_publication(module() | [struct()], String.t()) :: struct() | nil
  def find_publication(resource, event) when is_atom(resource) do
    resource
    |> Ash.Notifier.PubSub.Info.publications()
    |> find_publication(event)
  end

  def find_publication(publications, event) when is_list(publications) do
    Enum.find(publications, fn pub -> to_string(pub.event || pub.action) == event end)
  end

  @doc "Whether or not a given module uses the AshTypescript.TypedChannel DSL."
  @spec typed_channel?(module()) :: boolean()
  def typed_channel?(module) when is_atom(module) do
    Spark.Dsl.is?(module, AshTypescript.TypedChannel)
  rescue
    _ -> false
  end
end
