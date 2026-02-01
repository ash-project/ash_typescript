# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Codegen.FunctionGenerators.TypedQueries do
  @moduledoc """
  Generates TypeScript typed query types and field constants.

  Typed queries provide compile-time type safety for server-side rendered data
  and allow the same field selections to be used for client-side refetching.
  """

  import AshTypescript.Codegen
  import AshTypescript.Helpers

  alias AshTypescript.Rpc.RequestedFieldsProcessor

  @doc """
  Generates the typed queries section for TypeScript output.

  Returns an empty string if no typed queries are defined.
  """
  def generate_typed_queries_section([], _rpc_resources_and_actions, _all_resources), do: ""

  def generate_typed_queries_section(typed_queries, rpc_resources_and_actions, all_resources) do
    queries_by_resource =
      Enum.group_by(typed_queries, fn {resource, _action, _query} -> resource end)

    sections =
      Enum.map(queries_by_resource, fn {resource, queries} ->
        resource_name = build_resource_type_name(resource)

        query_types_and_consts =
          Enum.map(queries, fn {resource, action, typed_query} ->
            generate_typed_query_type_and_const(
              resource,
              action,
              typed_query,
              rpc_resources_and_actions,
              all_resources
            )
          end)

        """
        // #{resource_name} Typed Queries
        #{Enum.join(query_types_and_consts, "\n\n")}
        """
      end)

    """
    // ============================
    // Typed Queries
    // ============================
    // Use these types and field constants for server-side rendering and data fetching.
    // The field constants can be used with the corresponding RPC actions for client-side refetching.

    #{Enum.join(sections, "\n\n")}
    """
  end

  @doc """
  Generates a single typed query type and const declaration.
  """
  def generate_typed_query_type_and_const(
        resource,
        action,
        typed_query,
        rpc_resources_and_actions,
        _all_resources
      ) do
    resource_name = build_resource_type_name(resource)

    atomized_fields =
      RequestedFieldsProcessor.atomize_requested_fields(typed_query.fields, resource)

    case RequestedFieldsProcessor.process(resource, action.name, atomized_fields) do
      {:ok, {_select, _load, _template}} ->
        # Both type and const need to use mapped field names since UserResourceSchema has mapped names
        type_fields = format_typed_query_fields_type_for_typescript(atomized_fields, resource)

        type_name = typed_query.ts_result_type_name
        const_name = typed_query.ts_fields_const_name

        is_array = action.type == :read && !action.get?

        result_type =
          if is_array do
            "Array<InferResult<#{resource_name}ResourceSchema, #{type_fields}>>"
          else
            "InferResult<#{resource_name}ResourceSchema, #{type_fields}>"
          end

        const_fields = format_typed_query_fields_const_for_typescript(atomized_fields, resource)

        fields_type = find_matching_rpc_fields_type(resource, action, rpc_resources_and_actions)

        # Use `satisfies` to preserve literal types while ensuring type compatibility
        const_declaration =
          if fields_type do
            "export const #{const_name} = #{const_fields} satisfies #{fields_type};"
          else
            "export const #{const_name} = #{const_fields};"
          end

        """
        // Type for #{typed_query.name}
        export type #{type_name} = #{result_type};

        // Field selection for #{typed_query.name} - use with RPC actions for refetching
        #{const_declaration}
        """

      {:error, error} ->
        raise "Error processing typed query #{typed_query.name}: #{inspect(error)}"
    end
  end

  defp find_matching_rpc_fields_type(resource, action, rpc_resources_and_actions) do
    matching_rpc =
      Enum.find(rpc_resources_and_actions, fn {rpc_resource, rpc_action, _rpc_action_config} ->
        rpc_resource == resource && rpc_action.name == action.name
      end)

    case matching_rpc do
      {_resource, _action, rpc_action_config} ->
        rpc_action_name = to_string(rpc_action_config.name)
        "#{snake_to_pascal_case(rpc_action_name)}Fields"

      nil ->
        nil
    end
  end

  defp format_typed_query_fields_const_for_typescript(fields, resource) do
    "[" <> format_fields_const_array(fields, resource) <> "]"
  end

  defp format_typed_query_fields_type_for_typescript(fields, resource) do
    "[" <> format_fields_type_array(fields, resource) <> "]"
  end

  defp format_fields_const_array(fields, resource) do
    fields
    |> Enum.map_join(", ", &format_field_item(&1, resource))
  end

  defp format_fields_type_array(fields, resource) do
    fields
    |> Enum.map_join(", ", &format_field_item(&1, resource))
  end

  # format_field_item/2 - with resource context for field name mapping
  defp format_field_item(field, resource) when is_atom(field) do
    ~s["#{format_field_name(field, resource)}"]
  end

  defp format_field_item({field, nested_fields}, resource)
       when is_atom(field) and is_list(nested_fields) do
    "{ #{format_field_name(field, resource)}: [#{format_fields_type_array(nested_fields, resource)}] }"
  end

  defp format_field_item({field, {args, nested_fields}}, resource)
       when is_atom(field) and is_map(args) and is_list(nested_fields) do
    args_json = format_args_map(args, resource)

    "{ #{format_field_name(field, resource)}: { #{formatted_args_field()}: #{args_json}, #{formatted_fields_field()}: [#{format_fields_type_array(nested_fields, resource)}] } }"
  end

  defp format_field_item({field, nested_fields}, resource)
       when is_atom(field) and is_map(nested_fields) do
    case nested_fields do
      %{args: args, fields: fields} ->
        args_json = format_args_map(args, resource)

        "{ #{format_field_name(field, resource)}: { #{formatted_args_field()}: #{args_json}, #{formatted_fields_field()}: [#{format_fields_type_array(fields, resource)}] } }"

      _ ->
        inspect(nested_fields)
    end
  end

  defp format_field_item(%{} = field_map, resource) do
    formatted_pairs =
      field_map
      |> Enum.map_join(", ", fn {k, v} ->
        key = format_field_name(k, resource)
        value = format_field_item(v, resource)
        "#{key}: #{value}"
      end)

    "{ #{formatted_pairs} }"
  end

  defp format_field_item(list, resource) when is_list(list) do
    formatted_items =
      list
      |> Enum.map_join(", ", &format_field_item(&1, resource))

    "[#{formatted_items}]"
  end

  defp format_field_item(field, _resource), do: inspect(field)

  defp format_field_name(atom, resource) do
    formatter = AshTypescript.Rpc.output_field_formatter()
    AshTypescript.FieldFormatter.format_field_for_client(atom, resource, formatter)
  end

  defp format_args_map(args, resource) do
    formatted_args =
      args
      |> Enum.map_join(", ", fn {k, v} ->
        "\"#{format_field_name(k, resource)}\": #{Jason.encode!(v)}"
      end)

    "{ #{formatted_args} }"
  end
end
