# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.Custom do
  @moduledoc """
  Thin accessor module for reading ash_typescript-owned data persisted under
  `custom.ash_typescript` on Ash.Info.Manifest structs.

  Decoration is done by `AshTypescript.Manifest.Decorator` after
  `Ash.Info.Manifest.Generator.generate/1`. Runtime callers should prefer these
  accessors over walking Spark DSL state — the manifest carries pre-computed
  lookups that are O(1) map reads.

  All accessors return `nil` (or sensible empty defaults) when the struct has
  no ash_typescript decoration, so callers can pattern-match on `nil`.
  """

  alias Ash.Info.Manifest

  @typedoc """
  The decoration map persisted under `custom.ash_typescript` on a
  `%Manifest.Resource{}` (including embedded resources nested under a `%Manifest.Type{}`).
  """
  @type resource_custom :: %{
          optional(:field_name_mappings) => %{atom() => String.t()},
          optional(:reverse_field_name_mappings) => %{String.t() => atom()},
          optional(:argument_name_mappings) => %{atom() => %{atom() => String.t()}},
          optional(:reverse_argument_name_mappings) => %{atom() => %{String.t() => atom()}},
          optional(:formatted_field_names) => %{{atom(), atom()} => String.t()},
          optional(:type_name) => String.t() | nil,
          optional(:authorize_bulk_strategy) => :error | :filter
        }

  @typedoc """
  The decoration map persisted under `custom.ash_typescript` on a
  `%Manifest.Type{}` for NewTypes/TypedStructs that export
  `typescript_field_names/0`.
  """
  @type type_custom :: %{
          optional(:field_name_mappings) => %{atom() => String.t()},
          optional(:reverse_field_name_mappings) => %{String.t() => atom()},
          optional(:type_name) => String.t() | nil
        }

  @typedoc """
  The decoration map persisted under `custom.ash_typescript` on the
  `%Manifest.Action{}` carried by an RPC/typed-query entrypoint (and thus present
  in `action_lookup`). Only actions exposed as entrypoints are decorated — those
  are the only ones the runtime pipeline ever looks up.
  """
  @type action_custom :: %{
          optional(:return_classification) =>
            {:ok, atom(), term()} | {:error, atom()},
          optional(:input_expected_keys) => %{atom() => %{String.t() => atom()}},
          optional(:input_field_types) => %{atom() => Ash.Info.Manifest.Type.t()}
        }

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
          optional(:sorting_enabled?) => boolean()
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
  """
  @spec resolve_resource(atom() | term()) :: Manifest.Resource.t() | nil
  def resolve_resource(module) when is_atom(module) and not is_nil(module) do
    case Ash.Info.Manifest.get_resource(AshTypescript.resource_lookup(), module) do
      %Manifest.Resource{} = resource ->
        resource

      _ ->
        case Ash.Info.Manifest.get_type(AshTypescript.type_lookup(), module) do
          %Manifest.Type{resource: %Manifest.Resource{} = resource} -> resource
          _ -> nil
        end
    end
  end

  def resolve_resource(_), do: nil

  @doc """
  Returns the `:ash_typescript` decoration map for any struct that carries a
  `custom` field, or `nil` if no decoration is present.
  """
  @spec ash_typescript(struct() | nil) :: map() | nil
  def ash_typescript(%{custom: %{ash_typescript: data}}), do: data
  def ash_typescript(_), do: nil

  @doc """
  Returns `true` if the resource struct was decorated by ash_typescript
  (i.e., the underlying module has the `AshTypescript.Resource` extension).
  """
  @spec typescript_resource?(Manifest.Resource.t() | nil) :: boolean()
  def typescript_resource?(%Manifest.Resource{custom: %{ash_typescript: _}}), do: true
  def typescript_resource?(_), do: false

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
  def field_name_mappings(%Manifest.Resource{
        custom: %{ash_typescript: %{field_name_mappings: m}}
      }),
      do: m

  def field_name_mappings(_), do: %{}

  @doc """
  Returns the reverse mapping (`client_string => atom`) for a decorated resource.
  """
  @spec reverse_field_name_mappings(Manifest.Resource.t() | nil) :: %{String.t() => atom()}
  def reverse_field_name_mappings(%Manifest.Resource{
        custom: %{ash_typescript: %{reverse_field_name_mappings: m}}
      }),
      do: m

  def reverse_field_name_mappings(_), do: %{}

  @doc """
  Looks up the mapped client name for an internal field atom, or returns `nil`
  if there is no mapping.
  """
  @spec mapped_field_name(Manifest.Resource.t() | nil, atom()) :: String.t() | nil
  def mapped_field_name(resource, field) when is_atom(field) do
    resource |> field_name_mappings() |> Map.get(field)
  end

  @doc """
  Looks up the original Elixir atom for a client-side field name. Returns `nil`
  if no mapping is registered.

  Accepts atom or string for `client_name` (atom is converted via `Atom.to_string/1`).
  """
  @spec original_field_name(Manifest.Resource.t() | nil, String.t() | atom()) :: atom() | nil
  def original_field_name(resource, client_name) when is_binary(client_name) do
    resource |> reverse_field_name_mappings() |> Map.get(client_name)
  end

  def original_field_name(resource, client_name) when is_atom(client_name) do
    original_field_name(resource, Atom.to_string(client_name))
  end

  @doc """
  Returns the pre-formatted client name for a field under a built-in formatter,
  or `nil` if the resource isn't decorated, the field isn't tracked, or the
  formatter isn't one of `:camel_case` / `:snake_case` / `:pascal_case`.
  """
  @spec formatted_field_name(Manifest.Resource.t() | nil, atom(), atom()) :: String.t() | nil
  def formatted_field_name(
        %Manifest.Resource{custom: %{ash_typescript: %{formatted_field_names: m}}},
        field,
        formatter
      )
      when is_atom(field) and is_atom(formatter) do
    Map.get(m, {field, formatter})
  end

  def formatted_field_name(_, _, _), do: nil

  @doc """
  Returns the precomputed bulk-authorization strategy (`:error` or `:filter`)
  for a decorated resource, or `nil` when the resource isn't decorated (caller
  should fall back to a live `Ash.DataLayer.data_layer_can?/2` check).
  """
  @spec authorize_bulk_strategy(Manifest.Resource.t() | nil) :: :error | :filter | nil
  def authorize_bulk_strategy(%Manifest.Resource{
        custom: %{ash_typescript: %{authorize_bulk_strategy: strategy}}
      }),
      do: strategy

  def authorize_bulk_strategy(_), do: nil

  @doc """
  Returns the argument-name mapping (`%{arg_atom => client_string}`) for a
  particular action on the resource, or an empty map.
  """
  @spec argument_name_mappings_for_action(Manifest.Resource.t() | nil, atom()) ::
          %{atom() => String.t()}
  def argument_name_mappings_for_action(
        %Manifest.Resource{custom: %{ash_typescript: %{argument_name_mappings: m}}},
        action_name
      )
      when is_atom(action_name) do
    Map.get(m, action_name, %{})
  end

  def argument_name_mappings_for_action(_, _), do: %{}

  @doc """
  Looks up the mapped client name for an action argument atom. Returns `nil`
  if no mapping is registered.
  """
  @spec mapped_argument_name(Manifest.Resource.t() | nil, atom(), atom()) :: String.t() | nil
  def mapped_argument_name(resource, action_name, argument)
      when is_atom(action_name) and is_atom(argument) do
    resource |> argument_name_mappings_for_action(action_name) |> Map.get(argument)
  end

  @doc """
  Looks up the original Elixir argument atom for a client-side argument name.
  Returns `nil` if no mapping is registered.

  Accepts atom or string for `client_name`.
  """
  @spec original_argument_name(Manifest.Resource.t() | nil, atom(), String.t() | atom()) ::
          atom() | nil
  def original_argument_name(
        %Manifest.Resource{custom: %{ash_typescript: %{reverse_argument_name_mappings: m}}},
        action_name,
        client_name
      )
      when is_atom(action_name) and is_binary(client_name) do
    m |> Map.get(action_name, %{}) |> Map.get(client_name)
  end

  def original_argument_name(resource, action_name, client_name) when is_atom(client_name) do
    original_argument_name(resource, action_name, Atom.to_string(client_name))
  end

  def original_argument_name(_, _, _), do: nil

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
  def action_return_classification(%Manifest.Action{
        custom: %{ash_typescript: %{return_classification: classification}}
      }),
      do: classification

  def action_return_classification(_), do: nil

  @doc """
  Returns the precomputed `%{client_name => internal_atom}` input map for a
  decorated action under `formatter` (one of the built-in formatters), or `nil`
  when the action isn't decorated or `formatter` isn't a precomputed built-in
  (caller should compute live).
  """
  @spec action_input_expected_keys(Manifest.Action.t() | nil, atom() | tuple()) ::
          %{String.t() => atom()} | nil
  def action_input_expected_keys(
        %Manifest.Action{custom: %{ash_typescript: %{input_expected_keys: by_formatter}}},
        formatter
      )
      when is_map(by_formatter) do
    Map.get(by_formatter, formatter)
  end

  def action_input_expected_keys(_, _), do: nil

  @doc """
  Returns the precomputed `%{internal_atom => %Manifest.Type{}}` input field-type
  map for a decorated action, or `nil` when the action isn't decorated.
  """
  @spec action_input_field_types(Manifest.Action.t() | nil) ::
          %{atom() => Ash.Info.Manifest.Type.t()} | nil
  def action_input_field_types(%Manifest.Action{
        custom: %{ash_typescript: %{input_field_types: types}}
      }),
      do: types

  def action_input_field_types(_), do: nil

  # ─────────────────────────────────────────────────────────────────
  # Type accessors (NewTypes / TypedStructs)
  # ─────────────────────────────────────────────────────────────────

  @doc """
  Returns the forward `field_name_mappings` map for a decorated type.
  """
  @spec type_field_name_mappings(Manifest.Type.t() | nil) :: %{atom() => String.t()}
  def type_field_name_mappings(%Manifest.Type{
        custom: %{ash_typescript: %{field_name_mappings: m}}
      }),
      do: m

  def type_field_name_mappings(_), do: %{}

  @doc """
  Returns the reverse mapping (`client_string => atom`) for a decorated type.
  """
  @spec reverse_type_field_name_mappings(Manifest.Type.t() | nil) :: %{String.t() => atom()}
  def reverse_type_field_name_mappings(%Manifest.Type{
        custom: %{ash_typescript: %{reverse_field_name_mappings: m}}
      }),
      do: m

  def reverse_type_field_name_mappings(_), do: %{}

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
end
