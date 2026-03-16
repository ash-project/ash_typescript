# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.ValidationErrorSchemas do
  @moduledoc """
  Generates validation error schemas for TypeScript RPC clients.

  This module uses a unified type-driven dispatch pattern for mapping Ash types
  to their corresponding validation error types. The core dispatcher `map_error_type/2`
  handles NewType unwrapping at entry and delegates to type-specific handlers.
  """

  import AshTypescript.Helpers
  import AshTypescript.Codegen, only: [build_resource_type_name: 1]

  alias AshTypescript.Rpc.Codegen.Helpers.ActionIntrospection

  # Filters to public arguments only. For spec actions, arguments are already
  # public-only. For raw Ash actions (from tests), filters on .public? field.
  defp filter_public_arguments(arguments) do
    Enum.filter(arguments, &Map.get(&1, :public?, true))
  end

  # ─────────────────────────────────────────────────────────────────
  # Core Dispatcher
  # ─────────────────────────────────────────────────────────────────

  @doc """
  Maps an Ash type to its corresponding validation error type.

  This is the unified dispatcher that handles all type-to-error-type mappings.
  NewTypes are unwrapped at entry for consistent handling.

  ## Parameters
  - `type` - The Ash type (atom, tuple, or module)
  - `constraints` - Type constraints (keyword list)

  ## Returns
  A TypeScript error type string (e.g., "string[]", "FooValidationErrors")
  """
  @spec map_error_type(atom() | tuple() | AshApiSpec.Type.t(), keyword()) :: String.t()
  def map_error_type(type, constraints \\ [])

  # Handle nil type
  def map_error_type(nil, _constraints), do: "string[]"

  # ── %AshApiSpec.Type{} dispatch ──────────────────────────────────
  def map_error_type(%AshApiSpec.Type{} = type_info, _constraints) do
    case type_info.kind do
      :type_ref ->
        full_type = AshApiSpec.Generator.TypeResolver.resolve_definition(type_info.module)
        map_error_type(full_type, [])

      :array ->
        inner_error = map_error_type(type_info.item_type, [])
        "#{inner_error}[]"

      kind when kind in [:resource, :embedded_resource] ->
        resource = type_info.resource_module || type_info.module
        map_resource_error(resource)

      :union ->
        union_types = Keyword.get(type_info.constraints || [], :types, [])
        build_union_error_type(union_types)

      kind when kind in [:map, :keyword, :tuple] ->
        map_typed_container_error(type_info.constraints || [])

      :struct ->
        map_struct_error(type_info.constraints || [])

      :enum ->
        "string[]"

      _ ->
        if is_custom_type?(type_info.module) do
          "#{type_info.module.typescript_type_name()}ValidationErrors"
        else
          "string[]"
        end
    end
  end

  # ── Raw Ash type dispatch ────────────────────────────────────────
  def map_error_type(type, constraints) do
    {unwrapped_type, full_constraints} =
      AshApiSpec.Generator.TypeResolver.unwrap_new_type(type, constraints)

    cond do
      # Arrays - recurse into inner type
      match?({:array, _}, type) ->
        {:array, inner_type} = type
        inner_constraints = Keyword.get(constraints, :items, [])
        inner_error = map_error_type(inner_type, inner_constraints)
        "#{inner_error}[]"

      # Custom types with typescript_type_name - check original type BEFORE using
      # unwrapped type, so NewTypes with custom type names are respected (issue #52)
      is_custom_type?(type) ->
        "#{type.typescript_type_name()}ValidationErrors"

      # Embedded resources
      is_embedded_resource?(unwrapped_type) ->
        map_resource_error(unwrapped_type)

      # Union types
      unwrapped_type == Ash.Type.Union ->
        build_union_error_type(Keyword.get(full_constraints, :types, []))

      # Typed containers (Map, Keyword, Tuple) with potential field constraints
      unwrapped_type in [Ash.Type.Map, Ash.Type.Keyword, Ash.Type.Tuple] ->
        map_typed_container_error(full_constraints)

      # Ash.Type.Struct - check for instance_of
      unwrapped_type == Ash.Type.Struct ->
        map_struct_error(full_constraints)

      # Types with fields and instance_of (TypedStruct pattern via NewType)
      Keyword.has_key?(full_constraints, :fields) and
          Keyword.has_key?(full_constraints, :instance_of) ->
        instance_of = Keyword.get(full_constraints, :instance_of)
        resource_name = build_resource_type_name(instance_of)
        "#{resource_name}ValidationErrors"

      # Enum types - just string errors
      Spark.implements_behaviour?(unwrapped_type, Ash.Type.Enum) ->
        "string[]"

      # All primitives and unknown types
      true ->
        "string[]"
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Type-Specific Handlers
  # ─────────────────────────────────────────────────────────────────

  defp map_resource_error(resource) do
    resource_name = build_resource_type_name(resource)
    "#{resource_name}ValidationErrors"
  end

  defp map_struct_error(constraints) do
    instance_of = Keyword.get(constraints, :instance_of)

    cond do
      # instance_of pointing to embedded resource
      instance_of && is_embedded_resource?(instance_of) ->
        map_resource_error(instance_of)

      # instance_of pointing to module with typescript_type_name
      instance_of && is_custom_type?(instance_of) ->
        "#{instance_of.typescript_type_name()}ValidationErrors"

      # Has fields constraint - inline object type
      Keyword.has_key?(constraints, :fields) ->
        map_typed_container_error(constraints)

      # Fallback
      true ->
        "Record<string, any>"
    end
  end

  defp map_typed_container_error(constraints) do
    fields = Keyword.get(constraints, :fields, [])

    if fields == [] do
      "Record<string, any>"
    else
      field_defs =
        Enum.map_join(fields, "; ", fn {field_name, field_config} ->
          field_type = Keyword.get(field_config, :type)
          field_constraints = Keyword.get(field_config, :constraints, [])
          formatted_name = format_output_field(field_name)
          error_type = map_error_type(field_type, field_constraints)

          "#{formatted_name}?: #{error_type}"
        end)

      "{ #{field_defs} }"
    end
  end

  @doc """
  Generates validation error type for an RPC action.
  """
  def generate_validation_error_type(resource, action, rpc_action_name) do
    resource_lookup = AshTypescript.resource_lookup()

    generate_validation_error_type(resource, action, rpc_action_name, resource_lookup)
  end

  @doc """
  Generates validation error type for an RPC action with pre-computed resource_lookup.
  """
  def generate_validation_error_type(resource, action, rpc_action_name, resource_lookup) do
    if ActionIntrospection.action_input_type(resource, action) != :none do
      error_type_name = "#{snake_to_pascal_case(rpc_action_name)}ValidationErrors"
      error_field_defs = generate_rpc_action_error_fields(resource, action, resource_lookup)

      field_lines =
        Enum.map(error_field_defs, fn {name, type} ->
          "  #{name}?: #{type};"
        end)

      """
      export type #{error_type_name} = {
      #{Enum.join(field_lines, "\n")}
      };
      """
    else
      ""
    end
  end

  @doc """
  Generates validation error schemas for embedded resources.
  """
  def generate_validation_error_schemas_for_embedded_resources(embedded_resources) do
    resource_lookup = AshTypescript.resource_lookup()

    generate_validation_error_schemas_for_embedded_resources(embedded_resources, resource_lookup)
  end

  @doc """
  Generates validation error schemas for embedded resources with pre-computed resource_lookup.
  """
  def generate_validation_error_schemas_for_embedded_resources(
        embedded_resources,
        resource_lookup
      ) do
    if embedded_resources != [] do
      schemas =
        embedded_resources
        |> Enum.map_join("\n\n", &generate_input_validation_errors_schema(&1, resource_lookup))

      """
      // ============================
      // Validation Error Schemas for Embedded Resources
      // ============================

      #{schemas}
      """
    else
      ""
    end
  end

  @doc """
  Generates validation error schemas for types with field constraints.

  Accepts either:
  - A list of type info maps (new format): `%{instance_of:, constraints:, field_name_mappings:}`
  - A list of modules (legacy format): for backward compatibility

  Returns TypeScript validation error schema definitions.
  """
  def generate_validation_error_schemas_for_typed_structs(type_infos) when is_list(type_infos) do
    if type_infos != [] do
      schemas =
        type_infos
        |> Enum.map_join("\n\n", fn
          %{instance_of: instance_of, constraints: constraints, field_name_mappings: mappings} ->
            generate_validation_error_schema_for_field_type(instance_of, constraints, mappings)

          module when is_atom(module) ->
            constraints =
              if Ash.Type.NewType.new_type?(module) do
                Ash.Type.NewType.constraints(module, [])
              else
                []
              end

            field_name_mappings =
              if function_exported?(module, :typescript_field_names, 0) do
                module.typescript_field_names()
              else
                nil
              end

            generate_validation_error_schema_for_field_type(
              module,
              constraints,
              field_name_mappings
            )
        end)

      """
      // ============================
      // Validation Error Schemas for Field-Constrained Types
      // ============================

      #{schemas}
      """
    else
      ""
    end
  end

  @doc """
  Generates explicit validation error types for input schemas.
  """
  def generate_input_validation_errors_schema(resource) do
    resource_lookup = AshTypescript.resource_lookup()

    generate_input_validation_errors_schema(resource, resource_lookup)
  end

  @doc """
  Generates explicit validation error types for input schemas with pre-computed resource_lookup.
  """
  def generate_input_validation_errors_schema(resource, resource_lookup) do
    resource_name = build_resource_type_name(resource)

    api_resource = AshApiSpec.get_resource!(resource_lookup, resource)

    error_fields =
      api_resource
      |> AshApiSpec.Resource.fields_by_kind(:attribute)
      |> Enum.map_join("\n", fn attr ->
        formatted_name =
          AshTypescript.FieldFormatter.format_field_for_client(
            attr.name,
            resource,
            AshTypescript.Rpc.output_field_formatter()
          )

        error_type = get_ts_error_type(attr)

        "  #{formatted_name}?: #{error_type};"
      end)

    """
    export type #{resource_name}ValidationErrors = {
    #{error_fields}
    };
    """
  end

  # ─────────────────────────────────────────────────────────────────
  # Public API
  # ─────────────────────────────────────────────────────────────────

  @doc """
  Maps Ash types to their corresponding validation error types.
  Backward compatible wrapper around map_error_type/2.
  """
  # Handle AshApiSpec structs — pass spec type directly
  def get_ts_error_type(%{type: %AshApiSpec.Type{} = spec_type}) do
    map_error_type(spec_type, [])
  end

  def get_ts_error_type(%{type: type, constraints: constraints}) do
    map_error_type(type, constraints || [])
  end

  def get_ts_error_type(%{type: type}) do
    map_error_type(type, [])
  end

  @doc """
  Builds a union error type from a list of union type definitions.
  Creates an object with optional error fields for each union variant.

  Example:
  Input union: { text: TextInput } | { note: string }
  Error type: { text?: TextValidationErrors; note?: string[]; }
  """
  def build_union_error_type(union_types) do
    if Enum.empty?(union_types) do
      "Record<string, any>"
    else
      member_fields =
        union_types
        |> Enum.map_join("; ", fn {type_name, type_config} ->
          formatted_name =
            AshTypescript.FieldFormatter.format_field_name(
              type_name,
              AshTypescript.Rpc.output_field_formatter()
            )

          member_type = Keyword.get(type_config, :type)
          member_constraints = Keyword.get(type_config, :constraints, [])
          member_error_type = map_error_type(member_type, member_constraints)

          "#{formatted_name}?: #{member_error_type}"
        end)

      "{ #{member_fields} }"
    end
  end

  defp generate_rpc_action_error_fields(resource, action, resource_lookup) do
    cond do
      action.type in [:read, :action] ->
        arguments = filter_public_arguments(action.arguments)

        if arguments != [] do
          Enum.map(arguments, fn arg ->
            formatted_arg_name = format_argument_name_for_client(resource, action.name, arg.name)
            error_type = get_ts_error_type(arg)
            {formatted_arg_name, error_type}
          end)
        end

      action.type in [:create, :update, :destroy] ->
        arguments = filter_public_arguments(action.arguments)

        if action.accept != [] || arguments != [] do
          accept_field_defs =
            Enum.map(action.accept, fn field_name ->
              attr = AshApiSpec.get_field(resource_lookup, resource, field_name)

              formatted_field_name =
                AshTypescript.FieldFormatter.format_field_for_client(
                  field_name,
                  resource,
                  AshTypescript.Rpc.output_field_formatter()
                )

              error_type = get_ts_error_type(attr)
              {formatted_field_name, error_type}
            end)

          argument_field_defs =
            Enum.map(arguments, fn arg ->
              formatted_arg_name =
                format_argument_name_for_client(resource, action.name, arg.name)

              error_type = get_ts_error_type(arg)
              {formatted_arg_name, error_type}
            end)

          accept_field_defs ++ argument_field_defs
        else
          []
        end
    end
  end

  # Helper to format argument name for client output
  # If mapped, use the string directly; otherwise apply formatter
  defp format_argument_name_for_client(resource, action_name, arg_name) do
    mapped = AshTypescript.Resource.Info.get_mapped_argument_name(resource, action_name, arg_name)

    cond do
      is_binary(mapped) ->
        mapped

      mapped == arg_name ->
        AshTypescript.FieldFormatter.format_field_name(
          arg_name,
          AshTypescript.Rpc.output_field_formatter()
        )

      true ->
        AshTypescript.FieldFormatter.format_field_name(
          mapped,
          AshTypescript.Rpc.output_field_formatter()
        )
    end
  end

  defp generate_validation_error_schema_for_field_type(
         instance_of_module,
         constraints,
         field_name_mappings
       ) do
    resource_name = build_resource_type_name(instance_of_module)

    fields = Keyword.get(constraints, :fields, [])

    error_fields =
      fields
      |> Enum.map_join("\n", fn {field_name, field_config} ->
        # Apply field name mapping if defined
        mapped_name =
          if field_name_mappings && Keyword.has_key?(field_name_mappings, field_name) do
            Keyword.get(field_name_mappings, field_name)
          else
            field_name
          end

        formatted_name =
          AshTypescript.FieldFormatter.format_field_name(
            mapped_name,
            AshTypescript.Rpc.output_field_formatter()
          )

        field_type = Keyword.get(field_config, :type)
        field_constraints = Keyword.get(field_config, :constraints, [])
        error_type = get_ts_error_type(%{type: field_type, constraints: field_constraints})
        "  #{formatted_name}?: #{error_type};"
      end)

    """
    export type #{resource_name}ValidationErrors = {
    #{error_fields}
    };
    """
  end

  defp is_custom_type?(type) when is_atom(type) and not is_nil(type) do
    Code.ensure_loaded?(type) and
      function_exported?(type, :typescript_type_name, 0) and
      Spark.implements_behaviour?(type, Ash.Type)
  end

  defp is_custom_type?(_), do: false

  defp is_embedded_resource?(module) when is_atom(module) and not is_nil(module) do
    Code.ensure_loaded?(module) == true and
      Ash.Resource.Info.resource?(module) and
      Ash.Resource.Info.embedded?(module)
  end

  defp is_embedded_resource?(_), do: false
end
