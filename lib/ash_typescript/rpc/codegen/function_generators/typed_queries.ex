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
  alias AshTypescript.Manifest.Custom
  alias AshTypescript.Rpc.Codegen.FunctionGenerators.JsdocGenerator
  alias AshTypescript.Rpc.Codegen.FunctionNames
  alias AshTypescript.Rpc.Codegen.Helpers.EntrypointOptions

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

    manifest = AshTypescript.manifest()
    runtime = AshRpc.Runtime.from_manifest(manifest)

    case RequestedFieldsProcessor.process(runtime, resource, action.name, typed_query.fields) do
      {:ok, {_select, _load, _template}} ->
        # The type and the const are the same selection, named with the decorated client names
        selection = format_typed_query_fields(typed_query.fields, resource, runtime)

        type_name = FunctionNames.typed_query_result_type(typed_query)
        const_name = FunctionNames.typed_query_const(typed_query)

        entrypoint = Custom.typed_query_entrypoint(manifest, typed_query.name)
        is_array = action.type == :read and not EntrypointOptions.get?(entrypoint, action)

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
        is_get = EntrypointOptions.get?(EntrypointOptions.entrypoint!(rpc_action_config), action)

        # Prefer non-get actions (list-style) for typed queries, then sort alphabetically
        {is_get, to_string(rpc_action_config.name)}
      end)

    case List.first(matches) do
      {_resource, _action, rpc_action_config} ->
        FunctionNames.fields_type(rpc_action_config.name)

      nil ->
        nil
    end
  end

  # Field items are named against a context: `{:resource, %Resource{}}`,
  # `{:type, %Type{}}` (typed container) or `{:union, %Type{}}`. Nested selections
  # descend into the field's own resource or type, so each level is named with
  # its own decorated client names, as the runtime resolves them. The selection
  # may name fields by internal atoms or by client strings, at any level, and a
  # relationship's envelope keys (`fields`, `filter`, `page`, …) by either: string
  # names resolve through `AshRpc.ClientNames`, as the runtime's field selector
  # resolves them, so both forms render the same TypeScript.
  defp format_typed_query_fields(fields, resource, rt) do
    "[" <> format_fields_array(fields, resource_context(resource), rt) <> "]"
  end

  defp format_fields_array(fields, ctx, rt) when is_list(fields) do
    Enum.map_join(fields, ", ", &format_field_item(&1, ctx, rt))
  end

  defp format_fields_array(fields, _ctx, _rt), do: unrenderable!(fields)

  defp format_field_item(field, ctx, rt) when is_atom(field) or is_binary(field) do
    ~s["#{name(ctx, internal(ctx, field, rt))}"]
  end

  # Keyword form: one field per entry; calculation arguments keep JSON-style
  # quoted keys
  defp format_field_item({field, nested}, ctx, rt) when is_atom(field) or is_binary(field) do
    "{ #{format_pair(ctx, field, nested, rt, true)} }"
  end

  defp format_field_item(%{} = field_map, ctx, rt) when not is_struct(field_map) do
    formatted_pairs =
      field_map
      |> Enum.sort_by(fn {k, _v} -> to_string(k) end)
      |> Enum.map_join(", ", fn {k, v} -> format_pair(ctx, k, v, rt, false) end)

    "{ #{formatted_pairs} }"
  end

  defp format_field_item(field, _ctx, _rt), do: unrenderable!(field)

  defp format_pair(ctx, field, nested, rt, quote_keys?) do
    field = internal(ctx, field, rt)

    value =
      case envelope(ctx, nested, rt) do
        {:ok, opts} -> format_envelope(ctx, field, opts, rt, quote_keys?)
        :error when is_list(nested) -> "[#{format_fields_array(nested, descend(ctx, field), rt)}]"
        :error when is_map(nested) -> format_field_item(nested, descend(ctx, field), rt)
        :error -> unrenderable!(nested)
      end

    "#{name(ctx, field)}: #{value}"
  end

  @envelope_keys [:args, :filter, :sort, :page, :limit, :offset, :fields]

  # A map holding any envelope key (resolved through the `:query_opts`
  # vocabulary, as the runtime does) is a calculation's or relationship's
  # envelope. Keys that aren't envelope options are left out: the runtime
  # rejects them on a relationship and ignores them on a calculation.
  defp envelope({:resource, _}, %{} = nested, rt) when not is_struct(nested) do
    opts =
      Enum.reduce(nested, %{}, fn {key, value}, acc ->
        case AshRpc.ClientNames.vocabulary(rt, :query_opts, key) do
          {:ok, opt} when opt in @envelope_keys -> Map.put(acc, opt, value)
          _ -> acc
        end
      end)

    if opts == %{}, do: :error, else: {:ok, opts}
  end

  defp envelope(_ctx, _nested, _rt), do: :error

  # Options in a fixed order, the nested fields last.
  defp format_envelope({:resource, resource} = ctx, field, opts, rt, quote_keys?) do
    destination = descend(ctx, field)

    entries =
      for key <- @envelope_keys, not is_nil(opts[key]) do
        "#{formatted_query_opt_field(key)}: " <>
          format_envelope_value(key, opts[key], resource, field, destination, rt, quote_keys?)
      end

    "{ #{Enum.join(entries, ", ")} }"
  end

  defp format_envelope_value(:args, args, resource, calc, _dest, rt, quote_keys?),
    do: format_args_map(args, resource, calc, rt, quote_keys?)

  defp format_envelope_value(:fields, fields, _resource, _field, dest, rt, _quote_keys?),
    do: "[#{format_fields_array(fields, dest, rt)}]"

  defp format_envelope_value(:filter, filter, _resource, _field, {:resource, dest}, rt, _),
    do: format_filter(filter, dest, rt)

  defp format_envelope_value(:sort, sort, _resource, _field, {:resource, dest}, rt, _),
    do: format_sort(sort, dest, rt)

  defp format_envelope_value(:page, %{} = page, _resource, _field, _dest, rt, _) do
    entries =
      page
      |> Enum.map(fn {key, value} -> {vocabulary_name!(rt, :page, key), value} end)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map_join(", ", fn {key, value} ->
        "#{ClientNames.vocabulary!(:page, key)}: #{json_value!(value)}"
      end)

    "{ #{entries} }"
  end

  defp format_envelope_value(key, value, _resource, _field, _dest, _rt, _)
       when key in [:limit, :offset] and is_integer(value),
       do: Integer.to_string(value)

  defp format_envelope_value(_key, value, _resource, _field, _dest, _rt, _),
    do: unrenderable!(value)

  # Calculation arguments as an object literal; `quote_keys?` selects JSON-style
  # quoted keys over the bare keys of the `%{args:, fields:}` form.
  defp format_args_map(%{} = args, resource, calc, rt, quote_keys?) do
    formatted_args =
      args
      |> Enum.map(fn {k, v} ->
        {resolved!(AshRpc.ClientNames.calc_arg(rt, resource.module, calc, k), k), v}
      end)
      |> Enum.sort_by(fn {k, _v} -> to_string(k) end)
      |> Enum.map_join(", ", fn {k, v} ->
        key = ClientNames.calculation_argument(resource, calc, k)
        key = if quote_keys?, do: ~s["#{key}"], else: key
        "#{key}: #{Jason.encode!(v)}"
      end)

    "{ #{formatted_args} }"
  end

  defp format_args_map(args, _resource, _calc, _rt, _quote_keys?), do: unrenderable!(args)

  # A filter as the destination's `FilterInput`: fields and relationships by
  # their client names, `and`/`or`/`not` and operators through the
  # `:filter_ops` vocabulary. The generated type takes connectives as arrays
  # and operators as objects, so a single statement under a connective becomes
  # a one-element array and a bare value its `eq`, which is how the runtime
  # reads both. Operator values are rendered through the operator's value
  # type (`filter_value/3`); the generated type has no calculation `input`.
  defp format_filter(%{} = filter, resource, rt) when not is_struct(filter) do
    entries =
      filter
      |> Enum.map(fn {key, value} -> filter_entry(resource, key, value, rt) end)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map_join(", ", fn {key, rendered} -> "#{key}: #{rendered}" end)

    "{ #{entries} }"
  end

  # A list is the `and` of its statements, as the runtime reads it, and an
  # entry of a keyword list one statement.
  defp format_filter(filter, resource, rt) when is_list(filter) do
    "{ #{ClientNames.vocabulary!(:filter_ops, :and)}: #{format_statements(filter, resource, rt)} }"
  end

  defp format_filter({key, value}, resource, rt), do: format_filter(%{key => value}, resource, rt)

  defp format_filter(filter, _resource, _rt), do: unrenderable!(filter)

  defp filter_entry(resource, key, value, rt) do
    with {:ok, name} <- AshRpc.ClientNames.resource_field(rt, resource.module, key),
         {:ok, entry} <- filter_target(resource, name) do
      rendered =
        case entry do
          {:relationship, destination} -> format_filter(value, destination, rt)
          :field -> format_filter_ops(value, resource, Map.fetch!(resource.fields, name), rt)
        end

      {ClientNames.resource_field(resource, name), rendered}
    else
      # Not a field: a connective, since `VerifyTypedQueryFields` rejects
      # any other key, as the runtime does.
      _ ->
        {:ok, op} = AshRpc.ClientNames.vocabulary(rt, :filter_ops, key)
        statements = if is_list(value), do: value, else: [value]
        {ClientNames.vocabulary!(:filter_ops, op), format_statements(statements, resource, rt)}
    end
  end

  defp format_statements(statements, resource, rt),
    do: "[#{Enum.map_join(statements, ", ", &format_filter(&1, resource, rt))}]"

  # Fields take precedence over relationships, as in the runtime's filter.
  defp filter_target(resource, name) do
    cond do
      Map.has_key?(resource.fields, name) ->
        {:ok, :field}

      relationship = Manifest.Resource.get_relationship(resource, name) ->
        {:ok,
         {:relationship, Map.fetch!(AshTypescript.resource_lookup(), relationship.destination)}}

      true ->
        :error
    end
  end

  defp format_filter_ops(%{} = ops, resource, field, rt) when not is_struct(ops) do
    entries =
      ops
      |> Enum.map(fn {key, value} -> {vocabulary_name!(rt, :filter_ops, key), value} end)
      |> Enum.sort_by(fn {op, _value} -> to_string(op) end)
      |> Enum.map_join(", ", fn
        {:input, _args} ->
          raise ArgumentError,
                "cannot render the filter on #{inspect(field.name)} of #{inspect(resource.module)} " <>
                  "in a typed query's fields: the generated filter types don't support " <>
                  "calculation arguments (input)"

        {op, value} ->
          "#{ClientNames.vocabulary!(:filter_ops, op)}: " <>
            filter_value(value, operator_value_type(field, op), rt)
      end)

    "{ #{entries} }"
  end

  # Operators as a keyword list (the runtime tells them from a list value by
  # their first entry being a tuple), else a bare value as `eq`.
  defp format_filter_ops([entry | _] = ops, resource, field, rt) when is_tuple(entry),
    do: format_filter_ops(Map.new(ops), resource, field, rt)

  defp format_filter_ops(value, resource, field, rt),
    do: format_filter_ops(%{eq: value}, resource, field, rt)

  # The type an operator's value takes, as the runtime's filter reads it: the
  # field's own type, one element of it (`has`), a list of either (`in`,
  # `intersects`), or nil for a concrete scalar (`isNil`).
  defp operator_value_type(%Manifest.Field{} = field, op) do
    case AshRpc.Introspection.filter_operator_value_type(field, op) do
      {:concrete, _module} -> nil
      type -> type
    end
  end

  # A filter value in the input shape the generated FilterInput types take
  # (`TypeMapper.map_plain_type(type, :input)`): a union value as its member
  # wrapped by the member's client name, a value of a type with fields (typed
  # map, struct, keyword, tuple) as an object of the fields' client names,
  # each named and nested through its own type. Keys are internal atoms or
  # client strings, as the runtime's `ValueFormatter.format_input/3` reads them.
  defp filter_value(value, %Manifest.Type{} = type, rt) do
    case ClientNames.resolve_type!(type) do
      %Manifest.Type{kind: :array, item_type: %Manifest.Type{} = item} when is_list(value) ->
        "[#{Enum.map_join(value, ", ", &filter_value(&1, item, rt))}]"

      %Manifest.Type{kind: :union} = union
      when is_map(value) and not is_struct(value) and map_size(value) == 1 ->
        [{member, member_value}] = Map.to_list(value)
        internal = resolved!(AshRpc.ClientNames.union_member(rt, union, member), member)
        %{type: member_type} = Manifest.Type.find_member(union, internal)

        "{ #{ClientNames.union_member(union, internal)}: " <>
          "#{filter_value(member_value, member_type, rt)} }"

      %Manifest.Type{} = typed when is_map(value) and not is_struct(value) ->
        map_filter_value(value, typed, rt)

      # A tuple field's value as its elements in order
      %Manifest.Type{kind: :tuple, element_types: elements} = typed
      when is_tuple(value) and tuple_size(value) == length(elements) ->
        elements
        |> Enum.map(& &1.name)
        |> Enum.zip(Tuple.to_list(value))
        |> Map.new()
        |> map_filter_value(typed, rt)

      _ ->
        json_value!(value)
    end
  end

  defp filter_value(value, nil, _rt), do: json_value!(value)

  # An untyped map (`Record<string, any>`) is sent with its keys as written.
  defp map_filter_value(value, typed, rt) do
    if Manifest.Type.has_fields?(typed) do
      entries =
        value
        |> Map.new(fn {key, field_value} ->
          {resolved!(AshRpc.ClientNames.type_field(rt, typed, key), key), field_value}
        end)
        |> Enum.sort_by(fn {key, _} -> to_string(key) end)
        |> Enum.map_join(", ", fn {key, field_value} ->
          "#{ClientNames.type_field(typed, key)}: " <>
            filter_value(field_value, Manifest.Type.find_field_type(typed, key), rt)
        end)

      "{ #{entries} }"
    else
      Jason.encode!(value)
    end
  end

  defp resolved!({:ok, name}, _key), do: name
  defp resolved!(:error, key), do: unrenderable!(key)

  # A sort as `SortString`s: one string for a single field, else an array. Names
  # resolve as the runtime's sort does: a string is a client name after its
  # `+`/`-`/`++`/`--` prefix, an atom an internal name.
  defp format_sort(sort, resource, rt) when is_binary(sort) do
    case String.split(sort, ",") do
      [single] -> format_sort_entry(single, resource, rt)
      entries -> format_sort(entries, resource, rt)
    end
  end

  # `VerifyTypedQueryFields` rejects any other sort, as the runtime does.
  defp format_sort(sort, resource, rt) when is_list(sort),
    do: "[#{Enum.map_join(sort, ", ", &format_sort_entry(&1, resource, rt))}]"

  defp format_sort_entry(entry, resource, rt) when is_binary(entry) do
    {modifier, name} = AshRpc.FilterInput.split_sort_modifier(entry)
    field = internal({:resource, resource}, name, rt)
    Jason.encode!(modifier <> ClientNames.resource_field(resource, field))
  end

  defp format_sort_entry(entry, resource, _rt) when is_atom(entry),
    do: Jason.encode!(ClientNames.resource_field(resource, entry))

  # A scalar. A map, list or tuple reaches this only where the runtime rejects
  # it (a scalar operator's value, a page option), which
  # `VerifyTypedQueryFields` reports, or as a keyword list for a keyword field,
  # which the runtime takes but the generated types (an object of its fields)
  # have no form for. Lists the operator takes (`in`, array fields) are
  # rendered through their item type.
  defp json_value!(value) when is_list(value) or is_tuple(value), do: unrenderable!(value)
  defp json_value!(value), do: Jason.encode!(value)

  # The internal name of a field, typed map field or union member given by
  # internal atom or client string.
  defp internal(_ctx, name, _rt) when is_atom(name), do: name

  defp internal(ctx, name, rt) when is_binary(name) do
    case ctx do
      {:resource, resource} -> AshRpc.ClientNames.resource_field(rt, resource.module, name)
      {:type, type} -> AshRpc.ClientNames.type_field(rt, type, name)
      {:union, type} -> AshRpc.ClientNames.union_member(rt, type, name)
    end
    |> resolved!(name)
  end

  defp internal(_ctx, name, _rt), do: unrenderable!(name)

  defp vocabulary_name!(rt, scope, key),
    do: resolved!(AshRpc.ClientNames.vocabulary(rt, scope, key), key)

  # `VerifyTypedQueryFields` ran the selection, filters and sorts through the
  # runtime, so a shape the runtime rejects never reaches this; what does is a
  # form the runtime takes but the generated types can't express (a keyword
  # list for a keyword field).
  defp unrenderable!(part) do
    raise ArgumentError,
          "cannot render #{inspect(part)} in a typed query's fields: " <>
            "the generated TypeScript types have no form for it"
  end

  defp name({:resource, resource}, field), do: ClientNames.resource_field(resource, field)
  defp name({:type, type}, field), do: ClientNames.type_field(type, field)
  defp name({:union, type}, member), do: ClientNames.union_member(type, member)

  # The verifier ran the same selection through the runtime, so every field
  # and member named here exists in the manifest.
  defp descend({:resource, resource}, field) do
    case Manifest.Resource.get_relationship(resource, field) do
      %Manifest.Relationship{destination: destination} ->
        resource_context(destination)

      nil ->
        %Manifest.Field{type: type} = Manifest.Resource.get_field(resource, field)
        context_for(type)
    end
  end

  defp descend({:type, type}, field) do
    %Manifest.Type{} = field_type = Manifest.Type.find_field_type(type, field)
    context_for(field_type)
  end

  defp descend({:union, type}, member) do
    %{type: %Manifest.Type{} = member_type} = Manifest.Type.find_member(type, member)
    context_for(member_type)
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

  defp resource_context(module),
    do: {:resource, Map.fetch!(AshTypescript.resource_lookup(), module)}
end
