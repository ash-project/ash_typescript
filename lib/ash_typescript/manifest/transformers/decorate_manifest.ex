# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.Transformers.DecorateManifest do
  @moduledoc """
  Runs after `BuildManifest` and decorates the persisted `%Ash.Info.Manifest{}`
  with ash_typescript-specific metadata.

  After this transformer, every persisted lookup — `:manifest`,
  `:resource_lookup`, `:action_lookup`, `:type_lookup` — refers to the
  *decorated* spec. Downstream readers (verifiers, runtime, codegen) should
  pull the manifest and lookups from here.

  The manifest is decorated twice: `AshRpc.Manifest.Decorator` (driven by
  `AshTypescript.RpcMappingSource`) writes `custom.ash_rpc`, then
  `AshTypescript.Manifest.Decorator` writes `custom.ash_typescript`. The
  embedded `custom.ash_rpc.lookups` are rebuilt last so they carry both.
  """

  use Spark.Dsl.Transformer

  alias AshTypescript.Manifest.Custom
  alias AshTypescript.Manifest.Decorator
  alias Spark.Dsl.Transformer

  @impl true
  def after?(AshTypescript.Manifest.Transformers.BuildManifest), do: true
  def after?(_), do: false

  @impl true
  def transform(dsl_state) do
    case Transformer.get_persisted(dsl_state, :manifest) do
      nil ->
        {:ok, dsl_state}

      manifest ->
        decorated =
          manifest
          |> AshRpc.Manifest.Decorator.decorate(AshTypescript.RpcMappingSource)
          |> Decorator.decorate()
          |> AshRpc.Manifest.put_lookups()

        dsl_state =
          dsl_state
          |> Transformer.persist(:manifest, decorated)
          |> Transformer.persist(:resource_lookup, AshRpc.Manifest.resource_lookup(decorated))
          |> Transformer.persist(:action_lookup, AshRpc.Manifest.action_lookup(decorated))
          |> Transformer.persist(:type_lookup, AshRpc.Manifest.type_lookup(decorated))
          |> Transformer.persist(:rpc_action_lookup, build_rpc_action_lookup(decorated))
          |> Transformer.persist(:typed_query_lookup, build_typed_query_lookup(decorated))

        {:ok, dsl_state}
    end
  end

  # Entrypoint lookups keyed by the client-facing action / typed-query name (as a
  # string), read through `AshTypescript.rpc_action_lookup/1` and
  # `typed_query_lookup/1`. The runtime doesn't use them: ash_rpc resolves wire
  # entrypoints from its own `custom.ash_rpc` lookups.
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
end
