# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshApiSpec do
  @moduledoc """
  Generates a language-agnostic API specification from Ash resources and actions.

  Given a list of `{resource, action_name}` tuples or an OTP app, traverses the
  type graph to find all reachable resources and types, producing structured IR
  (Elixir structs) that can also be serialized to JSON.
  """

  alias AshApiSpec.{Entrypoint, Resource}

  @type t :: %__MODULE__{
          version: String.t(),
          resources: [Resource.t()],
          types: [AshApiSpec.Type.t()],
          entrypoints: [Entrypoint.t()]
        }

  @type resource_lookup :: %{atom() => Resource.t()}
  @type action_lookup :: %{{atom(), atom()} => AshApiSpec.Action.t()}

  defstruct version: "1.0.0",
            resources: [],
            types: [],
            entrypoints: []

  # ─────────────────────────────────────────────────────────────────
  # Generation
  # ─────────────────────────────────────────────────────────────────

  @doc """
  Generate an API specification for the given OTP app.

  ## Options

    * `:otp_app` - The OTP app to scan for Ash domains and resources (required)
    * `:action_entrypoints` - Optional list of `{resource_module, action_name}` tuples
      used as entrypoints for deriving the spec. When omitted, all public actions
      across all domains are included.
  """
  @spec generate(keyword()) :: {:ok, t()} | {:error, term()}
  def generate(opts) do
    AshApiSpec.Generator.generate(opts)
  end

  # ─────────────────────────────────────────────────────────────────
  # Resource Lookup
  # ─────────────────────────────────────────────────────────────────

  @doc """
  Builds a resource lookup map from the spec, keyed by resource module.
  """
  @spec resource_lookup(t()) :: resource_lookup()
  def resource_lookup(%__MODULE__{resources: resources}) do
    Map.new(resources, fn r -> {r.module, r} end)
  end

  @doc """
  Builds an action lookup map from the spec, keyed by `{resource_module, action_name}`.
  """
  @spec action_lookup(t()) :: action_lookup()
  def action_lookup(%__MODULE__{entrypoints: entrypoints}) do
    Map.new(entrypoints, fn e -> {{e.resource, e.action.name}, e.action} end)
  end

  @doc """
  Generates a spec and returns the resource lookup map directly.
  """
  @spec generate_resource_lookup(keyword()) :: {:ok, resource_lookup()} | {:error, term()}
  def generate_resource_lookup(opts) do
    {:ok, spec} = generate(opts)
    {:ok, resource_lookup(spec)}
  end

  # ─────────────────────────────────────────────────────────────────
  # Resource Accessors
  # ─────────────────────────────────────────────────────────────────

  @doc "Looks up a resource by module. Returns nil if not found."
  @spec get_resource(resource_lookup(), atom()) :: Resource.t() | nil
  def get_resource(resource_lookup, module) when is_map(resource_lookup) do
    Map.get(resource_lookup, module)
  end

  @doc "Looks up a resource by module. Raises if not found."
  @spec get_resource!(resource_lookup(), atom()) :: Resource.t()
  def get_resource!(resource_lookup, module) when is_map(resource_lookup) do
    case Map.get(resource_lookup, module) do
      %Resource{} = r -> r
      nil -> raise "Resource #{inspect(module)} not found in resource lookup"
    end
  end

  @doc "Checks if a resource exists in the lookup."
  @spec has_resource?(resource_lookup(), atom()) :: boolean()
  def has_resource?(resource_lookup, module) when is_map(resource_lookup) do
    Map.has_key?(resource_lookup, module)
  end

  # ─────────────────────────────────────────────────────────────────
  # Nested Accessors (resource_lookup → resource → item)
  # ─────────────────────────────────────────────────────────────────

  @doc "Gets a field by resource module and field name."
  @spec get_field(resource_lookup(), atom(), atom()) :: AshApiSpec.Field.t() | nil
  def get_field(resource_lookup, resource_module, field_name) do
    with %Resource{} = r <- Map.get(resource_lookup, resource_module) do
      Resource.get_field(r, field_name)
    end
  end

  @doc "Gets a relationship by resource module and relationship name."
  @spec get_relationship(resource_lookup(), atom(), atom()) :: AshApiSpec.Relationship.t() | nil
  def get_relationship(resource_lookup, resource_module, rel_name) do
    with %Resource{} = r <- Map.get(resource_lookup, resource_module) do
      Resource.get_relationship(r, rel_name)
    end
  end

  @doc """
  Gets a field or relationship by name, checking fields first.

  Returns `%AshApiSpec.Field{}`, `%AshApiSpec.Relationship{}`, or nil.
  """
  @spec get_field_or_relationship(resource_lookup(), atom(), atom()) ::
          AshApiSpec.Field.t() | AshApiSpec.Relationship.t() | nil
  def get_field_or_relationship(resource_lookup, resource_module, name) do
    case get_field(resource_lookup, resource_module, name) do
      %AshApiSpec.Field{} = field -> field
      nil -> get_relationship(resource_lookup, resource_module, name)
    end
  end

  @doc "Gets an action by resource module and action name from an action lookup."
  @spec get_action(action_lookup(), atom(), atom()) :: AshApiSpec.Action.t() | nil
  def get_action(action_lookup, resource_module, action_name) do
    Map.get(action_lookup, {resource_module, action_name})
  end

  @doc "Gets an identity by resource module and identity name."
  @spec get_identity(resource_lookup(), atom(), atom()) :: %{keys: [atom()]} | nil
  def get_identity(resource_lookup, resource_module, identity_name) do
    with %Resource{} = r <- Map.get(resource_lookup, resource_module) do
      Resource.get_identity(r, identity_name)
    end
  end

  @doc "Gets the primary key field names by resource module."
  @spec primary_key(resource_lookup(), atom()) :: [atom()]
  def primary_key(resource_lookup, resource_module) do
    case Map.get(resource_lookup, resource_module) do
      %Resource{primary_key: pk} -> pk
      nil -> []
    end
  end
end
