defmodule AshTypescript.Rpc.ValidationErrorSchemas do
  @moduledoc """
  Generates validation error schemas for TypeScript RPC clients.

  This module handles the generation of TypeScript validation error types
  for RPC actions, embedded resources, and typed structs.
  """

  import AshTypescript.Helpers
  import AshTypescript.Codegen, only: [build_resource_type_name: 1]

  @doc """
  Generates validation error type for an RPC action.
  """
  def generate_validation_error_type(resource, action, rpc_action_name) do
    if action_has_input?(resource, action) do
      error_type_name = "#{snake_to_pascal_case(rpc_action_name)}ValidationErrors"
      error_field_defs = generate_rpc_action_error_fields(resource, action)

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
    if embedded_resources != [] do
      schemas =
        embedded_resources
        |> Enum.map_join("\n\n", &generate_input_validation_errors_schema/1)

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
  Generates validation error schemas for typed struct modules.
  """
  def generate_validation_error_schemas_for_typed_structs(typed_struct_modules) do
    if typed_struct_modules != [] do
      schemas =
        typed_struct_modules
        |> Enum.map_join("\n\n", &generate_validation_error_schema_for_typed_struct/1)

      """
      // ============================
      // Validation Error Schemas for TypedStruct Modules
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
    resource_name = build_resource_type_name(resource)

    error_fields =
      resource
      |> Ash.Resource.Info.public_attributes()
      |> Enum.map_join("\n", fn attr ->
        mapped_name = AshTypescript.Resource.Info.get_mapped_field_name(resource, attr.name)

        formatted_name =
          AshTypescript.FieldFormatter.format_field(
            mapped_name,
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

  @doc """
  Maps Ash types to their corresponding validation error types.
  """
  def get_ts_error_type(%{type: type, constraints: constraints}) do
    case type do
      {:array, inner_type} ->
        constraints = Keyword.get(constraints, :items, [])
        error_type = get_ts_error_type(%{type: inner_type, constraints: constraints})
        "#{error_type}[]"

      Ash.Type.Union ->
        union_types = Keyword.get(constraints, :types, [])
        build_union_error_type(union_types)

      map_like when map_like in [Ash.Type.Map, Ash.Type.Keyword, Ash.Type.Tuple] ->
        fields = Keyword.get(constraints, :fields, [])

        field_defs =
          Enum.map_join(fields, "; ", fn {key, type_config} ->
            type = Keyword.get(type_config, :type)
            constraints = Keyword.get(type_config, :constraints, [])

            "#{AshTypescript.Helpers.format_output_field(key)}?: #{get_ts_error_type(%{type: type, constraints: constraints})}"
          end)

        "{ #{field_defs} }"

      Ash.Type.Struct ->
        instance_of = Keyword.get(constraints, :instance_of)

        if instance_of && AshTypescript.Codegen.is_embedded_resource?(instance_of) do
          resource_name = build_resource_type_name(instance_of)
          "#{resource_name}ValidationErrors"
        else
          "Record<string, any>"
        end

      custom_type ->
        cond do
          is_custom_type?(custom_type) ->
            "#{custom_type.typescript_type_name()}ValidationErrors"

          AshTypescript.Codegen.is_embedded_resource?(custom_type) ->
            resource_name = build_resource_type_name(custom_type)
            "#{resource_name}ValidationErrors"

          AshTypescript.Codegen.is_typed_struct?(custom_type) ->
            resource_name = build_resource_type_name(custom_type)
            "#{resource_name}ValidationErrors"

          Ash.Type.NewType.new_type?(custom_type) ->
            subtype = Ash.Type.NewType.subtype_of(custom_type)
            sub_constraints = Ash.Type.NewType.constraints(custom_type, constraints)
            get_ts_error_type(%{type: subtype, constraints: sub_constraints})

          Spark.implements_behaviour?(custom_type, Ash.Type.Enum) ->
            "string[]"

          true ->
            "string[]"
        end
    end
  end

  def get_ts_error_type(%{type: type}) do
    get_ts_error_type(%{type: type, constraints: []})
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
            AshTypescript.FieldFormatter.format_field(
              type_name,
              AshTypescript.Rpc.output_field_formatter()
            )

          type = Keyword.get(type_config, :type)
          constraints = Keyword.get(type_config, :constraints, [])
          member_error_type = get_ts_error_type(%{type: type, constraints: constraints})

          "#{formatted_name}?: #{member_error_type}"
        end)

      "{ #{member_fields} }"
    end
  end

  defp generate_rpc_action_error_fields(resource, action) do
    cond do
      action.type in [:read, :action] ->
        arguments = action.arguments

        if arguments != [] do
          Enum.map(arguments, fn arg ->
            mapped_name =
              AshTypescript.Resource.Info.get_mapped_argument_name(
                resource,
                action.name,
                arg.name
              )

            formatted_arg_name =
              AshTypescript.FieldFormatter.format_field(
                mapped_name,
                AshTypescript.Rpc.output_field_formatter()
              )

            error_type = get_ts_error_type(arg)
            {formatted_arg_name, error_type}
          end)
        end

      action.type in [:create, :update, :destroy] ->
        if action.accept != [] || action.arguments != [] do
          accept_field_defs =
            Enum.map(action.accept, fn field_name ->
              attr = Ash.Resource.Info.attribute(resource, field_name)

              mapped_name =
                AshTypescript.Resource.Info.get_mapped_field_name(resource, field_name)

              formatted_field_name =
                AshTypescript.FieldFormatter.format_field(
                  mapped_name,
                  AshTypescript.Rpc.output_field_formatter()
                )

              error_type = get_ts_error_type(attr)
              {formatted_field_name, error_type}
            end)

          argument_field_defs =
            Enum.map(action.arguments, fn arg ->
              mapped_name =
                AshTypescript.Resource.Info.get_mapped_argument_name(
                  resource,
                  action.name,
                  arg.name
                )

              formatted_arg_name =
                AshTypescript.FieldFormatter.format_field(
                  mapped_name,
                  AshTypescript.Rpc.output_field_formatter()
                )

              error_type = get_ts_error_type(arg)
              {formatted_arg_name, error_type}
            end)

          accept_field_defs ++ argument_field_defs
        else
          []
        end
    end
  end

  defp generate_validation_error_schema_for_typed_struct(typed_struct_module) do
    resource_name = build_resource_type_name(typed_struct_module)

    fields = AshTypescript.Codegen.get_typed_struct_fields(typed_struct_module)

    # Get field name mappings if defined
    field_name_mappings =
      if function_exported?(typed_struct_module, :typescript_field_names, 0) do
        typed_struct_module.typescript_field_names()
      else
        []
      end

    error_fields =
      fields
      |> Enum.map_join("\n", fn field ->
        # Apply field name mapping if defined
        mapped_name =
          if Keyword.has_key?(field_name_mappings, field.name) do
            Keyword.get(field_name_mappings, field.name)
          else
            field.name
          end

        formatted_name =
          AshTypescript.FieldFormatter.format_field(
            mapped_name,
            AshTypescript.Rpc.output_field_formatter()
          )

        error_type = get_ts_error_type(%{type: field.type, constraints: field.constraints || []})
        "  #{formatted_name}?: #{error_type};"
      end)

    """
    export type #{resource_name}ValidationErrors = {
    #{error_fields}
    };
    """
  end

  defp is_custom_type?(type) do
    is_atom(type) and
      Code.ensure_loaded?(type) and
      function_exported?(type, :typescript_type_name, 0) and
      Spark.implements_behaviour?(type, Ash.Type)
  end

  defp action_has_input?(resource, action) do
    case action.type do
      :read ->
        action.arguments != []

      :create ->
        accepts = Ash.Resource.Info.action(resource, action.name).accept || []
        accepts != [] || action.arguments != []

      action_type when action_type in [:update, :destroy] ->
        action.accept != [] || action.arguments != []

      :action ->
        action.arguments != []
    end
  end
end
