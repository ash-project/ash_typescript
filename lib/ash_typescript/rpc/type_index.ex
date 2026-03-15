# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.TypeIndex do
  @moduledoc """
  Pre-computed type metadata index for O(1) runtime lookups.

  Pre-computes module-level type facts (NewType unwrapping, field name maps,
  embedded resource status) from the AshApiSpec type graph for O(1) lookups.

  Built once from `resource_lookups` and threaded through all runtime processing
  functions via the `%Request{}` struct.

  ## What's indexed per type module

  - `new_type?` — whether the module is an `Ash.Type.NewType`
  - `subtype` — the unwrapped subtype (if NewType)
  - `has_ts_field_names?` — whether `typescript_field_names/0` callback exists
  - `field_names` / `field_names_reverse` — pre-computed name mapping tables
  - `resource?` / `embedded_resource?` — Ash resource classification
  - `default_constraints` — cached `do_init([])` result with `instance_of` augmentation
  """

  alias AshApiSpec.Generator.TypeResolver

  @type type_entry :: %{
          new_type?: boolean(),
          subtype: atom() | nil,
          has_ts_field_names?: boolean(),
          field_names: %{atom() => String.t()},
          field_names_reverse: %{String.t() => atom()},
          resource?: boolean(),
          embedded_resource?: boolean(),
          default_constraints: keyword() | nil
        }

  @type t :: %{atom() => type_entry()}

  # ---------------------------------------------------------------------------
  # Build
  # ---------------------------------------------------------------------------

  @doc """
  Builds a TypeIndex by walking all type modules in the resource_lookups.

  Discovers every type module referenced by resource fields, action arguments,
  action returns, metadata, relationships, and nested types (arrays, unions,
  typed structs/maps/keywords/tuples). Pre-computes module-level facts for each.
  """
  @spec build(%{atom() => AshApiSpec.Resource.t()} | nil, AshApiSpec.action_lookup()) :: t()
  def build(resource_lookups, action_lookup \\ %{})
  def build(nil, _action_lookup), do: %{}

  def build(resource_lookups, action_lookup) when is_map(resource_lookups) do
    # Collect type modules from resources (fields, relationships)
    type_modules = collect_type_modules(resource_lookups)

    # Collect type modules from action entrypoints (arguments, returns, metadata)
    action_type_modules = collect_type_modules_from_actions(action_lookup)

    # Also include resource modules (for is_embedded_resource? / resource? checks)
    resource_modules = MapSet.new(Map.keys(resource_lookups))

    all_modules =
      type_modules
      |> MapSet.union(action_type_modules)
      |> MapSet.union(resource_modules)

    Map.new(all_modules, fn module -> {module, build_entry(module)} end)
  end

  # ---------------------------------------------------------------------------
  # Lookup Functions
  # ---------------------------------------------------------------------------

  @doc """
  Unwraps a NewType using pre-computed index facts.

  For the common case where `constraints` is `[]`, returns the cached
  `default_constraints` (including `instance_of` augmentation) without
  calling `do_init/1` at runtime.

  Falls back to `TypeResolver.unwrap_new_type/2` for types not in the index.
  """
  @spec unwrap_new_type(t(), atom(), keyword()) :: {atom(), keyword()}
  def unwrap_new_type(index, type, constraints) when is_atom(type) do
    case Map.get(index, type) do
      %{new_type?: true, subtype: subtype, default_constraints: default_constraints}
      when constraints == [] ->
        {subtype, default_constraints}

      %{new_type?: true, subtype: subtype, has_ts_field_names?: has_names} ->
        merged_constraints =
          case type.do_init(constraints) do
            {:ok, merged} -> merged
            {:error, _} -> constraints
          end

        augmented =
          if has_names and not Keyword.has_key?(merged_constraints, :instance_of) do
            Keyword.put(merged_constraints, :instance_of, type)
          else
            merged_constraints
          end

        {subtype, augmented}

      %{new_type?: false} ->
        {type, constraints}

      nil ->
        {unwrapped, merged} = TypeResolver.unwrap_new_type(type, constraints)

        augmented =
          if unwrapped != type and
               Code.ensure_loaded?(type) == true and
               function_exported?(type, :typescript_field_names, 0) and
               not Keyword.has_key?(merged, :instance_of) do
            Keyword.put(merged, :instance_of, type)
          else
            merged
          end

        {unwrapped, augmented}
    end
  end

  def unwrap_new_type(_index, type, constraints), do: {type, constraints}

  @doc """
  Checks if a module has a `typescript_field_names/0` callback.
  """
  @spec has_ts_field_names?(t(), atom() | nil) :: boolean()
  def has_ts_field_names?(_index, nil), do: false

  def has_ts_field_names?(index, module) when is_atom(module) do
    case Map.get(index, module) do
      %{has_ts_field_names?: val} -> val
      nil -> has_field_names_callback?(module)
    end
  end

  def has_ts_field_names?(_index, _), do: false

  @doc """
  Gets the pre-computed `typescript_field_names` map (internal → client).
  """
  @spec field_names(t(), atom() | nil) :: %{atom() => String.t()}
  def field_names(_index, nil), do: %{}

  def field_names(index, module) when is_atom(module) do
    case Map.get(index, module) do
      %{field_names: names} -> names
      nil -> get_field_names_map(module)
    end
  end

  def field_names(_index, _), do: %{}

  @doc """
  Gets the pre-computed reverse field names map (client → internal).
  """
  @spec field_names_reverse(t(), atom() | nil) :: %{String.t() => atom()}
  def field_names_reverse(_index, nil), do: %{}

  def field_names_reverse(index, module) when is_atom(module) do
    case Map.get(index, module) do
      %{field_names_reverse: names} -> names
      nil -> get_field_names_map(module) |> Map.new(fn {k, v} -> {v, k} end)
    end
  end

  def field_names_reverse(_index, _), do: %{}

  @doc """
  Checks if a module is an embedded Ash resource.
  """
  @spec embedded_resource?(t(), atom()) :: boolean()
  def embedded_resource?(_index, module) when not is_atom(module), do: false

  def embedded_resource?(index, module) do
    case Map.get(index, module) do
      %{embedded_resource?: val} -> val
      nil -> is_ash_embedded_resource?(module)
    end
  end

  @doc """
  Checks if a module is an Ash resource (embedded or not).
  """
  @spec resource?(t(), atom()) :: boolean()
  def resource?(_index, module) when not is_atom(module), do: false

  def resource?(index, module) do
    case Map.get(index, module) do
      %{resource?: val} -> val
      nil -> is_atom(module) and Ash.Resource.Info.resource?(module)
    end
  end

  # ---------------------------------------------------------------------------
  # Inline Utilities (no index needed)
  # ---------------------------------------------------------------------------

  @doc """
  Checks if constraints include non-empty field definitions.

  Inlined replacement for `Introspection.has_field_constraints?/1` — no index
  needed since this is a trivial keyword list check.
  """
  @spec has_field_constraints?(keyword()) :: boolean()
  def has_field_constraints?(constraints) when is_list(constraints) do
    case Keyword.get(constraints, :fields) do
      nil -> false
      [] -> false
      _fields -> true
    end
  end

  def has_field_constraints?(_), do: false

  @doc """
  Checks if constraints specify an `instance_of` that is an Ash resource.

  Uses the index for the resource check when available.
  """
  @spec is_resource_instance_of?(t(), keyword()) :: boolean()
  def is_resource_instance_of?(index, constraints) when is_list(constraints) do
    case Keyword.get(constraints, :instance_of) do
      nil -> false
      module -> resource?(index, module)
    end
  end

  def is_resource_instance_of?(_index, _), do: false

  @doc """
  Gets the type and constraints for a field from field specs.

  Delegate to `Introspection.get_field_spec_type/2` — this is a constraint-level
  lookup, not a module-level one, so indexing doesn't apply.
  """
  @spec get_field_spec_type(keyword(), atom()) :: {atom() | nil, keyword()}
  def get_field_spec_type(field_specs, field_name) when is_list(field_specs) do
    case Enum.find(field_specs, fn {name, _spec} -> name == field_name end) do
      nil -> {nil, []}
      {_name, spec} -> {Keyword.get(spec, :type), Keyword.get(spec, :constraints, [])}
    end
  end

  def get_field_spec_type(_, _), do: {nil, []}

  # ---------------------------------------------------------------------------
  # Private: Type Module Collection
  # ---------------------------------------------------------------------------

  defp collect_type_modules(resource_lookups) do
    resource_lookups
    |> Enum.flat_map(fn {_module, resource} -> collect_from_resource(resource) end)
    |> MapSet.new()
  end

  defp collect_type_modules_from_actions(action_lookup) do
    action_lookup
    |> Enum.flat_map(fn {_key, action} ->
      arg_modules = Enum.flat_map(action.arguments, &collect_from_type(&1.type))

      returns_modules =
        if action.returns, do: collect_from_type(action.returns), else: []

      metadata_modules =
        Enum.flat_map(action.metadata || [], &collect_from_type(&1.type))

      arg_modules ++ returns_modules ++ metadata_modules
    end)
    |> MapSet.new()
  end

  defp collect_from_resource(%AshApiSpec.Resource{} = resource) do
    field_modules =
      Enum.flat_map(Map.values(resource.fields), &collect_from_type(&1.type))

    rel_modules =
      Enum.flat_map(Map.values(resource.relationships), fn rel -> [rel.destination] end)

    field_modules ++ rel_modules
  end

  defp collect_from_type(nil), do: []

  defp collect_from_type(%AshApiSpec.Type{} = type) do
    own = if type.module && is_atom(type.module), do: [type.module], else: []

    instance_of =
      if type.instance_of && is_atom(type.instance_of), do: [type.instance_of], else: []

    resource_module =
      if type.resource_module && is_atom(type.resource_module),
        do: [type.resource_module],
        else: []

    children =
      case type.kind do
        :array ->
          if type.item_type, do: collect_from_type(type.item_type), else: []

        :union ->
          Enum.flat_map(type.members || [], fn m -> collect_from_type(m.type) end)

        kind when kind in [:struct, :map, :keyword] ->
          Enum.flat_map(type.fields || [], fn f -> collect_from_type(f.type) end)

        :tuple ->
          Enum.flat_map(type.element_types || [], fn e -> collect_from_type(e.type) end)

        _ ->
          []
      end

    own ++ instance_of ++ resource_module ++ children
  end

  # ---------------------------------------------------------------------------
  # Private: Entry Builder
  # ---------------------------------------------------------------------------

  defp build_entry(module) when is_atom(module) do
    loaded? = Code.ensure_loaded?(module) == true
    new_type? = loaded? and Ash.Type.NewType.new_type?(module)

    subtype = if new_type?, do: Ash.Type.NewType.subtype_of(module), else: nil

    has_ts_field_names? =
      loaded? and function_exported?(module, :typescript_field_names, 0)

    field_names =
      if has_ts_field_names?, do: module.typescript_field_names() |> Map.new(), else: %{}

    field_names_reverse =
      Map.new(field_names, fn {internal, client} -> {client, internal} end)

    resource? = loaded? and Ash.Resource.Info.resource?(module)
    embedded_resource? = resource? and Ash.Resource.Info.embedded?(module)

    # Pre-compute do_init([]) for NewTypes — the common case at runtime
    default_constraints =
      if new_type? do
        base =
          case module.do_init([]) do
            {:ok, constraints} -> constraints
            {:error, _} -> []
          end

        if has_ts_field_names? and not Keyword.has_key?(base, :instance_of) do
          Keyword.put(base, :instance_of, module)
        else
          base
        end
      else
        nil
      end

    %{
      new_type?: new_type?,
      subtype: subtype,
      has_ts_field_names?: has_ts_field_names?,
      field_names: field_names,
      field_names_reverse: field_names_reverse,
      resource?: resource?,
      embedded_resource?: embedded_resource?,
      default_constraints: default_constraints
    }
  end

  # ─────────────────────────────────────────────────────────────────
  # Fallback Helpers (for modules not in the index)
  # ─────────────────────────────────────────────────────────────────

  defp has_field_names_callback?(module) when is_atom(module) do
    Code.ensure_loaded?(module) == true and function_exported?(module, :typescript_field_names, 0)
  end

  defp get_field_names_map(module) when is_atom(module) do
    if has_field_names_callback?(module) do
      module.typescript_field_names() |> Map.new()
    else
      %{}
    end
  end

  defp is_ash_embedded_resource?(module) when is_atom(module) do
    Code.ensure_loaded?(module) == true and
      Ash.Resource.Info.resource?(module) and
      Ash.Resource.Info.embedded?(module)
  end
end
