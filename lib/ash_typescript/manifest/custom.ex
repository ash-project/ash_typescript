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
  under `custom.ash_rpc` (written by `AshRpc.Manifest.Decorator`); the
  accessors for those delegate to `AshRpc.Manifest.Custom`. Callers should
  prefer these accessors over walking Spark DSL state — the manifest carries
  pre-computed lookups that are O(1) map reads.

  All accessors return `nil` (or sensible empty defaults) when the struct has
  no decoration, so callers can pattern-match on `nil`.
  """

  alias Ash.Info.Manifest

  @typedoc """
  The decoration map persisted under `custom.ash_typescript` on a
  `%Manifest.Resource{}` (including embedded resources nested under a `%Manifest.Type{}`).
  """
  @type resource_custom :: %{optional(:type_name) => String.t() | nil}

  @typedoc """
  The decoration map persisted under `custom.ash_typescript` on a
  `%Manifest.Type{}` for NewTypes/TypedStructs that export
  `typescript_field_names/0`.
  """
  @type type_custom :: %{optional(:type_name) => String.t() | nil}

  @typedoc """
  The decoration map persisted under `custom.ash_typescript` on a
  `%Manifest.Entrypoint{}`.
  """
  @type entrypoint_custom :: %{
          optional(:rpc_action) => term(),
          optional(:typed_query) => term(),
          optional(:domain) => atom(),
          optional(:resource_config) => term(),
          optional(:metadata_field_mappings) => %{atom() => String.t()},
          optional(:reverse_metadata_field_mappings) => %{String.t() => atom()},
          optional(:exposed_metadata_fields) => [atom()],
          optional(:load_restrictions) => {:allow, list()} | {:deny, list()} | :none,
          optional(:filtering_enabled?) => boolean(),
          optional(:sorting_enabled?) => boolean(),
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
  manifest instead of the globally configured one. `nil` uses the
  configured manifest.
  """
  @spec resolve_resource(atom() | term(), module() | nil) :: Manifest.Resource.t() | nil
  def resolve_resource(module, manifest \\ nil)

  def resolve_resource(module, manifest) when is_atom(module) and not is_nil(module) do
    manifest = manifest || AshTypescript.manifest_module()

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
  Returns the `:ash_typescript` decoration map for any struct that carries a
  `custom` field, or `nil` if no decoration is present.
  """
  @spec ash_typescript(struct() | nil) :: map() | nil
  def ash_typescript(%{custom: %{ash_typescript: data}}), do: data
  def ash_typescript(_), do: nil

  @doc """
  Returns `true` if the resource struct is exposed to clients (i.e., the
  underlying module has the `AshTypescript.Resource` extension).
  """
  @spec typescript_resource?(Manifest.Resource.t() | nil) :: boolean()
  def typescript_resource?(resource), do: AshRpc.Manifest.Custom.exposed?(resource)

  @doc """
  Returns the precomputed TypeScript type name for a decorated resource or
  type struct, or `nil` when undecorated / not applicable.
  """
  @spec type_name(Manifest.Resource.t() | Manifest.Type.t() | nil) :: String.t() | nil
  def type_name(%Manifest.Resource{custom: %{ash_typescript: %{type_name: name}}}), do: name
  def type_name(%Manifest.Type{custom: %{ash_typescript: %{type_name: name}}}), do: name
  def type_name(_), do: nil

  # ─────────────────────────────────────────────────────────────────
  # Resource accessors
  # ─────────────────────────────────────────────────────────────────

  @doc """
  Returns the forward `field_name_mappings` map (`atom => client_string`) for
  a decorated resource, or an empty map.
  """
  @spec field_name_mappings(Manifest.Resource.t() | nil) :: %{atom() => String.t()}
  def field_name_mappings(resource), do: AshRpc.Manifest.Custom.field_name_overrides(resource)

  @doc """
  Looks up the mapped client name for an internal field atom, or returns `nil`
  if there is no mapping.
  """
  @spec mapped_field_name(Manifest.Resource.t() | nil, atom()) :: String.t() | nil
  def mapped_field_name(resource, field) when is_atom(field),
    do: AshRpc.Manifest.Custom.field_name_override(resource, field)

  @doc """
  Looks up the original Elixir atom for a client-side field name. Returns `nil`
  if no mapping is registered.

  Accepts atom or string for `client_name` (atom is converted via `Atom.to_string/1`).
  """
  @spec original_field_name(Manifest.Resource.t() | nil, String.t() | atom()) :: atom() | nil
  def original_field_name(resource, client_name),
    do: AshRpc.Manifest.Custom.original_field_name(resource, client_name)

  @doc """
  Returns the pre-formatted client name for a field under a built-in formatter,
  or `nil` if the resource isn't decorated, the field isn't tracked, or the
  formatter isn't one of `:camel_case` / `:snake_case` / `:pascal_case`.
  """
  @spec formatted_field_name(Manifest.Resource.t() | nil, atom(), atom()) :: String.t() | nil
  def formatted_field_name(resource, field, formatter)
      when is_atom(field) and is_atom(formatter) do
    if AshRpc.Manifest.Custom.exposed?(resource),
      do: AshRpc.FieldFormatter.format_field_for_client(field, resource, formatter)
  end

  def formatted_field_name(_, _, _), do: nil

  @doc """
  Looks up the mapped client name for an action argument atom. Returns `nil`
  if no mapping is registered.
  """
  @spec mapped_argument_name(Manifest.Resource.t() | nil, atom(), atom()) :: String.t() | nil
  def mapped_argument_name(resource, action, argument),
    do: AshRpc.Manifest.Custom.argument_name_override(resource, action, argument)

  @doc """
  Looks up the original Elixir argument atom for a client-side argument name.
  Returns `nil` if no mapping is registered.

  Accepts atom or string for `client_name`.
  """
  @spec original_argument_name(Manifest.Resource.t() | nil, atom(), String.t() | atom()) ::
          atom() | nil
  def original_argument_name(resource, action, client_name),
    do: AshRpc.Manifest.Custom.original_argument_name(resource, action, client_name)

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

  @doc """
  Returns the effective read action name for a decorated many-cardinality
  relationship (the relationship's configured `read_action`, falling back to
  the destination's primary read action). `nil` when undecorated.
  """
  @spec relationship_read_action(Manifest.Relationship.t() | nil) :: atom() | nil
  def relationship_read_action(rel), do: AshRpc.Manifest.Custom.relationship_read_action(rel)

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

  @doc """
  Returns the precomputed `%{internal_atom => %Manifest.Type{}}` input field-type
  map for a decorated action, or `nil` when the action isn't decorated.
  """
  @spec action_input_field_types(Manifest.Action.t() | nil) ::
          %{atom() => Ash.Info.Manifest.Type.t()} | nil
  def action_input_field_types(action),
    do: AshRpc.Manifest.Custom.action_input_field_types(action)

  # ─────────────────────────────────────────────────────────────────
  # Type accessors (NewTypes / TypedStructs)
  # ─────────────────────────────────────────────────────────────────

  @doc """
  Returns the forward `field_name_mappings` map for a decorated type.
  """
  @spec type_field_name_mappings(Manifest.Type.t() | nil) :: %{atom() => String.t()}
  def type_field_name_mappings(type), do: AshRpc.Manifest.Custom.type_field_name_overrides(type)

  @doc """
  Returns the reverse mapping (`client_string => atom`) for a decorated type.
  """
  @spec reverse_type_field_name_mappings(Manifest.Type.t() | nil) :: %{String.t() => atom()}
  def reverse_type_field_name_mappings(type),
    do: elem(type_field_name_mappings_pair(type) || {%{}, %{}}, 1)

  @doc """
  Returns `{forward, reverse}` field-name maps for a decorated type, or `nil`
  when the type carries no `custom.ash_rpc` field-name decoration.

  Unlike `type_field_name_mappings/1` (which returns `%{}` for both the
  decorated-but-empty and undecorated cases), this distinguishes "not decorated"
  as `nil` so callers can fall back to resolving the decorated type from the type
  lookup or to live reflection.
  """
  @spec type_field_name_mappings_pair(Manifest.Type.t() | nil) ::
          {%{atom() => String.t()}, %{String.t() => atom()}} | nil
  def type_field_name_mappings_pair(type),
    do: AshRpc.Manifest.Custom.type_field_name_overrides_pair(type)

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

  @doc "Returns the resource_config DSL struct for this entrypoint, or `nil`."
  @spec resource_config(Manifest.Entrypoint.t() | nil) :: term() | nil
  def resource_config(%Manifest.Entrypoint{custom: %{ash_typescript: %{resource_config: rc}}}),
    do: rc

  def resource_config(_), do: nil

  @doc """
  Returns the metadata field-name mapping (`atom => client_string`) for the
  entrypoint's RPC action, or an empty map.
  """
  @spec metadata_field_mappings(Manifest.Entrypoint.t() | nil) :: %{atom() => String.t()}
  def metadata_field_mappings(%Manifest.Entrypoint{
        custom: %{ash_typescript: %{metadata_field_mappings: m}}
      }),
      do: m

  def metadata_field_mappings(_), do: %{}

  @doc """
  Returns the reverse metadata mapping (`client_string => atom`), or empty.
  """
  @spec reverse_metadata_field_mappings(Manifest.Entrypoint.t() | nil) :: %{String.t() => atom()}
  def reverse_metadata_field_mappings(%Manifest.Entrypoint{
        custom: %{ash_typescript: %{reverse_metadata_field_mappings: m}}
      }),
      do: m

  def reverse_metadata_field_mappings(_), do: %{}

  @doc "Returns the precomputed exposed metadata field atoms for an entrypoint, or `[]`."
  @spec exposed_metadata_fields(Manifest.Entrypoint.t() | nil) :: [atom()]
  def exposed_metadata_fields(%Manifest.Entrypoint{
        custom: %{ash_typescript: %{exposed_metadata_fields: fields}}
      }),
      do: fields

  def exposed_metadata_fields(_), do: []

  @doc "Returns the load restriction tag for an entrypoint. Defaults to `:none`."
  @spec load_restrictions(Manifest.Entrypoint.t() | nil) ::
          {:allow, list()} | {:deny, list()} | :none
  def load_restrictions(%Manifest.Entrypoint{
        custom: %{ash_typescript: %{load_restrictions: lr}}
      }),
      do: lr

  def load_restrictions(_), do: :none

  @doc "Whether client filtering is enabled for this entrypoint. Defaults to `true`."
  @spec filtering_enabled?(Manifest.Entrypoint.t() | nil) :: boolean()
  def filtering_enabled?(%Manifest.Entrypoint{
        custom: %{ash_typescript: %{filtering_enabled?: v}}
      }),
      do: v

  def filtering_enabled?(_), do: true

  @doc "Whether client sorting is enabled for this entrypoint. Defaults to `true`."
  @spec sorting_enabled?(Manifest.Entrypoint.t() | nil) :: boolean()
  def sorting_enabled?(%Manifest.Entrypoint{
        custom: %{ash_typescript: %{sorting_enabled?: v}}
      }),
      do: v

  def sorting_enabled?(_), do: true

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
end
