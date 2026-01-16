# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Action.Metadata.Signature do
  @moduledoc """
  Builds contract and version signatures for RPC actions.

  This module supports skew protection by generating two types of signatures:

  - **Contract Signature**: Captures only breaking changes that would cause existing
    clients to fail (required field additions, removals, type changes, mapping changes).

  - **Version Signature**: Captures all interface changes including non-breaking
    additions (new optional fields, new relationships, etc.).

  Both signatures are hashed to enable skew detection at runtime.

  ## Usage

      {contract_hash, version_hash} = Signature.hashes_for_action(resource, action, rpc_action)

  ## Hash Types

  | Hash Type | Changes When | Client Action |
  |-----------|--------------|---------------|
  | Contract Hash | Breaking changes only | Must handle (reload, error) |
  | Version Hash | Any interface change | Informational (may want to update) |
  """

  alias AshTypescript.Rpc.Action.Metadata.TypeRegistry
  alias AshTypescript.Rpc.Codegen.Helpers.ActionIntrospection
  alias AshTypescript.Rpc.Codegen.TypeGenerators.MetadataTypes

  defmodule ContractSignature do
    @moduledoc """
    Struct representing breaking changes only.

    Includes: required fields, removals, type changes, mapping changes.
    Excludes: optional field additions (non-breaking).
    """
    defstruct [
      :resource_name,
      :rpc_action_name,
      :ash_action_name,
      :action_type,
      :required_arguments,
      :required_attributes,
      :existing_return_fields,
      :field_mappings,
      :argument_mappings,
      :pagination_config,
      :get_config,
      :identities,
      :metadata_config,
      :referenced_type_schemas
    ]
  end

  defmodule VersionSignature do
    @moduledoc """
    Struct representing all interface changes.

    Includes everything in ContractSignature plus optional additions.
    """
    defstruct [
      :resource_name,
      :rpc_action_name,
      :ash_action_name,
      :action_type,
      :all_arguments,
      :all_accepted_attributes,
      :all_return_fields,
      :field_mappings,
      :argument_mappings,
      :pagination_config,
      :get_config,
      :identities,
      :metadata_config,
      :referenced_type_schemas
    ]
  end

  @doc """
  Builds contract signature (breaking changes only).

  The contract signature includes only elements that would break existing clients
  if changed: required arguments, required attributes, existing return fields,
  and all configuration/mapping changes.
  """
  @spec build_contract(module(), map(), map()) :: ContractSignature.t()
  def build_contract(resource, action, rpc_action) do
    %ContractSignature{
      resource_name: inspect(resource),
      rpc_action_name: rpc_action.name,
      ash_action_name: action.name,
      action_type: action.type,
      required_arguments: extract_required_arguments(action),
      required_attributes: extract_required_attributes(resource, action),
      existing_return_fields: extract_existing_return_fields(resource, action),
      field_mappings: extract_field_mappings(resource),
      argument_mappings: extract_argument_mappings(resource, action),
      pagination_config: extract_pagination_config(action),
      get_config: extract_get_config(action, rpc_action),
      identities: extract_identities(rpc_action),
      metadata_config: extract_metadata_config(rpc_action, action),
      referenced_type_schemas: build_referenced_type_schemas(resource, action)
    }
  end

  @doc """
  Builds version signature (all interface elements).

  The version signature includes all interface elements that could affect
  TypeScript code generation, including optional additions.
  """
  @spec build_version(module(), map(), map()) :: VersionSignature.t()
  def build_version(resource, action, rpc_action) do
    %VersionSignature{
      resource_name: inspect(resource),
      rpc_action_name: rpc_action.name,
      ash_action_name: action.name,
      action_type: action.type,
      all_arguments: extract_all_arguments(action),
      all_accepted_attributes: extract_all_attributes(resource, action),
      all_return_fields: extract_all_return_fields(resource, action),
      field_mappings: extract_field_mappings(resource),
      argument_mappings: extract_argument_mappings(resource, action),
      pagination_config: extract_pagination_config(action),
      get_config: extract_get_config(action, rpc_action),
      identities: extract_identities(rpc_action),
      metadata_config: extract_metadata_config(rpc_action, action),
      referenced_type_schemas: build_referenced_type_schemas(resource, action)
    }
  end

  defp build_referenced_type_schemas(resource, action) do
    case action.type do
      :action ->
        # For generic actions, collect from return type
        TypeRegistry.build_for_action_return(action)

      _ ->
        # For resource actions (read, create, update, destroy), collect from resource
        TypeRegistry.build_for_resource(resource)
    end
  end

  @doc """
  Computes SHA256 hash of any signature struct, returns 16-char hex string.

  The hash is deterministic and computed from the struct's binary representation.
  """
  @spec hash(ContractSignature.t() | VersionSignature.t()) :: String.t()
  def hash(signature) do
    signature
    |> Map.from_struct()
    |> normalize_for_hashing()
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> String.slice(0, 16)
  end

  @doc """
  Builds both signatures and computes both hashes.

  Returns a tuple of `{contract_hash, version_hash}`.
  """
  @spec hashes_for_action(module(), map(), map()) :: {String.t(), String.t()}
  def hashes_for_action(resource, action, rpc_action) do
    contract_hash = build_contract(resource, action, rpc_action) |> hash()
    version_hash = build_version(resource, action, rpc_action) |> hash()
    {contract_hash, version_hash}
  end

  # ─────────────────────────────────────────────────────────────────
  # Contract Signature Helpers (Breaking Changes Only)
  # ─────────────────────────────────────────────────────────────────

  defp extract_required_arguments(action) do
    action.arguments
    |> Enum.filter(fn arg -> arg.public? and not arg.allow_nil? and is_nil(arg.default) end)
    |> Map.new(fn arg -> {arg.name, normalize_argument(arg)} end)
  end

  defp extract_required_attributes(resource, action) do
    accepted = Map.get(action, :accept) || []
    allow_nil_input = Map.get(action, :allow_nil_input) || []
    require_attributes = Map.get(action, :require_attributes) || []

    accepted
    |> Enum.map(&Ash.Resource.Info.attribute(resource, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(fn attr ->
      # Required if: not in allow_nil_input AND (in require_attributes OR (not allow_nil AND no default))
      attr.name not in allow_nil_input and
        (attr.name in require_attributes or
           (not attr.allow_nil? and is_nil(attr.default)))
    end)
    |> Map.new(fn attr -> {attr.name, normalize_attribute(attr)} end)
  end

  defp extract_existing_return_fields(resource, action) do
    case action.type do
      :action ->
        extract_action_return_fields(action)

      _ ->
        extract_resource_fields(resource)
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Version Signature Helpers (All Interface Elements)
  # ─────────────────────────────────────────────────────────────────

  defp extract_all_arguments(action) do
    action.arguments
    |> Enum.filter(& &1.public?)
    |> Map.new(fn arg -> {arg.name, normalize_argument_full(arg)} end)
  end

  defp extract_all_attributes(resource, action) do
    accepted = Map.get(action, :accept) || []

    accepted
    |> Enum.map(&Ash.Resource.Info.attribute(resource, &1))
    |> Enum.reject(&is_nil/1)
    |> Map.new(fn attr -> {attr.name, normalize_attribute_full(attr)} end)
  end

  defp extract_all_return_fields(resource, action) do
    case action.type do
      :action ->
        extract_action_return_fields_full(action)

      _ ->
        extract_resource_fields_full(resource)
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Shared Helpers
  # ─────────────────────────────────────────────────────────────────

  defp extract_field_mappings(resource) do
    if function_exported?(resource, :typescript_field_names, 0) do
      resource.typescript_field_names()
      |> Enum.sort()
    else
      []
    end
  end

  defp extract_argument_mappings(resource, action) do
    if function_exported?(resource, :typescript_argument_names, 1) do
      resource.typescript_argument_names(action.name)
      |> Enum.sort()
    else
      []
    end
  end

  defp extract_pagination_config(action) do
    case ActionIntrospection.get_pagination_config(action) do
      nil ->
        nil

      config ->
        # Normalize pagination config to only include relevant fields
        %{
          offset?: Map.get(config, :offset?, false),
          keyset?: Map.get(config, :keyset?, false),
          required?: Map.get(config, :required?, false),
          countable: Map.get(config, :countable, false),
          default_limit: Map.get(config, :default_limit),
          max_page_size: Map.get(config, :max_page_size)
        }
    end
  end

  defp extract_get_config(action, rpc_action) do
    %{
      get?: Map.get(action, :get?, false) || Map.get(rpc_action, :get?, false),
      get_by: Map.get(rpc_action, :get_by) || [],
      not_found_error?: Map.get(rpc_action, :not_found_error?)
    }
  end

  defp extract_identities(rpc_action) do
    (Map.get(rpc_action, :identities) || [:_primary_key])
    |> Enum.sort()
  end

  defp extract_metadata_config(rpc_action, action) do
    exposed_fields = MetadataTypes.get_exposed_metadata_fields(rpc_action, action)
    field_names = Map.get(rpc_action, :metadata_field_names) || []

    %{
      exposed_fields: Enum.sort(exposed_fields),
      field_names: Enum.sort(field_names)
    }
  end

  # ─────────────────────────────────────────────────────────────────
  # Field Extraction Helpers
  # ─────────────────────────────────────────────────────────────────

  defp extract_resource_fields(resource) do
    attributes = extract_resource_attributes(resource)
    relationships = extract_resource_relationships(resource)
    calculations = extract_resource_calculations(resource)
    aggregates = extract_resource_aggregates(resource)

    %{
      attributes: attributes,
      relationships: relationships,
      calculations: calculations,
      aggregates: aggregates
    }
  end

  defp extract_resource_fields_full(resource) do
    attributes = extract_resource_attributes_full(resource)
    relationships = extract_resource_relationships_full(resource)
    calculations = extract_resource_calculations_full(resource)
    aggregates = extract_resource_aggregates_full(resource)

    %{
      attributes: attributes,
      relationships: relationships,
      calculations: calculations,
      aggregates: aggregates
    }
  end

  defp extract_resource_attributes(resource) do
    resource
    |> Ash.Resource.Info.public_attributes()
    |> Map.new(&{&1.name, normalize_type(&1.type, &1.constraints)})
  end

  defp extract_resource_attributes_full(resource) do
    resource
    |> Ash.Resource.Info.public_attributes()
    |> Map.new(fn attr ->
      {attr.name,
       %{type: normalize_type(attr.type, attr.constraints), allow_nil?: attr.allow_nil?}}
    end)
  end

  defp extract_resource_relationships(resource) do
    resource
    |> Ash.Resource.Info.public_relationships()
    |> Map.new(fn rel ->
      {rel.name, %{type: rel.type, destination: inspect(rel.destination)}}
    end)
  end

  defp extract_resource_relationships_full(resource) do
    resource
    |> Ash.Resource.Info.public_relationships()
    |> Map.new(fn rel ->
      {rel.name,
       %{type: rel.type, destination: inspect(rel.destination), cardinality: rel.cardinality}}
    end)
  end

  defp extract_resource_calculations(resource) do
    resource
    |> Ash.Resource.Info.public_calculations()
    |> Map.new(fn calc ->
      {calc.name, normalize_type(calc.type, calc.constraints || [])}
    end)
  end

  defp extract_resource_calculations_full(resource) do
    resource
    |> Ash.Resource.Info.public_calculations()
    |> Map.new(fn calc ->
      args =
        calc.arguments
        |> Map.new(fn arg -> {arg.name, normalize_argument_full(arg)} end)

      {calc.name,
       %{
         type: normalize_type(calc.type, calc.constraints || []),
         allow_nil?: calc.allow_nil?,
         arguments: args
       }}
    end)
  end

  defp extract_resource_aggregates(resource) do
    resource
    |> Ash.Resource.Info.public_aggregates()
    |> Map.new(fn agg ->
      {agg.name, agg.kind}
    end)
  end

  defp extract_resource_aggregates_full(resource) do
    resource
    |> Ash.Resource.Info.public_aggregates()
    |> Map.new(fn agg ->
      {agg.name, %{kind: agg.kind, field: agg.field}}
    end)
  end

  # ─────────────────────────────────────────────────────────────────
  # Generic Action Return Type Helpers
  # ─────────────────────────────────────────────────────────────────

  defp extract_action_return_fields(action) do
    case ActionIntrospection.action_returns_field_selectable_type?(action) do
      {:ok, :resource, module} ->
        {:resource, inspect(module)}

      {:ok, :array_of_resource, module} ->
        {:array_of_resource, inspect(module)}

      {:ok, :typed_map, fields} ->
        {:typed_map, normalize_typed_map_fields(fields)}

      {:ok, :array_of_typed_map, fields} ->
        {:array_of_typed_map, normalize_typed_map_fields(fields)}

      {:ok, :typed_struct, {module, fields}} ->
        {:typed_struct, {inspect(module), normalize_typed_map_fields(fields)}}

      {:ok, :array_of_typed_struct, {module, fields}} ->
        {:array_of_typed_struct, {inspect(module), normalize_typed_map_fields(fields)}}

      {:ok, :unconstrained_map, _} ->
        {:unconstrained_map, nil}

      _ ->
        {:other, normalize_type(action.returns, action.constraints || [])}
    end
  end

  defp extract_action_return_fields_full(action) do
    # For version signature, include more detail
    extract_action_return_fields(action)
  end

  defp normalize_typed_map_fields(fields) when is_list(fields) do
    fields
    |> Map.new(fn {name, field_constraints} ->
      type = Keyword.get(field_constraints, :type, :any)
      constraints = Keyword.get(field_constraints, :constraints, [])
      allow_nil = Keyword.get(field_constraints, :allow_nil?, true)
      {name, %{type: normalize_type(type, constraints), allow_nil?: allow_nil}}
    end)
  end

  defp normalize_typed_map_fields(_), do: %{}

  # ─────────────────────────────────────────────────────────────────
  # Normalization Helpers
  # ─────────────────────────────────────────────────────────────────

  defp normalize_argument(arg) do
    %{
      type: normalize_type(arg.type, arg.constraints || []),
      constraints: normalize_constraints(arg.constraints)
    }
  end

  defp normalize_argument_full(arg) do
    %{
      type: normalize_type(arg.type, arg.constraints || []),
      constraints: normalize_constraints(arg.constraints),
      allow_nil?: arg.allow_nil?,
      has_default?: not is_nil(arg.default)
    }
  end

  defp normalize_attribute(attr) do
    %{
      type: normalize_type(attr.type, attr.constraints || []),
      constraints: normalize_constraints(attr.constraints)
    }
  end

  defp normalize_attribute_full(attr) do
    %{
      type: normalize_type(attr.type, attr.constraints || []),
      constraints: normalize_constraints(attr.constraints),
      allow_nil?: attr.allow_nil?,
      has_default?: not is_nil(attr.default)
    }
  end

  defp normalize_type(type, constraints) do
    # Unwrap NewTypes to get consistent hashing
    {unwrapped_type, full_constraints} =
      AshTypescript.TypeSystem.Introspection.unwrap_new_type(type, constraints)

    case unwrapped_type do
      {:array, inner_type} ->
        %{array: normalize_type(inner_type, Keyword.get(full_constraints, :items, []))}

      :union ->
        # Normalize union types
        types = Keyword.get(full_constraints, :types, [])

        normalized_types =
          types
          |> Map.new(fn {member_name, member_opts} ->
            member_type = Keyword.get(member_opts, :type)
            member_constraints = Keyword.get(member_opts, :constraints, [])
            {member_name, normalize_type(member_type, member_constraints)}
          end)

        %{union: normalized_types}

      type ->
        type_name = inspect(type)
        normalized_constraints = normalize_constraints(full_constraints)

        if normalized_constraints == %{} do
          type_name
        else
          %{type: type_name, constraints: normalized_constraints}
        end
    end
  end

  defp normalize_constraints(nil), do: %{}

  defp normalize_constraints(constraints) when is_list(constraints) do
    # Only include constraints that affect the TypeScript interface
    constraints
    |> Keyword.take([
      :one_of,
      :min,
      :max,
      :min_length,
      :max_length,
      :fields,
      :instance_of,
      :items,
      :types,
      :match
    ])
    |> Map.new(fn {key, value} -> {key, normalize_constraint_value(value)} end)
  end

  defp normalize_constraints(_), do: %{}

  defp normalize_constraint_value(value) when is_list(value) do
    if Keyword.keyword?(value) do
      # Convert keyword lists to maps
      Map.new(value, fn {k, v} -> {k, normalize_constraint_value(v)} end)
    else
      Enum.map(value, &normalize_constraint_value/1)
    end
  end

  defp normalize_constraint_value(%Regex{} = regex), do: Regex.source(regex)
  defp normalize_constraint_value(value) when is_atom(value), do: inspect(value)
  defp normalize_constraint_value(value), do: value

  defp normalize_for_hashing(%Regex{} = regex) do
    # Convert Regex to its source string for consistent hashing
    Regex.source(regex)
  end

  defp normalize_for_hashing(map) when is_map(map) and not is_struct(map) do
    map
    |> Enum.map(fn {key, value} -> {key, normalize_for_hashing(value)} end)
    |> Enum.sort_by(fn {key, _} -> key end)
  end

  defp normalize_for_hashing(%{__struct__: struct_name} = struct) do
    # Handle other structs by converting to map first
    struct
    |> Map.from_struct()
    |> Map.put(:__struct__, struct_name)
    |> Enum.map(fn {key, value} -> {key, normalize_for_hashing(value)} end)
    |> Enum.sort_by(fn {key, _} -> key end)
  end

  defp normalize_for_hashing(list) when is_list(list) do
    Enum.map(list, &normalize_for_hashing/1)
  end

  defp normalize_for_hashing(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.map(&normalize_for_hashing/1)
    |> List.to_tuple()
  end

  defp normalize_for_hashing(value), do: value
end
