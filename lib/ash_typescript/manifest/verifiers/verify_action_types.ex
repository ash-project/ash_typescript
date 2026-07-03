# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.Verifiers.VerifyActionTypes do
  @moduledoc """
  Walks the persisted `%Ash.Info.Manifest{}` and validates that field names in
  every RPC entrypoint's argument types and `:action` return types are TypeScript-safe.

  Operates entirely on pre-resolved `%Ash.Info.Manifest.Type{}` structs — does not
  call `Ash.Resource.Info` or `Ash.Type.NewType` directly. NewType unwrapping has
  already been performed by the manifest generator, so a NewType subtype of `:map`
  appears as `kind: :map, module: NewTypeModule` in the manifest.

  Accepted-attribute inputs are skipped here; those are validated by the resource-
  level verifiers (`VerifyFieldNames`, `VerifyMapFieldNames`).
  """
  use Spark.Dsl.Verifier
  import AshTypescript.NameValidation, only: [invalid_name?: 1, make_name_better: 1]
  alias Ash.Info.Manifest.Type
  alias AshTypescript.Rpc.Codegen.Helpers.ActionIntrospection
  alias Spark.Dsl.Verifier

  @impl true
  def verify(dsl) do
    manifest = Verifier.get_persisted(dsl, :manifest)
    resource_lookup = Verifier.get_persisted(dsl, :resource_lookup)

    do_verify(manifest, resource_lookup)
  end

  defp do_verify(nil, _resource_lookup), do: :ok

  defp do_verify(%Ash.Info.Manifest{} = manifest, resource_lookup) do
    type_lookup = build_type_lookup(manifest)

    errors =
      Enum.flat_map(manifest.entrypoints, fn entrypoint ->
        validate_entrypoint(entrypoint, resource_lookup, type_lookup)
      end)

    case errors do
      [] -> :ok
      _ -> format_validation_errors(errors)
    end
  end

  # Index manifest.types by module so `:type_ref` and `:embedded_resource`
  # references can resolve to the full standalone definition in one hop.
  defp build_type_lookup(%Ash.Info.Manifest{types: types}) do
    Map.new(types, fn %Type{module: mod} = t -> {mod, t} end)
  end

  defp validate_entrypoint(entrypoint, resource_lookup, type_lookup) do
    resource = entrypoint.resource
    action = entrypoint.action
    rpc_name = rpc_name(entrypoint, action)

    validate_return_type(resource, rpc_name, action, type_lookup) ++
      validate_input_types(resource, rpc_name, action, resource_lookup, type_lookup)
  end

  defp rpc_name(entrypoint, action) do
    case get_in(entrypoint.config, [:ash_typescript, :rpc_action]) do
      %{name: name} -> name
      _ -> action.name
    end
  end

  # Only `:action` (generic) actions need return-type validation — CRUD actions
  # return the resource itself, which is validated at the resource level.
  defp validate_return_type(
         resource,
         rpc_name,
         %{type: :action, returns: %Type{} = returns} = action,
         type_lookup
       ) do
    validate_type(
      resource,
      returns,
      {:return_type, rpc_name, action.name},
      MapSet.new(),
      type_lookup
    )
  end

  defp validate_return_type(_resource, _rpc_name, _action, _type_lookup), do: []

  defp validate_input_types(resource, rpc_name, action, resource_lookup, type_lookup) do
    Enum.flat_map(action.inputs || [], fn input ->
      if ActionIntrospection.accepted_attribute?(resource, input.name, resource_lookup) do
        []
      else
        context = {:argument, rpc_name, action.name, input.name}
        validate_type(resource, input.type, context, MapSet.new(), type_lookup)
      end
    end)
  end

  # ─────────────────────────────────────────────────────────────────
  # Type walking
  # ─────────────────────────────────────────────────────────────────

  defp validate_type(_resource, nil, _context, _visited, _type_lookup), do: []

  defp validate_type(
         resource,
         %Type{kind: :array, item_type: item},
         context,
         visited,
         type_lookup
       ) do
    validate_type(resource, item, context, visited, type_lookup)
  end

  defp validate_type(resource, %Type{kind: :struct} = type, context, visited, type_lookup) do
    cond do
      # Manifest already populated `.fields` (e.g. NewType subtype of :struct
      # whose `fields:` constraint resolved successfully during generation).
      is_list(type.fields) and type.fields != [] ->
        validate_field_list(resource, type, context, visited, type_lookup)

      # `Ash.TypedStruct` and other NewType-of-struct modules: unwrap to read
      # the declared field constraints.
      is_atom(type.instance_of) and Ash.Type.NewType.new_type?(type.instance_of) ->
        validate_new_type_callback(resource, type.instance_of, context, visited, type_lookup)

      # Plain Elixir structs that opt in via `typed_struct_fields/0` aren't
      # known to the manifest builder — fall back to direct introspection.
      is_atom(type.instance_of) and function_exported?(type.instance_of, :typed_struct_fields, 0) ->
        validate_typed_struct_callback(resource, type.instance_of, context, visited, type_lookup)

      true ->
        []
    end
  end

  # `kind: :unknown` covers custom `use Ash.Type` modules — the manifest doesn't
  # categorize them, so introspect callbacks directly.
  defp validate_type(
         resource,
         %Type{kind: :unknown, module: mod} = type,
         context,
         visited,
         type_lookup
       )
       when is_atom(mod) and not is_nil(mod) do
    constraints = type.constraints || []

    cond do
      composite_type?(mod, constraints) ->
        validate_composite_callback(resource, mod, constraints, context, visited, type_lookup)

      function_exported?(mod, :typed_struct_fields, 0) ->
        validate_typed_struct_callback(resource, mod, context, visited, type_lookup)

      true ->
        []
    end
  end

  defp validate_type(resource, %Type{kind: kind} = type, context, visited, type_lookup)
       when kind in [:map, :keyword, :tuple] do
    validate_field_list(resource, type, context, visited, type_lookup)
  end

  defp validate_type(
         resource,
         %Type{kind: :union, members: members},
         context,
         visited,
         type_lookup
       )
       when is_list(members) do
    Enum.flat_map(members, fn %{type: member_type} ->
      validate_type(resource, member_type, context, visited, type_lookup)
    end)
  end

  defp validate_type(
         resource,
         %Type{kind: :embedded_resource} = type,
         context,
         visited,
         type_lookup
       ) do
    case resource_module(type) do
      nil -> []
      mod -> visit_embedded(resource, mod, context, visited, type_lookup)
    end
  end

  defp validate_type(resource, %Type{kind: :resource} = type, context, visited, type_lookup) do
    case resource_module(type) do
      nil -> []
      mod -> visit_resource_ref(resource, mod, context, visited, type_lookup)
    end
  end

  # Named types (NewType subtypes, enums) appear as `:type_ref` references —
  # walk the full definition stored in `manifest.types`.
  defp validate_type(resource, %Type{kind: :type_ref, module: mod}, context, visited, type_lookup)
       when not is_nil(mod) do
    if MapSet.member?(visited, mod) do
      []
    else
      case Map.get(type_lookup, mod) do
        %Type{} = resolved ->
          validate_type(resource, resolved, context, MapSet.put(visited, mod), type_lookup)

        _ ->
          []
      end
    end
  end

  defp validate_type(_resource, _other, _context, _visited, _type_lookup), do: []

  defp resource_module(%Type{resource_module: mod}) when not is_nil(mod), do: mod
  defp resource_module(%Type{instance_of: mod}) when not is_nil(mod), do: mod
  defp resource_module(_), do: nil

  # Walks `.fields` (for :map, :keyword, :struct) or `.element_types` (for :tuple)
  # — uses Type.get_fields/1 to handle both uniformly.
  defp validate_field_list(resource, %Type{} = type, context, visited, type_lookup) do
    field_descriptors = Type.get_fields(type)
    mappings = mapping_module_for(type) |> mappings_from_module()

    Enum.flat_map(field_descriptors, fn %{name: field_name, type: field_type} ->
      mapped_name = Map.get(mappings, field_name, field_name)
      field_error_kind = field_error_kind(type)

      name_errors =
        if invalid_name?(mapped_name) do
          [{resource, context, field_error_kind, field_name, make_name_better(field_name)}]
        else
          []
        end

      name_errors ++ validate_type(resource, field_type, context, visited, type_lookup)
    end)
  end

  defp field_error_kind(%Type{kind: :struct}), do: :struct_field
  defp field_error_kind(_), do: :field

  defp validate_new_type_callback(resource, new_type_module, context, visited, type_lookup) do
    if MapSet.member?(visited, new_type_module) do
      []
    else
      visited = MapSet.put(visited, new_type_module)
      mappings = mappings_from_module(new_type_module)

      constraints =
        case new_type_module.do_init([]) do
          {:ok, merged} -> merged
          _ -> []
        end

      fields = Keyword.get(constraints, :fields, [])

      Enum.flat_map(fields, fn {field_name, field_config} ->
        mapped_name = Map.get(mappings, field_name, field_name)

        name_errors =
          if invalid_name?(mapped_name) do
            [{resource, context, :struct_field, field_name, make_name_better(field_name)}]
          else
            []
          end

        field_type = Keyword.get(field_config, :type)
        field_constraints = Keyword.get(field_config, :constraints, [])

        nested_errors =
          if field_type do
            resolved =
              Ash.Info.Manifest.Generator.TypeResolver.resolve(field_type, field_constraints)

            validate_type(resource, resolved, context, visited, type_lookup)
          else
            []
          end

        name_errors ++ nested_errors
      end)
    end
  end

  defp composite_type?(mod, constraints) do
    function_exported?(mod, :composite?, 1) and mod.composite?(constraints)
  rescue
    _ -> false
  end

  defp validate_composite_callback(
         resource,
         type_module,
         constraints,
         context,
         visited,
         type_lookup
       ) do
    if MapSet.member?(visited, type_module) do
      []
    else
      visited = MapSet.put(visited, type_module)
      mappings = mappings_from_module(type_module)

      composite_fields =
        if function_exported?(type_module, :composite_types, 1) do
          type_module.composite_types(constraints)
        else
          []
        end

      Enum.flat_map(composite_fields, fn field_def ->
        {field_name, field_type, field_constraints} =
          case field_def do
            {name, storage_key, ftype, fconstraints} when is_atom(storage_key) ->
              {name, ftype, fconstraints}

            {name, ftype, fconstraints} ->
              {name, ftype, fconstraints}
          end

        mapped_name = Map.get(mappings, field_name, field_name)

        name_errors =
          if invalid_name?(mapped_name) do
            [{resource, context, :composite_field, field_name, make_name_better(field_name)}]
          else
            []
          end

        nested_errors =
          if field_type do
            resolved =
              Ash.Info.Manifest.Generator.TypeResolver.resolve(field_type, field_constraints)

            validate_type(resource, resolved, context, visited, type_lookup)
          else
            []
          end

        name_errors ++ nested_errors
      end)
    end
  end

  defp validate_typed_struct_callback(resource, struct_module, context, visited, type_lookup) do
    if MapSet.member?(visited, struct_module) do
      []
    else
      visited = MapSet.put(visited, struct_module)
      mappings = mappings_from_module(struct_module)

      struct_module.typed_struct_fields()
      |> Enum.flat_map(fn {field_name, field_opts} ->
        mapped_name = Map.get(mappings, field_name, field_name)

        name_errors =
          if invalid_name?(mapped_name) do
            [{resource, context, :typed_struct_field, field_name, make_name_better(field_name)}]
          else
            []
          end

        # Recurse into the field's declared type via TypeResolver (raw Ash type → manifest Type)
        field_type = Keyword.get(field_opts, :type)
        field_constraints = Keyword.get(field_opts, :constraints, [])

        nested_errors =
          if field_type do
            resolved =
              Ash.Info.Manifest.Generator.TypeResolver.resolve(field_type, field_constraints)

            validate_type(resource, resolved, context, visited, type_lookup)
          else
            []
          end

        name_errors ++ nested_errors
      end)
    end
  end

  # For a Type carrying mappings, the relevant module is `instance_of` (struct/NewType
  # subtypes), falling back to `module` (raw NewType subtype of :map/:keyword/:tuple
  # has `instance_of: nil` but `module:` set to the NewType).
  defp mapping_module_for(%Type{instance_of: mod}) when not is_nil(mod), do: mod
  defp mapping_module_for(%Type{module: mod}) when not is_nil(mod), do: mod
  defp mapping_module_for(_), do: nil

  defp mappings_from_module(nil), do: %{}

  defp mappings_from_module(mod) when is_atom(mod) do
    # `Code.ensure_loaded?/1` before `function_exported?/3` — modules not yet
    # loaded into the BEAM report no exported functions. Without this, sequential
    # test runs (where Mix's compiled artifacts haven't been auto-loaded) cause
    # the verifier to falsely flag mapped field names as invalid.
    if Code.ensure_loaded?(mod) and function_exported?(mod, :typescript_field_names, 0) do
      Map.new(mod.typescript_field_names())
    else
      %{}
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Embedded resource / regular resource walking
  # ─────────────────────────────────────────────────────────────────

  defp visit_embedded(resource, embedded_module, context, visited, type_lookup) do
    if MapSet.member?(visited, embedded_module) do
      []
    else
      visited = MapSet.put(visited, embedded_module)
      mappings = embedded_resource_mappings(embedded_module)

      validate_resource_module_fields(
        resource,
        embedded_module,
        :embedded_field,
        mappings,
        context,
        visited,
        type_lookup
      )
    end
  end

  defp visit_resource_ref(resource, target_resource, context, visited, type_lookup) do
    if MapSet.member?(visited, target_resource) do
      []
    else
      visited = MapSet.put(visited, target_resource)
      mappings = embedded_resource_mappings(target_resource)

      validate_resource_module_fields(
        resource,
        target_resource,
        :resource_field,
        mappings,
        context,
        visited,
        type_lookup
      )
    end
  end

  defp embedded_resource_mappings(resource_module) do
    if AshTypescript.Resource.Info.typescript_resource?(resource_module) do
      field_names = AshTypescript.Resource.Info.typescript_field_names!(resource_module)
      Map.new(field_names)
    else
      %{}
    end
  end

  defp validate_resource_module_fields(
         resource,
         target,
         error_kind,
         mappings,
         context,
         visited,
         type_lookup
       ) do
    attributes = Ash.Resource.Info.public_attributes(target)

    calculations =
      target
      |> Ash.Resource.Info.public_calculations()
      |> Enum.filter(fn calc -> Map.get(calc, :field?, true) end)

    aggregates = Ash.Resource.Info.public_aggregates(target)
    relationships = Ash.Resource.Info.public_relationships(target)

    attr_and_calc_errors =
      (attributes ++ calculations)
      |> Enum.flat_map(fn field ->
        mapped_name = Map.get(mappings, field.name, field.name)

        name_errors =
          if invalid_name?(mapped_name) do
            [{resource, context, error_kind, field.name, make_name_better(field.name)}]
          else
            []
          end

        nested_errors =
          validate_resource_field_type(resource, field, context, visited, type_lookup)

        name_errors ++ nested_errors
      end)

    other_field_errors =
      (aggregates ++ relationships)
      |> Enum.flat_map(fn field ->
        mapped_name = Map.get(mappings, field.name, field.name)

        if invalid_name?(mapped_name) do
          [{resource, context, error_kind, field.name, make_name_better(field.name)}]
        else
          []
        end
      end)

    attr_and_calc_errors ++ other_field_errors
  end

  # Resource attributes/calcs still expose raw Ash types here. Re-enter the type
  # walker by resolving to a manifest Type on the fly via the cached lookup.
  defp validate_resource_field_type(resource, field, context, visited, type_lookup) do
    type =
      Ash.Info.Manifest.Generator.TypeResolver.resolve(field.type, field.constraints || [])

    validate_type(resource, type, context, visited, type_lookup)
  end

  # ─────────────────────────────────────────────────────────────────
  # Error formatting (matches the legacy `Rpc.Verifiers.VerifyActionTypes` format)
  # ─────────────────────────────────────────────────────────────────

  defp format_validation_errors(errors) do
    grouped =
      Enum.group_by(errors, fn {_resource, context, _field_type, _field_name, _suggested} ->
        context
      end)

    message_parts = Enum.map_join(grouped, "\n\n", &format_error_group/1)

    {:error,
     Spark.Error.DslError.exception(
       message: """
       Invalid field names found in action return types or argument types.
       These patterns are not allowed in TypeScript generation.

       #{message_parts}

       To fix this:
       - For map/keyword/tuple types: Create a custom Ash.Type.NewType and define the `typescript_field_names/0` callback
       - For typed structs: Define the `typescript_field_names/0` callback on the struct module
       - For custom composite types: Define the `typescript_field_names/0` callback on the custom type module
       - For embedded resources: Use the `field_names` option in the resource's typescript DSL block
       - For action arguments: Use the `argument_names` option in the resource's typescript DSL block
       """
     )}
  end

  defp format_error_group({context, errors}) do
    context_description = format_context(context)

    field_suggestions =
      Enum.map_join(errors, "\n", fn {_resource, _context, field_type, field_name, suggested} ->
        "    - #{field_type} #{field_name} -> #{suggested}"
      end)

    "#{context_description}:\n#{field_suggestions}"
  end

  defp format_context({:return_type, rpc_name, action_name}) do
    "Invalid field names in return type of RPC action #{rpc_name} (action: #{action_name})"
  end

  defp format_context({:argument, rpc_name, action_name, arg_name}) do
    "Invalid field names in argument #{arg_name} of RPC action #{rpc_name} (action: #{action_name})"
  end
end
