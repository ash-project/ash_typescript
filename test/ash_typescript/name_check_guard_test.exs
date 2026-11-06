# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.NameCheckGuardTest do
  # Every name codegen reads or builds is a `NameCheck` slot, so the check
  # sees every generated name. The test traces the name readers and builders
  # while codegen runs over the test app, and matches what each call returns
  # to a slot of the test app's manifest with that name at the call's
  # position: the same owner and raw name, or as much of them as the call's
  # arguments carry (`at?/3`).
  use ExUnit.Case, async: false

  alias Ash.Info.Manifest.Type
  alias AshTypescript.Codegen.ClientNames
  alias AshTypescript.Codegen.ScalarAliases
  alias AshTypescript.Codegen.SchemaCore
  alias AshTypescript.Manifest.Custom
  alias AshTypescript.Manifest.NameCheck
  alias AshTypescript.Manifest.TypeUses
  alias AshTypescript.Rpc.Codegen.FunctionNames
  alias AshTypescript.TypedController.Codegen, as: TypedControllerCodegen

  @traced [
    {AshTypescript.Codegen.ClientNames, :resource_field},
    {AshTypescript.Codegen.ClientNames, :calculation_argument},
    {AshTypescript.Codegen.ClientNames, :action_input},
    {AshTypescript.Codegen.ClientNames, :type_field},
    {AshTypescript.Codegen.ClientNames, :union_member},
    {AshTypescript.Codegen.ClientNames, :metadata_field},
    {AshTypescript.Codegen.ClientNames, :vocabulary!},
    {AshTypescript.Rpc.Codegen.FunctionNames, :execution},
    {AshTypescript.Rpc.Codegen.FunctionNames, :validation},
    {AshTypescript.Rpc.Codegen.FunctionNames, :channel},
    {AshTypescript.Rpc.Codegen.FunctionNames, :validation_channel},
    {AshTypescript.Rpc.Codegen.FunctionNames, :input_type},
    {AshTypescript.Rpc.Codegen.FunctionNames, :result_type},
    {AshTypescript.Rpc.Codegen.FunctionNames, :fields_type},
    {AshTypescript.Rpc.Codegen.FunctionNames, :infer_result_type},
    {AshTypescript.Rpc.Codegen.FunctionNames, :config_type},
    {AshTypescript.Rpc.Codegen.FunctionNames, :metadata_type},
    {AshTypescript.Rpc.Codegen.FunctionNames, :restricted_schema},
    {AshTypescript.Rpc.Codegen.FunctionNames, :typed_query_const},
    {AshTypescript.Rpc.Codegen.FunctionNames, :typed_query_result_type},
    {AshTypescript.Codegen.SchemaCore, :action_schema_name},
    {AshTypescript.TypedController.Codegen, :route_function_name},
    {AshTypescript.TypedController.Codegen, :route_input_type_name},
    {AshTypescript.TypedController.Codegen, :route_result_type_name},
    {AshTypescript.TypedController.Codegen, :route_zod_schema_name},
    {AshTypescript.TypedController.Codegen, :route_valibot_schema_name},
    {AshTypescript.TypedChannel.Codegen, :payload_type_name},
    {AshTypescript.Helpers, :format_output_field},
    {AshTypescript.Manifest.Custom, :type_alias_names},
    {AshTypescript.Codegen.ScalarAliases, :name}
  ]

  setup_all do
    manifest = AshTypescript.manifest()
    custom_types = Custom.custom_types()
    # `RouteRenderer` reads each route argument's client name off the route.
    route_arguments =
      for route <- Custom.routes(manifest),
          input <- route.inputs,
          do: %{
            mfa: {AshTypescript.Manifest.RouteArgument, :client_name, 0},
            args: [route, input],
            name: input.client_name
          }

    slots = NameCheck.slots(manifest, custom_types)

    %{
      manifest: manifest,
      slots_by_name: Enum.group_by(slots, & &1.name),
      nodes: nodes_at(manifest),
      emitted: trace_codegen(custom_types) ++ route_arguments
    }
  end

  test "every name codegen reads or builds is the name of a NameCheck slot at its position",
       context do
    assert missing(context.emitted, context) == []
  end

  test "the guard sees names from every traced function", %{emitted: emitted} do
    seen = MapSet.new(emitted, fn %{mfa: {m, f, _a}} -> {m, f} end)

    for {module, function} <- @traced do
      assert {module, function} in seen,
             "no name traced from #{inspect(module)}.#{function}"
    end
  end

  test "a name outside the slots fails the guard", context do
    fake = %{
      mfa: {AshTypescript.Codegen.ClientNames, :resource_field, 2},
      args: [AshTypescript.Test.Todo, :title],
      name: "notASlot"
    }

    assert missing([fake | context.emitted], context) == [{fake.mfa, "notASlot"}]
  end

  test "a slot's name at another position doesn't cover a name", context do
    # `title` is a field of more than one resource, so its name is a slot
    # name; a field of another resource that isn't one is still reported.
    assert Enum.count(context.slots_by_name["title"], &(&1.kind == :resource_field)) > 1

    stray = %{
      mfa: {AshTypescript.Codegen.ClientNames, :resource_field, 2},
      args: [AshTypescript.Test.NotExposed, :title],
      name: "title"
    }

    assert missing([stray | context.emitted], context) == [{stray.mfa, "title"}]
  end

  # The traced names no slot at their position carries.
  defp missing(emitted, context) do
    emitted
    |> Enum.reject(fn %{name: name} = entry ->
      context.slots_by_name
      |> Map.get(name, [])
      |> Enum.any?(&at?(&1, entry, context.nodes))
    end)
    |> Enum.map(&{&1.mfa, &1.name})
    |> Enum.uniq()
  end

  # Whether `slot` is the slot of the traced call: the same owner, or as
  # much of it as the call's arguments carry.
  defp at?(slot, %{mfa: {ClientNames, :resource_field, 2}, args: [resource, field]}, _nodes),
    do: resource_field?(slot, resource_module(resource), field)

  defp at?(
         slot,
         %{mfa: {ClientNames, :calculation_argument, 3}, args: [resource, calc, arg]},
         _nodes
       ),
       do:
         slot.kind == :calculation_argument and
           slot.owner == {:calculation, calc, resource_module(resource)} and slot.raw == arg

  # An action input that is a field of its resource is named as the field.
  defp at?(slot, %{mfa: {ClientNames, :action_input, 3}, args: [resource, action, input]}, _n) do
    module = resource_module(resource)

    resource_field?(slot, module, input) or
      (slot.kind == :action_argument and match?({:action, _, ^module, _}, slot.owner) and
         elem(slot.owner, 1) == action.name and slot.raw == input)
  end

  # A type node is matched to the positions it sits at; a resource node's
  # fields are its resource's.
  defp at?(slot, %{mfa: {ClientNames, :type_field, 2}, args: [type, field]}, nodes) do
    case ClientNames.resolve_type!(type) do
      %Type{kind: kind} = t when kind in [:resource, :embedded_resource] ->
        resource_field?(slot, Type.effective_resource(t), field)

      t ->
        slot.kind == :type_field and slot.raw == field and
          Map.get(nodes, {slot.owner, slot.path}) == t
    end
  end

  defp at?(slot, %{mfa: {ClientNames, :union_member, 2}, args: [type, member]}, nodes),
    do:
      slot.kind == :union_member and slot.raw == member and
        Map.get(nodes, {slot.owner, slot.path}) == ClientNames.resolve_type!(type)

  defp at?(slot, %{mfa: {ClientNames, :metadata_field, 2}, args: [entrypoint, field]}, _n),
    do:
      slot.kind == :metadata_field and slot.raw == field and
        match?({:rpc_action, _, _}, slot.owner) and
        to_string(elem(slot.owner, 1)) == entrypoint.name

  defp at?(slot, %{mfa: {FunctionNames, f, _a}, args: [rpc_name | _]}, _n)
       when f in [
              :execution,
              :validation,
              :channel,
              :validation_channel,
              :input_type,
              :result_type,
              :fields_type,
              :infer_result_type,
              :config_type,
              :metadata_type,
              :restricted_schema
            ],
       do: binding?(slot, :rpc_function, f, rpc_name)

  defp at?(slot, %{mfa: {FunctionNames, :typed_query_const, _a}, args: [typed_query | _]}, _n),
    do: binding?(slot, :typed_query_const, :const, typed_query.name)

  defp at?(slot, %{mfa: {FunctionNames, :typed_query_result_type, 1}, args: [tq]}, _n),
    do: binding?(slot, :typed_query_const, :result_type, tq.name)

  defp at?(
         slot,
         %{mfa: {SchemaCore, :action_schema_name, _a}, args: [generator, rpc_name | _]},
         _n
       ) do
    role =
      if generator == AshTypescript.Codegen.ZodSchemaGenerator,
        do: :zod_schema,
        else: :valibot_schema

    binding?(slot, :rpc_function, role, rpc_name)
  end

  defp at?(
         slot,
         %{mfa: {TypedControllerCodegen, :route_function_name, _a}, args: [route, _p, kind | _]},
         _n
       ) do
    route_binding?(slot, route, if(kind == :path, do: :path, else: :function))
  end

  defp at?(slot, %{mfa: {TypedControllerCodegen, f, _a}, args: [route | _]}, _n) do
    role =
      case f do
        :route_input_type_name -> :input_type
        :route_result_type_name -> :result_type
        :route_zod_schema_name -> :zod_schema
        :route_valibot_schema_name -> :valibot_schema
      end

    route_binding?(slot, route, role)
  end

  defp at?(
         slot,
         %{mfa: {AshTypescript.Manifest.RouteArgument, :client_name, 0}, args: [route, input]},
         _n
       ),
       do:
         slot.kind == :route_argument and slot.owner == {:route, route.name, route.source_module} and
           slot.raw == input.name

  defp at?(
         slot,
         %{mfa: {AshTypescript.TypedChannel.Codegen, :payload_type_name, 1}, args: [event]},
         _n
       ),
       do: binding?(slot, :channel_event, :payload_type, event)

  # `format_output_field/1` only gets the raw name: a static key, or the
  # name of an rpc_action, a route or a route argument codegen formats again.
  defp at?(slot, %{mfa: {AshTypescript.Helpers, :format_output_field, 1}, args: [raw]}, _n) do
    slot.raw == raw and
      (slot.kind in [:static_field, :route_argument] or
         (slot.kind == :rpc_function and slot.role == :execution) or
         (slot.kind == :route_function and slot.role == :function))
  end

  # A request key of ash_rpc's vocabulary is a static key.
  defp at?(slot, %{mfa: {ClientNames, :vocabulary!, 2}, args: [_scope, raw]}, _n),
    do: slot.kind == :static_field and slot.raw == raw

  defp at?(slot, %{mfa: {ClientNames, :vocabulary!, 3}, args: [_manifest, _scope, raw]}, _n),
    do: slot.kind == :static_field and slot.raw == raw

  defp at?(slot, %{mfa: {Custom, :type_alias_names, 1}, args: [type]}, _n),
    do: slot.kind == :map_alias and slot.owner == {:type, type.module}

  defp at?(slot, %{mfa: {ScalarAliases, :name, 2}, args: [node, _ct]}, _n),
    do: slot.kind == :scalar_alias and slot.owner == {:type, node.module}

  defp resource_field?(slot, module, field),
    do: slot.kind == :resource_field and slot.owner == {:resource, module} and slot.raw == field

  defp binding?(slot, kind, role, raw),
    do: slot.kind == kind and slot[:role] == role and to_string(slot.raw) == to_string(raw)

  # Codegen passes the manifest route or the DSL route, which has no
  # `source_module`; route names are matched with the source when given.
  defp route_binding?(slot, route, role) do
    binding?(slot, slot.kind, role, route.name) and slot.kind in [:route_function, :route_schema] and
      case Map.get(route, :source_module) do
        nil -> true
        source -> slot.owner == {:route, route.name, source}
      end
  end

  defp resource_module(%{module: module}), do: module
  defp resource_module(module) when is_atom(module), do: module

  # Every type node the manifest reaches, by owner and path.
  defp nodes_at(manifest) do
    for {owner, path, node} <- TypeUses.positions(manifest), into: %{}, do: {{owner, path}, node}
  end

  # ── tracing ──────────────────────────────────────────────────────

  defp trace_codegen(custom_types) do
    match_spec = [{:_, [], [{:exception_trace}]}]

    for {module, function} <- @traced do
      Code.ensure_loaded!(module)
      :erlang.trace_pattern({module, function, :_}, match_spec, [:local])
    end

    # A process can't be its own tracer: the messages go to a collector.
    collector = spawn_link(fn -> collect([], []) end)
    :erlang.trace(self(), true, [:call, {:tracer, collector}])

    try do
      {:ok, _content} = AshTypescript.Test.CodegenTestHelper.generate_all_content()
    after
      :erlang.trace(self(), false, [:call])

      for {module, function} <- @traced,
          do: :erlang.trace_pattern({module, function, :_}, false, [:local])
    end

    ref = :erlang.trace_delivered(self())

    receive do
      {:trace_delivered, _pid, ^ref} -> send(collector, {:done, self()})
    end

    receive do
      {:traced, calls} -> Enum.flat_map(calls, &emitted_names(&1, custom_types))
    end
  end

  # Pairs each traced call with its return: calls nest, so the return of the
  # innermost open call comes first. `:done` is sent once every trace
  # message is delivered (`:erlang.trace_delivered/1`).
  defp collect(stack, acc) do
    receive do
      {:trace, _pid, :call, {m, f, args}} ->
        collect([{m, f, args} | stack], acc)

      {:trace, _pid, :return_from, {m, f, arity}, value} ->
        [{^m, ^f, args} | stack] = stack
        collect(stack, [{{m, f, arity}, args, value} | acc])

      {:trace, _pid, :exception_from, {m, f, _arity}, _exception} ->
        [{^m, ^f, _args} | stack] = stack
        collect(stack, acc)

      {:done, from} ->
        send(from, {:traced, Enum.reverse(acc)})
    end
  end

  defp emitted_names({mfa, args, value}, custom_types) do
    if exempt?(mfa, args, custom_types) do
      []
    else
      case name(mfa, value) do
        nil -> []
        name -> [%{mfa: mfa, args: args, name: name}]
      end
    end
  end

  # The route builders under a scope prefix (multi-mount `as:`), whose names
  # the check doesn't cover (spec Non-Goals); `route_function_name/1`, whose
  # name is its `/4` call's; schema names of routes without arguments, never
  # emitted; and MFA scalar aliases, named per use at codegen.
  defp exempt?({AshTypescript.TypedController.Codegen, :route_function_name, 1}, _args, _ct),
    do: true

  defp exempt?({AshTypescript.TypedController.Codegen, _f, _arity}, [_route, prefix | _], _ct)
       when prefix != nil,
       do: true

  # `RouteRenderer.render_zod_schema/1` (and the valibot one) builds the
  # schema name before it finds that a route without arguments has no schema.
  defp exempt?({AshTypescript.TypedController.Codegen, f, _arity}, [route | _], _ct)
       when f in [:route_zod_schema_name, :route_valibot_schema_name],
       do: route.inputs == []

  defp exempt?({ScalarAliases, :name, 2}, [node, _ct], custom_types),
    do: match?({:entry, %{ts_alias: {_m, _f, _a}}}, ScalarAliases.source(node, custom_types))

  # Filter operator and function keys (`eq`, `notEq`, …) aren't NameCheck
  # slots: ash_rpc's vocabulary names them, and codegen only reads them.
  defp exempt?({ClientNames, :vocabulary!, 2}, [:filter_ops, _raw], _ct), do: true
  defp exempt?({ClientNames, :vocabulary!, 3}, [_manifest, :filter_ops, _raw], _ct), do: true

  defp exempt?(_mfa, _args, _custom_types), do: false

  defp name({AshTypescript.Manifest.Custom, :type_alias_names, 1}, value),
    do: if(is_map(value), do: value.typescript)

  defp name(_mfa, value) when is_binary(value), do: value
  defp name(_mfa, _value), do: nil
end
