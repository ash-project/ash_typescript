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

  alias Ash.Info.Manifest
  alias AshRpc.RequestedFieldsProcessor
  alias AshTypescript.Codegen.ClientNames
  alias AshTypescript.Rpc.Codegen.FunctionGenerators.JsdocGenerator

  @doc """
  Generates the typed queries section for TypeScript output.

  Returns an empty string if no typed queries are defined.
  """
  def generate_typed_queries_section(
        [],
        _rpc_resources_and_actions,
        _all_resources
      ),
      do: ""

  def generate_typed_queries_section(
        typed_queries,
        rpc_resources_and_actions,
        all_resources
      ) do
    queries_by_resource =
      Enum.group_by(typed_queries, fn {resource, _action, _query} -> resource end)

    sections =
      queries_by_resource
      |> Enum.sort_by(fn {resource, _queries} -> inspect(resource) end)
      |> Enum.map(fn {resource, queries} ->
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

    runtime = AshRpc.Runtime.from_manifest(AshTypescript.manifest())

    atomized_fields =
      RequestedFieldsProcessor.atomize_requested_fields(typed_query.fields, resource, runtime)

    case RequestedFieldsProcessor.process(runtime, resource, action.name, atomized_fields) do
      {:ok, {_select, _load, _template}} ->
        # The type and the const are the same selection, named with the decorated client names
        selection = format_typed_query_fields(atomized_fields, resource)

        # Type names are always PascalCase in TypeScript
        type_name =
          typed_query.ts_result_type_name ||
            "#{snake_to_pascal_case(typed_query.name)}Result"

        # Const names use the configured field formatter
        const_name =
          typed_query.ts_fields_const_name || format_output_field(typed_query.name)

        is_array = action.type == :read && !action.get?

        result_type =
          if is_array do
            "Array<InferResult<#{resource_name}ResourceSchema, #{selection}>>"
          else
            "InferResult<#{resource_name}ResourceSchema, #{selection}>"
          end

        fields_type = find_matching_rpc_fields_type(resource, action, rpc_resources_and_actions)
        jsdoc = JsdocGenerator.generate_typed_query_jsdoc(typed_query, resource)

        """
        #{jsdoc}
        export type #{type_name} = #{result_type};

        #{jsdoc}
        export const #{const_name} = #{selection}#{satisfies_clause(fields_type)};
        """

      {:error, error} ->
        raise "Error processing typed query #{typed_query.name}: #{inspect(error)}"
    end
  end

  defp satisfies_clause(nil), do: ""
  defp satisfies_clause(fields_type), do: " satisfies #{fields_type}"

  defp find_matching_rpc_fields_type(resource, action, rpc_resources_and_actions) do
    matches =
      rpc_resources_and_actions
      |> Enum.filter(fn {rpc_resource, rpc_action, _rpc_action_config} ->
        rpc_resource == resource && rpc_action.name == action.name
      end)
      |> Enum.sort_by(fn {_resource, _action, rpc_action_config} ->
        is_get =
          Map.get(rpc_action_config, :get?, false) or
            (Map.get(rpc_action_config, :get_by) || []) != []

        # Prefer non-get actions (list-style) for typed queries, then sort alphabetically
        {is_get, to_string(rpc_action_config.name)}
      end)

    case List.first(matches) do
      {_resource, _action, rpc_action_config} ->
        rpc_action_name = to_string(rpc_action_config.name)
        "#{snake_to_pascal_case(rpc_action_name)}Fields"

      nil ->
        nil
    end
  end

  # Field items are named against a context: `{:resource, %Resource{}}`,
  # `{:type, %Type{}}` (typed container) or `{:union, %Type{}}`. Nested selections
  # descend into the field's own resource or type, so each level is named with
  # its own decorated client names, as the runtime resolves them.
  defp format_typed_query_fields(fields, resource) do
    "[" <> format_fields_array(fields, resource_context(resource)) <> "]"
  end

  defp format_fields_array(fields, ctx) do
    Enum.map_join(fields, ", ", &format_field_item(&1, ctx))
  end

  defp format_field_item(field, ctx) when is_atom(field) do
    ~s["#{name(ctx, field)}"]
  end

  defp format_field_item({field, nested_fields}, ctx)
       when is_atom(field) and is_list(nested_fields) do
    "{ #{name(ctx, field)}: [#{format_fields_array(nested_fields, descend(ctx, field))}] }"
  end

  defp format_field_item({field, {args, nested_fields}}, ctx)
       when is_atom(field) and is_map(args) and is_list(nested_fields) do
    calculation_selection(ctx, field, format_args_map(args, ctx, field), nested_fields)
  end

  defp format_field_item({field, nested_fields}, ctx)
       when is_atom(field) and is_map(nested_fields) do
    case nested_fields do
      %{args: args, fields: fields} ->
        calculation_selection(ctx, field, format_args_map(args, ctx, field), fields)

      _ ->
        inspect(nested_fields)
    end
  end

  defp format_field_item(%{} = field_map, ctx) do
    formatted_pairs =
      field_map
      |> Enum.sort_by(fn {k, _v} -> to_string(k) end)
      |> Enum.map_join(", ", fn
        {k, %{args: args, fields: fields}} when is_map(args) and is_list(fields) ->
          "#{name(ctx, k)}: { #{formatted_args_field()}: #{format_args_map(args, ctx, k, false)}, " <>
            "#{formatted_fields_field()}: [#{format_fields_array(fields, descend(ctx, k))}] }"

        {k, v} ->
          "#{name(ctx, k)}: #{format_field_item(v, descend(ctx, k))}"
      end)

    "{ #{formatted_pairs} }"
  end

  defp format_field_item(list, ctx) when is_list(list) do
    "[#{format_fields_array(list, ctx)}]"
  end

  defp format_field_item(field, _ctx), do: inspect(field)

  defp calculation_selection(ctx, field, args_json, nested_fields) do
    "{ #{name(ctx, field)}: { #{formatted_args_field()}: #{args_json}, " <>
      "#{formatted_fields_field()}: [#{format_fields_array(nested_fields, descend(ctx, field))}] } }"
  end

  # Calculation arguments as an object literal; `quote_keys?` selects JSON-style
  # quoted keys over the bare keys of the `%{args:, fields:}` form.
  defp format_args_map(args, ctx, calc, quote_keys? \\ true)

  defp format_args_map(args, {:resource, resource}, calc, quote_keys?) do
    formatted_args =
      args
      |> Enum.sort_by(fn {k, _v} -> to_string(k) end)
      |> Enum.map_join(", ", fn {k, v} ->
        key = ClientNames.calculation_argument(resource, calc, k)
        key = if quote_keys?, do: ~s["#{key}"], else: key
        "#{key}: #{Jason.encode!(v)}"
      end)

    "{ #{formatted_args} }"
  end

  defp name({:resource, resource}, field), do: ClientNames.resource_field(resource, field)
  defp name({:type, type}, field), do: ClientNames.type_field(type, field)
  defp name({:union, type}, member), do: ClientNames.union_member(type, member)

  defp descend({:resource, resource} = ctx, field) do
    case Manifest.Resource.get_relationship(resource, field) do
      %Manifest.Relationship{destination: destination} ->
        resource_context(destination)

      nil ->
        case Manifest.Resource.get_field(resource, field) do
          %Manifest.Field{type: type} -> context_for(type)
          nil -> raise ArgumentError, "no field #{inspect(field)} on #{describe(ctx)}"
        end
    end
  end

  defp descend({:type, type} = ctx, field) do
    case Manifest.Type.find_field_type(type, field) do
      %Manifest.Type{} = field_type -> context_for(field_type)
      nil -> raise ArgumentError, "no field #{inspect(field)} on #{describe(ctx)}"
    end
  end

  defp descend({:union, type} = ctx, member) do
    case Manifest.Type.find_member(type, member) do
      %{type: %Manifest.Type{} = member_type} -> context_for(member_type)
      nil -> raise ArgumentError, "no member #{inspect(member)} on #{describe(ctx)}"
    end
  end

  defp context_for(%Manifest.Type{} = type) do
    case ClientNames.resolve_type!(type) do
      %Manifest.Type{kind: :array, item_type: %Manifest.Type{} = item} ->
        context_for(item)

      %Manifest.Type{kind: kind} = t when kind in [:resource, :embedded_resource] ->
        resource_context(Manifest.Type.effective_resource(t))

      %Manifest.Type{kind: :union} = t ->
        {:union, t}

      t ->
        {:type, t}
    end
  end

  defp resource_context(module) do
    case Map.fetch(AshTypescript.resource_lookup(), module) do
      {:ok, resource} -> {:resource, resource}
      :error -> raise ArgumentError, "resource #{inspect(module)} is not in the manifest"
    end
  end

  defp describe({:resource, resource}), do: "resource #{inspect(resource.module)}"
  defp describe({_kind, type}), do: "type #{inspect(Manifest.Type.effective_module(type))}"
end
