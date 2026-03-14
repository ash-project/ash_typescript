# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshApiSpec do
  @moduledoc """
  Generates a language-agnostic API specification from Ash resources and actions.

  Given a list of `{resource, action_name}` tuples or an OTP app, traverses the
  type graph to find all reachable resources and types, producing structured IR
  (Elixir structs) that can be serialized to JSON.
  """

  alias AshApiSpec.Resource

  @type t :: %__MODULE__{
          version: String.t(),
          resources: [Resource.t()],
          types: [AshApiSpec.Type.t()]
        }

  @type resource_lookup :: %{atom() => Resource.t()}

  defstruct version: "1.0.0",
            resources: [],
            types: []

  # ─────────────────────────────────────────────────────────────────
  # Generation
  # ─────────────────────────────────────────────────────────────────

  @doc """
  Generate an API specification for the given OTP app.

  ## Options

    * `:otp_app` - The OTP app to scan for Ash domains and resources (required)
    * `:actions` - Optional list of `{resource_module, action_name}` tuples to
      include. When omitted, all public actions across all domains are included.
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
  Generates a spec and returns the resource lookup map directly.
  """
  @spec generate_resource_lookup(keyword()) :: {:ok, resource_lookup()} | {:error, term()}
  def generate_resource_lookup(opts) do
    case generate(opts) do
      {:ok, spec} -> {:ok, resource_lookup(spec)}
      error -> error
    end
  end

  @doc "Looks up a resource by module from a resource lookup map."
  @spec get_resource(resource_lookup(), atom()) :: Resource.t() | nil
  def get_resource(resource_lookup, module) when is_map(resource_lookup) do
    Map.get(resource_lookup, module)
  end

  @doc "Gets a field by resource module and field name from a resource lookup map."
  @spec get_field(resource_lookup(), atom(), atom()) :: AshApiSpec.Field.t() | nil
  def get_field(resource_lookup, resource_module, field_name) do
    with %Resource{} = r <- Map.get(resource_lookup, resource_module) do
      Resource.get_field(r, field_name)
    end
  end

  @doc "Gets the primary key field names by resource module from a resource lookup map."
  @spec primary_key(resource_lookup(), atom()) :: [atom()]
  def primary_key(resource_lookup, resource_module) do
    case Map.get(resource_lookup, resource_module) do
      %Resource{primary_key: pk} -> pk
      nil -> []
    end
  end

  @doc "Gets an identity by resource module and identity name from a resource lookup map."
  @spec get_identity(resource_lookup(), atom(), atom()) :: %{keys: [atom()]} | nil
  def get_identity(resource_lookup, resource_module, identity_name) do
    with %Resource{} = r <- Map.get(resource_lookup, resource_module) do
      Resource.get_identity(r, identity_name)
    end
  end
end
