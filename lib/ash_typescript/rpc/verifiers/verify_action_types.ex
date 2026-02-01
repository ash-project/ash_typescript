# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Verifiers.VerifyActionTypes do
  @moduledoc """
  Verifies that field names in action return types and argument types are valid for TypeScript.

  For each exposed RPC action, this verifier checks:
  1. Return type field names (for generic actions with `:action` type)
  2. Argument type field names (for all action types)

  This ensures that map, keyword, tuple, struct, embedded resource, and union types
  used in action signatures have valid TypeScript-compatible field names.
  """
  use Spark.Dsl.Verifier
  alias AshTypescript.TypeSystem.Introspection
  alias Spark.Dsl.Verifier

  # Suppress dialyzer warnings about MapSet opaque type - these are false positives
  # when passing MapSet through recursive function calls
  @dialyzer {:nowarn_function, validate_unwrapped_type: 5}
  @dialyzer {:nowarn_function, validate_type_field_names: 5}
  @dialyzer {:nowarn_function, validate_struct_type: 4}
  @dialyzer {:nowarn_function, validate_typed_struct_fields: 4}
  @dialyzer {:nowarn_function, validate_new_type_fields: 4}
  @dialyzer {:nowarn_function, validate_embedded_resource: 4}
  @dialyzer {:nowarn_function, validate_resource_fields: 4}
  @dialyzer {:nowarn_function, validate_composite_type: 5}

  @impl true
  def verify(dsl) do
    dsl
    |> Verifier.get_entities([:typescript_rpc])
    |> Enum.flat_map(fn %{resource: resource, rpc_actions: rpc_actions} ->
      validate_rpc_actions(resource, rpc_actions)
    end)
    |> case do
      [] -> :ok
      errors -> format_validation_errors(errors)
    end
  end

  defp validate_rpc_actions(resource, rpc_actions) do
    Enum.flat_map(rpc_actions, fn rpc_action ->
      action = Ash.Resource.Info.action(resource, rpc_action.action)

      if action do
        return_type_errors = validate_return_type(resource, rpc_action, action)
        argument_type_errors = validate_argument_types(resource, rpc_action, action)
        return_type_errors ++ argument_type_errors
      else
        []
      end
    end)
  end

  # Validate return types for generic actions
  defp validate_return_type(resource, rpc_action, %{type: :action} = action) do
    case action.returns do
      nil ->
        []

      returns ->
        constraints = Map.get(action, :constraints, [])

        validate_type_field_names(
          resource,
          returns,
          constraints,
          {:return_type, rpc_action.name, action.name}
        )
    end
  end

  # CRUD actions return the resource itself, which is already validated by resource verifiers
  defp validate_return_type(_resource, _rpc_action, _action), do: []

  # Validate argument types for all actions
  defp validate_argument_types(resource, rpc_action, action) do
    action.arguments
    |> Enum.filter(& &1.public?)
    |> Enum.flat_map(fn argument ->
      validate_type_field_names(
        resource,
        argument.type,
        argument.constraints,
        {:argument, rpc_action.name, action.name, argument.name}
      )
    end)
  end

  # Type validation - handles various Ash types with field constraints
  # Uses a visited set to prevent infinite recursion on cyclical resource references

  defp validate_type_field_names(resource, type, constraints, context, visited \\ MapSet.new()) do
    # Handle array types
    {inner_type, inner_constraints} = unwrap_array_type(type, constraints)

    # Unwrap NewType if applicable
    {unwrapped_type, unwrapped_constraints} =
      Introspection.unwrap_new_type(inner_type, inner_constraints)

    validate_unwrapped_type(resource, unwrapped_type, unwrapped_constraints, context, visited)
  end

  defp unwrap_array_type({:array, inner_type}, constraints) do
    items_constraints = Keyword.get(constraints, :items, [])
    {inner_type, items_constraints}
  end

  defp unwrap_array_type(type, constraints), do: {type, constraints}

  defp validate_unwrapped_type(resource, type, constraints, context, visited) do
    cond do
      # Map, Keyword, or Tuple types with field constraints
      type in [Ash.Type.Map, Ash.Type.Keyword, Ash.Type.Tuple] ->
        validate_fields_constraint(resource, constraints, context, visited)

      # Union types - check each union member
      type == Ash.Type.Union ->
        validate_union_types(resource, constraints, context, visited)

      # Struct types - check if typed struct with fields
      type == Ash.Type.Struct ->
        validate_struct_type(resource, constraints, context, visited)

      # Embedded resources - check public fields (skip if already visited)
      Introspection.is_embedded_resource?(type) ->
        if MapSet.member?(visited, type) do
          []
        else
          validate_embedded_resource(resource, type, context, MapSet.put(visited, type))
        end

      # Regular Ash resources - check public fields (skip if already visited)
      is_atom(type) and Ash.Resource.Info.resource?(type) ->
        if MapSet.member?(visited, type) do
          []
        else
          validate_resource_fields(resource, type, context, MapSet.put(visited, type))
        end

      # Custom Ash.Type with composite types (skip if already visited)
      is_atom(type) and is_composite_type?(type, constraints) ->
        if MapSet.member?(visited, type) do
          []
        else
          validate_composite_type(resource, type, constraints, context, MapSet.put(visited, type))
        end

      # Primitives and other types - no field validation needed
      true ->
        []
    end
  end

  defp validate_fields_constraint(resource, constraints, context, visited) do
    case Keyword.get(constraints, :fields) do
      nil ->
        []

      fields ->
        # Check if there's a typescript_field_names mapping from instance_of
        field_name_mappings = get_field_name_mappings(constraints)

        Enum.flat_map(fields, fn {field_name, field_config} ->
          # Check if field name is mapped
          mapped_name = Map.get(field_name_mappings, field_name, field_name)

          # Check if the mapped field name is invalid
          name_errors =
            if invalid_name?(mapped_name) do
              [{resource, context, :field, field_name, make_name_better(field_name)}]
            else
              []
            end

          # Recursively check nested types
          field_type = Keyword.get(field_config, :type)
          field_constraints = Keyword.get(field_config, :constraints, [])

          nested_errors =
            if field_type do
              validate_type_field_names(resource, field_type, field_constraints, context, visited)
            else
              []
            end

          name_errors ++ nested_errors
        end)
    end
  end

  defp validate_union_types(resource, constraints, context, visited) do
    case Keyword.get(constraints, :types) do
      nil ->
        []

      types ->
        Enum.flat_map(types, fn {_type_name, type_config} ->
          type = Keyword.get(type_config, :type)
          type_constraints = Keyword.get(type_config, :constraints, [])
          validate_type_field_names(resource, type, type_constraints, context, visited)
        end)
    end
  end

  defp validate_struct_type(resource, constraints, context, visited) do
    # Check for instance_of constraint pointing to a typed struct or Ash resource
    case Keyword.get(constraints, :instance_of) do
      nil ->
        # Also check fields constraint for anonymous structs
        validate_fields_constraint(resource, constraints, context, visited)

      struct_module when is_atom(struct_module) ->
        cond do
          # Check if it's an Ash resource (embedded or regular) - skip if already visited
          Ash.Resource.Info.resource?(struct_module) ->
            if MapSet.member?(visited, struct_module) do
              []
            else
              validate_resource_fields(
                resource,
                struct_module,
                context,
                MapSet.put(visited, struct_module)
              )
            end

          # Check if it's a typed struct with typed_struct_fields/0 - skip if already visited
          function_exported?(struct_module, :typed_struct_fields, 0) ->
            if MapSet.member?(visited, struct_module) do
              []
            else
              validate_typed_struct_fields(
                resource,
                struct_module,
                context,
                MapSet.put(visited, struct_module)
              )
            end

          # Check if it's an Ash.Type.NewType (e.g., Ash.TypedStruct) - skip if already visited
          # Unwrap it to get the fields constraint
          Ash.Type.NewType.new_type?(struct_module) ->
            if MapSet.member?(visited, struct_module) do
              []
            else
              validate_new_type_fields(
                resource,
                struct_module,
                context,
                MapSet.put(visited, struct_module)
              )
            end

          true ->
            []
        end
    end
  end

  defp validate_typed_struct_fields(resource, struct_module, context, visited) do
    field_name_mappings = get_typed_struct_mappings(struct_module)

    struct_module.typed_struct_fields()
    |> Enum.flat_map(fn {field_name, field_opts} ->
      mapped_name = Map.get(field_name_mappings, field_name, field_name)

      # Check if the field name itself is invalid
      name_errors =
        if invalid_name?(mapped_name) do
          [{resource, context, :typed_struct_field, field_name, make_name_better(field_name)}]
        else
          []
        end

      # Recursively check nested types in field options
      field_type = Keyword.get(field_opts, :type)
      field_constraints = Keyword.get(field_opts, :constraints, [])

      nested_errors =
        if field_type do
          validate_type_field_names(resource, field_type, field_constraints, context, visited)
        else
          []
        end

      name_errors ++ nested_errors
    end)
  end

  defp validate_new_type_fields(resource, new_type_module, context, visited) do
    # Unwrap the NewType to get the underlying type and constraints
    {_unwrapped_type, unwrapped_constraints} =
      Introspection.unwrap_new_type(new_type_module, [])

    # Get field name mappings from the module if available
    field_name_mappings = get_typed_struct_mappings(new_type_module)

    # Validate fields from the unwrapped constraints
    case Keyword.get(unwrapped_constraints, :fields) do
      nil ->
        []

      fields ->
        Enum.flat_map(fields, fn {field_name, field_config} ->
          mapped_name = Map.get(field_name_mappings, field_name, field_name)

          # Check if the mapped field name is invalid
          name_errors =
            if invalid_name?(mapped_name) do
              [{resource, context, :struct_field, field_name, make_name_better(field_name)}]
            else
              []
            end

          # Recursively check nested types
          field_type = Keyword.get(field_config, :type)
          field_constraints = Keyword.get(field_config, :constraints, [])

          nested_errors =
            if field_type do
              validate_type_field_names(resource, field_type, field_constraints, context, visited)
            else
              []
            end

          name_errors ++ nested_errors
        end)
    end
  end

  defp validate_embedded_resource(resource, embedded_module, context, visited) do
    # Embedded resources have their own field name verifiers at the resource level
    # Here we check if any public fields have invalid names without mappings
    # AND recursively check nested types in attributes/calculations
    field_name_mappings = get_resource_field_mappings(embedded_module)

    attributes = Ash.Resource.Info.public_attributes(embedded_module)
    calculations = Ash.Resource.Info.public_calculations(embedded_module)
    aggregates = Ash.Resource.Info.public_aggregates(embedded_module)
    relationships = Ash.Resource.Info.public_relationships(embedded_module)

    # Check attribute and calculation field names AND their nested types
    attr_and_calc_errors =
      (attributes ++ calculations)
      |> Enum.flat_map(fn field ->
        mapped_name = Map.get(field_name_mappings, field.name, field.name)

        # Check if the field name itself is invalid
        name_errors =
          if invalid_name?(mapped_name) do
            [{resource, context, :embedded_field, field.name, make_name_better(field.name)}]
          else
            []
          end

        # Recursively check nested types in the field's type
        nested_errors =
          validate_type_field_names(resource, field.type, field.constraints, context, visited)

        name_errors ++ nested_errors
      end)

    # Check aggregate and relationship field names only (no nested type recursion needed)
    other_field_errors =
      (aggregates ++ relationships)
      |> Enum.flat_map(fn field ->
        mapped_name = Map.get(field_name_mappings, field.name, field.name)

        if invalid_name?(mapped_name) do
          [{resource, context, :embedded_field, field.name, make_name_better(field.name)}]
        else
          []
        end
      end)

    attr_and_calc_errors ++ other_field_errors
  end

  defp validate_resource_fields(resource, target_resource, context, visited) do
    # Regular resources referenced in return types (e.g., Ash.Type.Struct with instance_of)
    # Check field names AND recursively check nested types in attributes/calculations
    field_name_mappings = get_resource_field_mappings(target_resource)

    attributes = Ash.Resource.Info.public_attributes(target_resource)
    calculations = Ash.Resource.Info.public_calculations(target_resource)
    aggregates = Ash.Resource.Info.public_aggregates(target_resource)
    relationships = Ash.Resource.Info.public_relationships(target_resource)

    # Check attribute and calculation field names AND their nested types
    attr_and_calc_errors =
      (attributes ++ calculations)
      |> Enum.flat_map(fn field ->
        mapped_name = Map.get(field_name_mappings, field.name, field.name)

        # Check if the field name itself is invalid
        name_errors =
          if invalid_name?(mapped_name) do
            [{resource, context, :resource_field, field.name, make_name_better(field.name)}]
          else
            []
          end

        # Recursively check nested types in the field's type
        nested_errors =
          validate_type_field_names(resource, field.type, field.constraints, context, visited)

        name_errors ++ nested_errors
      end)

    # Check aggregate and relationship field names only (no nested type recursion needed)
    other_field_errors =
      (aggregates ++ relationships)
      |> Enum.flat_map(fn field ->
        mapped_name = Map.get(field_name_mappings, field.name, field.name)

        if invalid_name?(mapped_name) do
          [{resource, context, :resource_field, field.name, make_name_better(field.name)}]
        else
          []
        end
      end)

    attr_and_calc_errors ++ other_field_errors
  end

  # Custom Ash.Type composite type validation

  defp is_composite_type?(type, constraints) when is_atom(type) do
    # Check if the type implements composite?/1 and returns true
    function_exported?(type, :composite?, 1) and type.composite?(constraints)
  rescue
    _ -> false
  end

  defp is_composite_type?(_, _), do: false

  defp validate_composite_type(resource, type, constraints, context, visited) do
    # Get composite field definitions from composite_types/1 callback
    composite_fields =
      if function_exported?(type, :composite_types, 1) do
        type.composite_types(constraints)
      else
        []
      end

    # Get field name mappings from typescript_field_names callback if available
    field_name_mappings = get_typed_struct_mappings(type)

    Enum.flat_map(composite_fields, fn field_def ->
      # Handle both 3-tuple and 4-tuple formats:
      # {field_name, type, constraints} or {field_name, storage_key, type, constraints}
      {field_name, field_type, field_constraints} =
        case field_def do
          {name, storage_key, field_type, field_constraints} when is_atom(storage_key) ->
            {name, field_type, field_constraints}

          {name, field_type, field_constraints} ->
            {name, field_type, field_constraints}
        end

      mapped_name = Map.get(field_name_mappings, field_name, field_name)

      # Check if the field name itself is invalid
      name_errors =
        if invalid_name?(mapped_name) do
          [{resource, context, :composite_field, field_name, make_name_better(field_name)}]
        else
          []
        end

      # Recursively check nested types in the composite field
      nested_errors =
        if field_type do
          validate_type_field_names(resource, field_type, field_constraints, context, visited)
        else
          []
        end

      name_errors ++ nested_errors
    end)
  end

  # Helper functions for getting field name mappings

  defp get_field_name_mappings(constraints) do
    case Keyword.get(constraints, :instance_of) do
      nil ->
        %{}

      module when is_atom(module) ->
        if function_exported?(module, :typescript_field_names, 0) do
          module.typescript_field_names() |> Map.new()
        else
          %{}
        end
    end
  end

  defp get_typed_struct_mappings(struct_module) do
    if function_exported?(struct_module, :typescript_field_names, 0) do
      struct_module.typescript_field_names() |> Map.new()
    else
      %{}
    end
  end

  defp get_resource_field_mappings(resource_module) do
    if AshTypescript.Resource.Info.typescript_resource?(resource_module) do
      field_names = AshTypescript.Resource.Info.typescript_field_names!(resource_module)
      Map.new(field_names)
    else
      %{}
    end
  end

  # Name validation functions (consistent with VerifyRpc and VerifyMapFieldNames)

  @doc false
  def invalid_name?(name) do
    Regex.match?(~r/_+\d|\?/, to_string(name))
  end

  @doc false
  def make_name_better(name) do
    name
    |> to_string()
    |> String.replace(~r/_+\d/, fn v ->
      String.trim_leading(v, "_")
    end)
    |> String.replace("?", "")
  end

  # Error formatting

  defp format_validation_errors(errors) do
    grouped_errors =
      errors
      |> Enum.group_by(fn {_resource, context, _field_type, _field_name, _suggested} ->
        context
      end)

    message_parts = Enum.map_join(grouped_errors, "\n\n", &format_error_group/1)

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
