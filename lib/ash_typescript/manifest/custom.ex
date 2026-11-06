# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.Custom do
  @moduledoc """
  Thin accessor module for reading decoration persisted on Ash.Info.Manifest
  structs.

  ash_typescript-owned (codegen) data lives under `custom.ash_typescript`,
  written by `AshTypescript.Manifest.Decorator`. Client names, argument
  overrides, relationship query capabilities and action precomputation live
  under `custom.ash_rpc` (written by `AshRpc.Manifest.Decorator`): codegen
  reads client names through `Codegen.ClientNames`, and the rest
  through `AshRpc.Manifest.Custom` (`relationship_pagination/1` and
  `action_return_classification/1` here delegate to it). Callers should
  prefer these accessors over walking Spark DSL state — the manifest carries
  pre-computed lookups that are O(1) map reads.

  All accessors return `nil` (or sensible empty defaults) when the struct has
  no decoration, so callers can pattern-match on `nil`.
  """

  alias Ash.Info.Manifest
  alias AshTypescript.Manifest.{Publication, Route}

  @typedoc """
  The decoration map persisted under `custom.ash_typescript` on a
  `%Manifest.Resource{}` (including embedded resources nested under a `%Manifest.Type{}`).
  """
  @type resource_custom :: %{optional(:type_name) => String.t() | nil}

  @typedoc """
  The decoration map persisted under `custom.ash_typescript` on a
  `%Manifest.Type{}`: the `type_name` of NewTypes/TypedStructs that export
  `typescript_field_names/0` or `typescript_type/0`, and the
  `type_alias_names` of an aliased map-like type.
  """
  @type type_custom :: %{
          optional(:type_name) => String.t() | nil,
          optional(:type_alias_names) => AshTypescript.CustomTypes.names()
        }

  @typedoc """
  The decoration map persisted under `custom.ash_typescript` on a
  `%Manifest.Entrypoint{}`.
  """
  @type entrypoint_custom :: %{
          optional(:rpc_action) => term(),
          optional(:typed_query) => term(),
          optional(:domain) => atom(),
          optional(:typed_query_entrypoint) => AshRpc.Entrypoint.t() | nil
        }

  # ─────────────────────────────────────────────────────────────────
  # Generic readers
  # ─────────────────────────────────────────────────────────────────

  @doc """
  Resolves a resource *module atom* to its decorated `%Manifest.Resource{}`.

  Checks the domain resource lookup first, then falls back to the embedded
  resource carried on a `kind: :embedded_resource` entry in the type lookup
  (embedded resources are not present in `resource_lookup`). Returns `nil`
  when the module is not in the manifest.

  Accepts an optional manifest module so callers operating on a scoped
  manifest (e.g. verifiers running against inline domains via
  `AshTypescript.Manifest.verify_for_domains/1`) resolve against that
  manifest instead of the globally configured one. `nil` uses
  `AshTypescript.manifest/0`, `AshTypescript.with_manifest/2` override included.
  """
  @spec resolve_resource(atom() | term(), module() | nil) :: Manifest.Resource.t() | nil
  def resolve_resource(module, manifest \\ nil)

  def resolve_resource(module, manifest) when is_atom(module) and not is_nil(module) do
    case Ash.Info.Manifest.get_resource(AshTypescript.resource_lookup(manifest), module) do
      %Manifest.Resource{} = resource ->
        resource

      _ ->
        case Ash.Info.Manifest.get_type(AshTypescript.type_lookup(manifest), module) do
          %Manifest.Type{resource: %Manifest.Resource{} = resource} -> resource
          _ -> nil
        end
    end
  end

  def resolve_resource(_, _), do: nil

  @doc """
  Returns the precomputed TypeScript type name for a decorated resource or
  type struct, or `nil` when undecorated / not applicable.
  """
  @spec type_name(Manifest.Resource.t() | Manifest.Type.t() | nil) :: String.t() | nil
  def type_name(%Manifest.Resource{custom: %{ash_typescript: %{type_name: name}}}), do: name
  def type_name(%Manifest.Type{custom: %{ash_typescript: %{type_name: name}}}), do: name
  def type_name(_), do: nil

  @doc """
  Returns the names codegen gives an aliased map-like type's definition (a
  declared custom type, `AshRpc.Manifest.Custom.custom_type?/1`, or a
  field-bearing NewType that opts into an alias):
  `t:AshTypescript.CustomTypes.names/0`, from
  `custom.ash_typescript.type_alias_names`. `nil` for any other type.
  """
  @spec type_alias_names(Manifest.Type.t() | nil) :: AshTypescript.CustomTypes.names() | nil
  def type_alias_names(%Manifest.Type{custom: %{ash_typescript: %{type_alias_names: names}}}),
    do: names

  def type_alias_names(_), do: nil

  # ─────────────────────────────────────────────────────────────────
  # Relationship accessors
  # ─────────────────────────────────────────────────────────────────

  @doc """
  Returns the pagination capability of a many-cardinality relationship's
  effective read action, derived at decoration time. `:none` for undecorated
  relationships (to-one, or destination not an RPC resource).
  """
  @spec relationship_pagination(Manifest.Relationship.t() | nil) ::
          :offset | :keyset | :mixed | :none
  def relationship_pagination(rel), do: AshRpc.Manifest.Custom.relationship_pagination(rel)

  # ─────────────────────────────────────────────────────────────────
  # Action accessors (entrypoint-exposed actions in action_lookup)
  # ─────────────────────────────────────────────────────────────────

  @doc """
  Returns the precomputed return-type classification for a decorated action
  (the result of `ActionIntrospection.action_returns_field_selectable_type?/1`),
  or `nil` when the action isn't decorated (caller should compute live).
  """
  @spec action_return_classification(Manifest.Action.t() | nil) ::
          {:ok, atom(), term()} | {:error, atom()} | nil
  def action_return_classification(action),
    do: AshRpc.Manifest.Custom.action_return_classification(action)

  # ─────────────────────────────────────────────────────────────────
  # Entrypoint accessors
  # ─────────────────────────────────────────────────────────────────

  @doc """
  Returns the RPC action DSL struct stashed on the entrypoint, or `nil` if the
  entrypoint isn't an RPC-action entrypoint (e.g., a typed-query-only entry).
  """
  @spec rpc_action(Manifest.Entrypoint.t() | nil) :: term() | nil
  def rpc_action(%Manifest.Entrypoint{custom: %{ash_typescript: %{rpc_action: action}}}),
    do: action

  def rpc_action(_), do: nil

  @doc """
  Returns the typed-query DSL struct stashed on the entrypoint, or `nil`.
  """
  @spec typed_query(Manifest.Entrypoint.t() | nil) :: term() | nil
  def typed_query(%Manifest.Entrypoint{custom: %{ash_typescript: %{typed_query: tq}}}), do: tq
  def typed_query(_), do: nil

  @doc "Returns the domain module that owns this entrypoint, or `nil`."
  @spec entrypoint_domain(Manifest.Entrypoint.t() | nil) :: atom() | nil
  def entrypoint_domain(%Manifest.Entrypoint{custom: %{ash_typescript: %{domain: d}}}), do: d
  def entrypoint_domain(_), do: nil

  @doc "Typed-query entrypoint (`%AshRpc.Entrypoint{preset_fields: …}`) by name, or `nil`."
  @spec typed_query_entrypoint(Manifest.t(), String.t() | atom()) :: AshRpc.Entrypoint.t() | nil
  def typed_query_entrypoint(%Ash.Info.Manifest{} = manifest, name) do
    name = to_string(name)

    Enum.find_value(manifest.entrypoints, fn
      %Manifest.Entrypoint{
        custom: %{ash_typescript: %{typed_query_entrypoint: %AshRpc.Entrypoint{name: ^name} = e}}
      } ->
        e

      _ ->
        nil
    end)
  end

  # ─────────────────────────────────────────────────────────────────
  # Typed controller routes and typed channel publications
  # (manifest-level custom.ash_typescript)
  # ─────────────────────────────────────────────────────────────────

  @doc "The `%Route{}` for `{source_module, name}`, or `nil`. `nil` source reads the configured manifest."
  @spec route(module() | Manifest.t() | nil, module(), atom()) :: Route.t() | nil
  def route(source, source_module, name),
    do: source |> typed_data(:routes) |> Map.get({source_module, name})

  @doc "Every stored route, sorted by `{source_module, name}`."
  @spec routes(module() | Manifest.t() | nil) :: [Route.t()]
  def routes(source \\ nil),
    do:
      source
      |> typed_data(:routes)
      |> Map.values()
      |> Enum.sort_by(&{&1.source_module, &1.name})

  @doc "The `%Publication{}` for `{channel_module, resource, event}`, or `nil`."
  @spec publication(module() | Manifest.t() | nil, module(), module(), String.t()) ::
          Publication.t() | nil
  def publication(source, channel_module, resource, event),
    do: source |> typed_data(:publications) |> Map.get({channel_module, resource, event})

  @doc "Every stored publication, sorted by `{channel_module, resource, event}`."
  @spec publications(module() | Manifest.t() | nil) :: [Publication.t()]
  def publications(source \\ nil),
    do:
      source
      |> typed_data(:publications)
      |> Map.values()
      |> Enum.sort_by(&{&1.channel_module, &1.resource, &1.event})

  # ─────────────────────────────────────────────────────────────────
  # Custom type declarations (manifest-level custom.ash_typescript)
  # ─────────────────────────────────────────────────────────────────

  @doc """
  The manifest module's `custom_types` entry for `module`
  (`AshTypescript.CustomTypes.Scalar` or `MapType`), or `nil`. `nil` source
  reads the configured manifest (`with_manifest/2` override included).
  """
  @spec declared_custom_type(module() | Manifest.t() | nil, module()) ::
          AshTypescript.CustomTypes.Scalar.t() | AshTypescript.CustomTypes.MapType.t() | nil
  def declared_custom_type(source, module), do: custom_type(source, :declared, module)

  @doc """
  The built-in entry for `module` (`AshTypescript.CustomTypes.Builtin`), or
  `nil`. A declared entry for the same module replaces it.
  """
  @spec builtin_custom_type(module() | Manifest.t() | nil, module()) ::
          AshTypescript.CustomTypes.Scalar.t() | AshTypescript.CustomTypes.MapType.t() | nil
  def builtin_custom_type(source, module), do: custom_type(source, :builtin, module)

  @doc """
  The entry that applies to `module`: its manifest `custom_types` entry, else
  its built-in one, else `nil`.
  """
  @spec custom_type_entry(module() | Manifest.t() | nil, module()) ::
          AshTypescript.CustomTypes.Scalar.t() | AshTypescript.CustomTypes.MapType.t() | nil
  def custom_type_entry(source, module),
    do: declared_custom_type(source, module) || builtin_custom_type(source, module)

  @doc """
  The persisted `custom_types` (`t:AshTypescript.CustomTypes.custom_types/0`):
  the manifest's entries and the built-ins. Without decoration, no
  declarations and the built-ins. `nil` source reads the configured manifest
  (`with_manifest/2` override included).
  """
  @spec custom_types(module() | Manifest.t() | nil) :: AshTypescript.CustomTypes.custom_types()
  def custom_types(source \\ nil) do
    case typed_data(source, :custom_types) do
      empty when map_size(empty) == 0 -> AshTypescript.CustomTypes.builtin_only()
      custom_types -> custom_types
    end
  end

  defp custom_type(source, kind, module) do
    source |> typed_data(:custom_types) |> Map.get(kind, %{}) |> Map.get(module)
  end

  defp typed_data(source, key) do
    case AshTypescript.manifest(source) do
      %Manifest{custom: %{ash_typescript: data}} when is_map(data) -> Map.get(data, key, %{})
      _ -> %{}
    end
  end
end
