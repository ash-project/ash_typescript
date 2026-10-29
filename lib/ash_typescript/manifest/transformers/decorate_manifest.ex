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

  Between the two, `AshTypescript.Manifest.TypedRoutes` decorates the typed
  controller routes and typed channel publications `BuildManifest` persisted,
  and stores them under `custom.ash_typescript.routes` / `.publications`.
  The `custom_types` declarations and built-ins `NormalizeCustomTypes`
  persisted are stored beside them, under `custom.ash_typescript.custom_types`.

  Both decorations get the same `custom_type_fields:` closure over those
  declarations and built-ins (`AshTypescript.CustomTypes.fields_for/3`), and
  the route and publication types go to ash_rpc's decorator as
  `extra_types:`, so their declared custom types get definitions in
  `manifest.types`. The rejection of an undeclared map-like custom type (RPC
  actions, typed queries, routes and publications) carries the hint closed
  over the same declarations (`AshTypescript.CustomTypes.hint/3`), so it
  also says to remove a `scalar` entry that covers the type.
  `AshTypescript.Manifest.Decorator` gets the declarations too, for the
  names of the aliases and schemas of declared custom types and of the
  field-bearing NewTypes that opt into an alias. A `typescript_type_alias/0`
  that returns no valid alias, and an aliased field-bearing NewType that
  exports `typescript_type/0` (named by `typescript_type_alias/0`), are a
  `Spark.Error.DslError`
  (`AshTypescript.CustomTypes.check_alias_names/2`). So is, checked first, a
  reached type module exporting `typescript_type_name/0` or
  `typescript_alias_name/0`, the callbacks' former names: the error names
  `typescript_type/0` / `typescript_type_alias/0`
  (`AshTypescript.CustomTypes.check_renamed_callbacks/1`).
  """

  use Spark.Dsl.Transformer

  alias AshTypescript.Manifest.Custom
  alias AshTypescript.Manifest.Decorator
  alias AshTypescript.Manifest.TypedRoutes
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
        custom_types = Transformer.get_persisted(dsl_state, :custom_types)
        fields_fun = AshTypescript.CustomTypes.fields_fun(custom_types)
        hint_fun = AshTypescript.CustomTypes.hint_fun(custom_types)
        routes = Transformer.get_persisted(dsl_state, :typed_routes, [])
        publications = Transformer.get_persisted(dsl_state, :typed_publications, [])

        rpc_decorated =
          manifest
          |> AshRpc.Manifest.Decorator.decorate(AshTypescript.RpcMappingSource,
            custom_type_fields: fields_fun,
            custom_type_fields_hint: hint_fun,
            extra_types: TypedRoutes.types(routes, publications)
          )
          |> TypedRoutes.decorate(routes, publications, fields_fun, hint_fun)

        with :ok <- check_renamed_callbacks(dsl_state, rpc_decorated),
             :ok <- check_alias_names(dsl_state, rpc_decorated, custom_types) do
          decorated =
            rpc_decorated
            |> Decorator.decorate(hint: hint_fun, custom_types: custom_types)
            |> put_custom_types(custom_types)
            |> AshRpc.Manifest.put_lookups()

          {:ok, persist(dsl_state, decorated, custom_types)}
        end
    end
  end

  defp persist(dsl_state, decorated, custom_types) do
    dsl_state
    |> track_type_modules(decorated, custom_types)
    |> Transformer.persist(:manifest, decorated)
    |> Transformer.persist(:resource_lookup, AshRpc.Manifest.resource_lookup(decorated))
    |> Transformer.persist(:action_lookup, AshRpc.Manifest.action_lookup(decorated))
    |> Transformer.persist(:type_lookup, AshRpc.Manifest.type_lookup(decorated))
    |> Transformer.persist(:typed_query_lookup, build_typed_query_lookup(decorated))
  end

  defp check_renamed_callbacks(dsl_state, manifest) do
    with {:error, message} <- AshTypescript.CustomTypes.check_renamed_callbacks(manifest),
         do: dsl_error(dsl_state, message)
  end

  defp check_alias_names(dsl_state, manifest, custom_types) do
    with {:error, message} <- AshTypescript.CustomTypes.check_alias_names(manifest, custom_types),
         do: dsl_error(dsl_state, message)
  end

  defp dsl_error(dsl_state, message) do
    {:error,
     Spark.Error.DslError.exception(
       module: Transformer.get_persisted(dsl_state, :module),
       path: [:custom_types],
       message: message
     )}
  end

  # Each type module whose `typescript_fields/0` or `composite_types/1`
  # supplied a declared custom type's fields, or whose
  # `typescript_type_alias/0` its alias, and every NewType definition in the
  # manifest gets a compile-time edge, so the manifest recompiles when it
  # changes (adding `typescript_type_alias/0` to a NewType later included).
  # Such modules must never read the manifest at compile time: it depends on
  # them.
  defp track_type_modules(dsl_state, manifest, %{declared: declared, builtin: builtin}) do
    manifest
    |> AshTypescript.CustomTypes.compile_dependencies(declared, builtin)
    |> Enum.reduce(dsl_state, fn module, dsl_state ->
      Transformer.eval(dsl_state, [], quote(do: _ = unquote(module).module_info(:md5)))
    end)
  end

  # The `custom_types` declarations and built-ins `NormalizeCustomTypes`
  # persisted, read through `Custom.declared_custom_type/2` and
  # `Custom.builtin_custom_type/2`.
  defp put_custom_types(%Ash.Info.Manifest{} = manifest, custom_types) do
    data = %{custom_types: custom_types}
    custom = Map.update(manifest.custom, :ash_typescript, data, &Map.merge(&1, data))
    %Ash.Info.Manifest{manifest | custom: custom}
  end

  # Typed-query entrypoints keyed by name (as a string), read through
  # `AshTypescript.typed_query_lookup/1`. The runtime doesn't use it: ash_rpc
  # resolves wire entrypoints from its own `custom.ash_rpc` lookups.
  defp build_typed_query_lookup(%Ash.Info.Manifest{entrypoints: entrypoints}) do
    Enum.reduce(entrypoints, %{}, fn entrypoint, acc ->
      case Custom.typed_query(entrypoint) do
        nil -> acc
        typed_query -> Map.put(acc, to_string(typed_query.name), entrypoint)
      end
    end)
  end
end
