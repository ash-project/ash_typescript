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

  Custom types with declared fields are `:type_ref`s to `kind: :map`
  definitions in `manifest.types`, checked like any typed map with their
  decorated names (`AshRpc.Manifest.Custom.type_field_name_overrides/1`).
  Other custom types (`kind: :unknown`) have no fields to check.

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
      %{},
      type_lookup
    )
  end

  defp validate_return_type(_resource, _rpc_name, _action, _type_lookup), do: []

  defp validate_input_types(resource, rpc_name, action, resource_lookup, type_lookup) do
    Enum.flat_map(action.inputs, fn input ->
      if ActionIntrospection.accepted_attribute?(resource, input.name, resource_lookup) do
        []
      else
        context = {:argument, rpc_name, action.name, input.name}
        validate_type(resource, input.type, context, %{}, type_lookup)
      end
    end)
  end

  # ─────────────────────────────────────────────────────────────────
  # Type walking
  #
  # `visited` is a module => true map used as a cycle guard. It is a plain map
  # rather than a MapSet because it crosses many mutually-recursive private
  # function boundaries, where dialyzer loses MapSet's opacity and reports
  # spurious `call_without_opaque` warnings.
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
    # Manifest already populated `.fields` (e.g. NewType subtype of :struct
    # whose `fields:` constraint resolved successfully during generation).
    # Decoration rejects a `:struct` without `fields` anywhere it can reach,
    # declared custom types' fields included, so there is nothing else to read.
    if is_list(type.fields) and type.fields != [] do
      validate_field_list(resource, type, context, visited, type_lookup)
    else
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
    if Map.has_key?(visited, mod) do
      []
    else
      case Map.get(type_lookup, mod) do
        %Type{} = resolved ->
          validate_type(resource, resolved, context, Map.put(visited, mod, true), type_lookup)

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
  # — uses Type.get_fields/1 to handle both uniformly. A field's name is its
  # decorated override (`typescript_field_names/0`, or a declared custom type's
  # `client_name:`), else the field name itself.
  defp validate_field_list(resource, %Type{} = type, context, visited, type_lookup) do
    field_descriptors = Type.get_fields(type)
    mappings = AshRpc.Manifest.Custom.type_field_name_overrides(type)

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

  # ─────────────────────────────────────────────────────────────────
  # Embedded resource / regular resource walking
  # ─────────────────────────────────────────────────────────────────

  defp visit_embedded(resource, embedded_module, context, visited, type_lookup) do
    if Map.has_key?(visited, embedded_module) do
      []
    else
      visited = Map.put(visited, embedded_module, true)
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
    if Map.has_key?(visited, target_resource) do
      []
    else
      visited = Map.put(visited, target_resource, true)
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
       - For custom types with declared fields: Define the `typescript_field_names/0` callback on the custom type module, or set `client_name` on the fields of its `map` entry in the manifest's `custom_types` section
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
