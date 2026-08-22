# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.Transformers.DecorateAppSpec do
  @moduledoc """
  Runs after `BuildAppSpec` and decorates the persisted `%Ash.Info.Manifest{}`
  with ash_typescript-specific metadata.

  After this transformer, every persisted lookup — `:manifest`,
  `:resource_lookup`, `:action_lookup`, `:type_lookup` — refers to the
  *decorated* spec. Downstream readers (verifiers, runtime, codegen) should
  pull the manifest and lookups from here.

  See `AshTypescript.Manifest.Decorator` for what gets decorated.
  """

  use Spark.Dsl.Transformer

  alias AshTypescript.Manifest.Custom
  alias AshTypescript.Manifest.Decorator
  alias Spark.Dsl.Transformer

  @impl true
  def after?(AshTypescript.Manifest.Transformers.BuildAppSpec), do: true
  def after?(_), do: false

  @impl true
  def transform(dsl_state) do
    case Transformer.get_persisted(dsl_state, :manifest) do
      nil ->
        {:ok, dsl_state}

      manifest ->
        decorated = Decorator.decorate(manifest)

        dsl_state =
          dsl_state
          |> Transformer.persist(:manifest, decorated)
          |> Transformer.persist(:resource_lookup, build_resource_lookup(decorated))
          |> Transformer.persist(:action_lookup, Ash.Info.Manifest.action_lookup(decorated))
          |> Transformer.persist(:type_lookup, Ash.Info.Manifest.type_lookup(decorated))
          |> Transformer.persist(:rpc_action_lookup, build_rpc_action_lookup(decorated))
          |> Transformer.persist(:typed_query_lookup, build_typed_query_lookup(decorated))

        {:ok, dsl_state}
    end
  end

  # O(1) entrypoint lookups keyed by the client-facing action / typed-query name
  # (as a string). Replaces per-request linear scans over `manifest.entrypoints`
  # in the runtime pipeline's `discover_action`.
  defp build_rpc_action_lookup(%Ash.Info.Manifest{entrypoints: entrypoints}) do
    Enum.reduce(entrypoints, %{}, fn entrypoint, acc ->
      case Custom.rpc_action(entrypoint) do
        nil -> acc
        rpc_action -> Map.put(acc, to_string(rpc_action.name), entrypoint)
      end
    end)
  end

  defp build_typed_query_lookup(%Ash.Info.Manifest{entrypoints: entrypoints}) do
    Enum.reduce(entrypoints, %{}, fn entrypoint, acc ->
      case Custom.typed_query(entrypoint) do
        nil -> acc
        typed_query -> Map.put(acc, to_string(typed_query.name), entrypoint)
      end
    end)
  end

  # Ash 3.25.2+ moved embedded resources from `manifest.resources` into
  # `manifest.types` (as `kind: :embedded_resource` entries with the definition
  # in `type.resource`). ash_typescript treats them uniformly with domain
  # resources for schema generation, so this merges them back into the lookup.
  defp build_resource_lookup(api_spec) do
    base = Ash.Info.Manifest.resource_lookup(api_spec)

    embedded =
      api_spec.types
      |> Enum.filter(fn type ->
        match?(%Ash.Info.Manifest.Type{kind: :embedded_resource, resource: %_{}}, type)
      end)
      |> Map.new(fn %{module: mod, resource: resource} -> {mod, resource} end)

    Map.merge(embedded, base)
  end
end
