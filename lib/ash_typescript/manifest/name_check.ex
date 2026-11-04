# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.NameCheck do
  @moduledoc """
  The walk over a decorated manifest that finds every name codegen emits, one
  slot each, and checks each with its family's rule in
  `AshTypescript.NameValidation`.

  The three families are:

    * client names, the keys of generated objects (`:resource_field`,
      `:calculation_argument`, `:action_argument`, `:metadata_field`,
      `:type_field`, `:union_member`, `:route_argument`), read from the
      `custom.ash_rpc` decoration as codegen's `ClientNames` reads
      them, the route arguments' `client_name`, and the generated code's own
      keys under the output formatter (`:static_field`,
      `AshTypescript.Helpers.static_client_names/0`);
    * binding names, the generated functions, consts, types and schemas
      (`:rpc_function`, `:typed_query_const`, `:route_function`,
      `:route_schema`), and the typed channel events and their payload types
      (`:channel_event`), built with the builders codegen calls;
    * static type aliases (`:map_alias`, `:scalar_alias`).

  It holds no rule of its own: the verdicts are `NameValidation`'s.

  `AshTypescript.Manifest.Transformers.DecorateManifest` runs `check/2` on
  the decorated manifest when it compiles.
  """

  alias Ash.Info.Manifest
  alias Ash.Info.Manifest.Type
  alias AshRpc.Manifest.Custom, as: RpcCustom
  alias AshTypescript.Codegen.ScalarAliases
  alias AshTypescript.Codegen.SchemaCore
  alias AshTypescript.Codegen.ValibotSchemaGenerator
  alias AshTypescript.Codegen.ZodSchemaGenerator
  alias AshTypescript.CustomTypes
  alias AshTypescript.Manifest.TypeUses
  alias AshTypescript.NameValidation
  alias AshTypescript.Rpc.Codegen.FunctionNames
  alias AshTypescript.TypedController.Codegen

  @type family :: :client | :binding | :alias

  @type kind ::
          :resource_field
          | :calculation_argument
          | :action_argument
          | :metadata_field
          | :type_field
          | :union_member
          | :route_argument
          | :static_field
          | :rpc_function
          | :typed_query_const
          | :route_function
          | :route_schema
          | :channel_event
          | :map_alias
          | :scalar_alias

  @type source ::
          :formatter
          | {:field_names, resource :: module()}
          | {:argument_names, resource :: module(), action :: atom()}
          | {:metadata_field_names, rpc_name :: atom()}
          | {:typescript_field_names, module()}
          | {:client_name, module()}
          | {:option,
             :ts_fields_const_name
             | :ts_result_type_name
             | :zod_schema_name
             | :valibot_schema_name}
          | {:ts_alias, module()}
          | {:typescript_type_alias, module()}
          | {:builtin, module()}
          | :module_name

  @typedoc """
  One generated name. `owner` is where it sits (a `t:AshTypescript.Manifest.TypeUses.owner/0`
  for type fields and union members, else `{:resource, r}`, `{:calculation, calc, r}`,
  `{:action, action, r, rpc_names}`, `{:rpc_action, rpc_name, r}`,
  `{:route, route, source_module}`, `{:publication, event, r, channel}` or
  `:static`), and `path` the path from the owner's root type node to the node
  the name belongs to. `formatter` is the manifest's output formatter, for
  the suggestions in `describe/1`. `bare?` marks the one binding slot of an
  rpc_action, typed query or route that carries the raw-name rule. Binding
  slots also carry their `role` (`:execution`, `:zod_schema`, `:const`, …) and
  how the role is bound (`bound_as`: `:value`, `:type` or `:key`, the rule's
  argument); resource field slots whether the resource has the
  `AshTypescript.Resource` extension (`exposed?`); and type field slots their
  `container` (`{:map_entry, m}`, `{:module, m}` or `:inline`, what declares
  the fields), for the line and its fix.
  """
  @type slot :: %{
          optional(:role) => atom(),
          optional(:bound_as) => :value | :type | :key,
          optional(:exposed?) => boolean(),
          optional(:container) => {:map_entry, module()} | {:module, module()} | :inline,
          family: family(),
          kind: kind(),
          owner: tuple(),
          path: [String.t()],
          raw: atom() | module(),
          name: String.t(),
          bare?: boolean(),
          source: source(),
          formatter: term()
        }

  @type problem :: %{slot: slot(), reason: NameValidation.reason()}

  @families [:client, :binding, :alias]

  @doc "Every generated name the decorated manifest gives codegen, one slot each."
  @spec slots(Manifest.t(), CustomTypes.custom_types()) :: [slot()]
  def slots(%Manifest{} = manifest, custom_types) do
    formatter = AshRpc.Manifest.output_formatter(manifest)

    (client_slots(manifest, custom_types) ++
       binding_slots(manifest, formatter) ++ alias_slots(manifest, custom_types))
    |> Enum.uniq()
    |> Enum.map(&Map.put(&1, :formatter, formatter))
  end

  @doc "The slots that break a rule of their family, in report order."
  @spec problems(Manifest.t(), CustomTypes.custom_types()) :: [problem()]
  def problems(%Manifest{} = manifest, custom_types) do
    manifest
    |> slots(custom_types)
    |> Enum.flat_map(fn slot ->
      case rule(slot) do
        :ok -> []
        {:error, reason} -> [%{slot: slot, reason: reason}]
      end
    end)
    |> Enum.sort_by(&report_key/1)
  end

  # Family, then owner group, then raw name; slots of one raw name keep the
  # walk's order (a binding owner's bare name first).
  defp report_key(%{slot: slot}) do
    {group_key, _heading} = group(slot)
    {Enum.find_index(@families, &(&1 == slot.family)), group_key, to_string(slot.raw)}
  end

  @doc """
  `:ok`, or `{:error, message}` listing every problem: one section per family
  (client, binding, alias names), then one group per owner, each line
  `describe/1`'s.
  """
  @spec check(Manifest.t(), CustomTypes.custom_types()) :: :ok | {:error, String.t()}
  def check(%Manifest{} = manifest, custom_types) do
    case problems(manifest, custom_types) do
      [] -> :ok
      problems -> {:error, report(problems)}
    end
  end

  @doc """
  The problem's report line: the slot, its name, the reason and the fix for
  its source.
  """
  @spec describe(problem()) :: String.t()
  def describe(problem), do: line(problem, 0)

  defp rule(%{family: :client} = slot),
    do: NameValidation.check_client_name(slot.raw, slot.name, slot.source != :formatter)

  # The raw-name rule applies once per rpc_action, typed query and route: on
  # its one bare slot.
  defp rule(%{family: :binding, bare?: true} = slot) do
    with :ok <- NameValidation.check_binding_name(slot.name, slot.bound_as),
         do: NameValidation.check_raw_binding_name(slot.raw)
  end

  defp rule(%{family: :binding} = slot),
    do: NameValidation.check_binding_name(slot.name, slot.bound_as)

  defp rule(%{family: :alias} = slot),
    do: NameValidation.check_alias_name(slot.name, alias_subject(slot))

  # How `CustomTypes.check_name/2`'s message names the alias, by its source.
  defp alias_subject(%{source: {:typescript_type_alias, module}, name: name}),
    do: "The typescript_type_alias/0 result #{inspect(name)} of #{inspect(module)}"

  defp alias_subject(%{source: :module_name, raw: module, name: name}),
    do: "The alias #{inspect(name)} of #{inspect(module)} (its module name)"

  defp alias_subject(%{raw: module, name: name}),
    do: "The ts_alias #{inspect(name)} of #{inspect(module)}"

  # ── client slots ────────────────────────────────────────────────

  defp client_slots(manifest, custom_types) do
    resources =
      manifest
      |> AshRpc.Manifest.resource_lookup()
      |> Map.values()
      |> Enum.sort_by(& &1.module)

    positions = TypeUses.positions(manifest)

    Enum.flat_map(resources, &resource_field_slots/1) ++
      Enum.flat_map(resources, &calculation_argument_slots/1) ++
      action_argument_slots(manifest) ++
      metadata_field_slots(manifest) ++
      type_field_slots(positions, custom_types) ++
      union_member_slots(positions) ++
      route_argument_slots(manifest) ++
      static_field_slots(manifest)
  end

  # The generated code's own keys (`hasMore`, `fetchOptions`, …), named by the
  # output formatter.
  defp static_field_slots(manifest) do
    formatter = AshRpc.Manifest.output_formatter(manifest)

    for field <- AshTypescript.Helpers.static_client_names() do
      client_slot(
        :static_field,
        :static,
        [],
        field,
        AshRpc.FieldFormatter.format_field_name(field, formatter),
        :formatter
      )
    end
  end

  defp resource_field_slots(%Manifest.Resource{module: module} = resource) do
    overrides = RpcCustom.field_name_overrides(resource)

    exposed? = RpcCustom.exposed?(resource)

    for {field, name} <- RpcCustom.field_names(resource) do
      source = if Map.has_key?(overrides, field), do: {:field_names, module}, else: :formatter

      :resource_field
      |> client_slot({:resource, module}, [], field, name, source)
      |> Map.put(:exposed?, exposed?)
    end
  end

  defp calculation_argument_slots(%Manifest.Resource{module: module} = resource) do
    for %{kind: :calculation, name: calc} <- Manifest.Resource.all_fields(resource),
        {name, arg} <- RpcCustom.calculation_argument_names(resource, calc) do
      client_slot(:calculation_argument, {:calculation, calc, module}, [], arg, name, :formatter)
    end
  end

  defp action_argument_slots(%Manifest{} = manifest) do
    resource_lookup = AshRpc.Manifest.resource_lookup(manifest)

    manifest.entrypoints
    |> Enum.group_by(&{&1.resource, &1.action.name})
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.flat_map(fn {{module, action_name}, [%{action: action} | _] = group} ->
      resource = Map.get(resource_lookup, module)
      # The runtime names an input as a field only when it is a key of the
      # resource's fields (relationships aren't); anything else is an argument.
      fields = (resource && resource.fields) || %{}
      overrides = RpcCustom.argument_name_overrides(resource, action_name)

      owner = {:action, action_name, module, TypeUses.rpc_names(group)}

      for {name, input} <- RpcCustom.action_expected_input_keys(action) || %{},
          not Map.has_key?(fields, input) do
        source =
          if Map.has_key?(overrides, input),
            do: {:argument_names, module, action_name},
            else: :formatter

        client_slot(:action_argument, owner, [], input, name, source)
      end
    end)
  end

  defp metadata_field_slots(%Manifest{} = manifest) do
    manifest
    |> AshRpc.Manifest.entrypoint_lookup()
    |> Map.values()
    |> Enum.sort_by(& &1.name)
    |> Enum.flat_map(fn %AshRpc.Entrypoint{} = entrypoint ->
      rpc_name = String.to_existing_atom(entrypoint.name)

      for {field, name} <- RpcCustom.entrypoint_metadata_field_names(entrypoint) do
        source =
          if Map.has_key?(entrypoint.metadata_field_names, field),
            do: {:metadata_field_names, rpc_name},
            else: :formatter

        client_slot(
          :metadata_field,
          {:rpc_action, rpc_name, entrypoint.resource},
          [],
          field,
          name,
          source
        )
      end
    end)
  end

  defp type_field_slots(positions, %{declared: declared, builtin: builtin}) do
    entry_of = &(Map.get(declared, &1) || Map.get(builtin, &1))

    for {owner, path, %Type{kind: kind} = node} <- positions,
        kind in [:map, :keyword, :tuple, :struct],
        overrides = RpcCustom.type_field_name_overrides(node),
        container = container(owner, path, node, entry_of),
        {field, name} <- RpcCustom.type_field_names(node) do
      source =
        case {Map.has_key?(overrides, field), container} do
          {false, _container} -> :formatter
          {true, {:map_entry, module}} -> {:client_name, module}
          {true, _container} -> {:typescript_field_names, Type.effective_module(node)}
        end

      Map.put(client_slot(:type_field, owner, path, field, name, source), :container, container)
    end
  end

  # What declares a type node's fields, for the fix of a formatter-made name:
  # a `map` entry, a named module (a definition, or an inline struct's
  # `instance_of`), or the inline constraints of the position.
  defp container(owner, path, node, entry_of) do
    module = Type.effective_module(node)

    cond do
      match?({:type, _}, owner) and path == [] and CustomTypes.map_entry(module, entry_of) != nil ->
        {:map_entry, module}

      match?({:type, _}, owner) and path == [] ->
        {:module, module}

      node.instance_of != nil ->
        {:module, node.instance_of}

      true ->
        :inline
    end
  end

  defp union_member_slots(positions) do
    for {owner, path, %Type{kind: :union} = node} <- positions,
        {member, name} <- RpcCustom.type_member_names(node) do
      client_slot(:union_member, owner, path, member, name, :formatter)
    end
  end

  defp route_argument_slots(%Manifest{} = manifest) do
    for route <- AshTypescript.Manifest.Custom.routes(manifest), input <- route.inputs do
      client_slot(
        :route_argument,
        {:route, route.name, route.source_module},
        [],
        input.name,
        input.client_name,
        :formatter
      )
    end
  end

  defp client_slot(kind, owner, path, raw, name, source) do
    %{
      family: :client,
      kind: kind,
      owner: owner,
      path: path,
      raw: raw,
      name: name,
      bare?: false,
      source: source
    }
  end

  # ── binding slots ───────────────────────────────────────────────

  defp binding_slots(%Manifest{} = manifest, formatter) do
    rpc_function_slots(manifest, formatter) ++
      typed_query_slots(manifest, formatter) ++
      route_slots(manifest, formatter) ++
      publication_slots(manifest)
  end

  # A typed channel event is an unquoted key of `<Channel>Events`, and names
  # its payload type.
  defp publication_slots(manifest) do
    for publication <- AshTypescript.Manifest.Custom.publications(manifest),
        owner =
          {:publication, publication.event, publication.resource, publication.channel_module},
        {role, name} <- [
          event: publication.event,
          payload_type: AshTypescript.TypedChannel.Codegen.payload_type_name(publication.event)
        ] do
      binding_slot(:channel_event, role, owner, publication.event, name, false, :formatter)
    end
  end

  defp rpc_function_slots(manifest, formatter) do
    for entrypoint <- manifest.entrypoints,
        rpc_action = AshTypescript.Manifest.Custom.rpc_action(entrypoint),
        rpc_action != nil,
        owner =
          {:rpc_action, rpc_action.name,
           AshTypescript.Manifest.Custom.entrypoint_domain(entrypoint)},
        {role, name, bare?} <- rpc_function_names(rpc_action.name, formatter) do
      binding_slot(:rpc_function, role, owner, rpc_action.name, name, bare?, :formatter)
    end
  end

  defp rpc_function_names(rpc_name, formatter) do
    [
      {:execution, FunctionNames.execution(rpc_name, formatter), true},
      {:validation, FunctionNames.validation(rpc_name, formatter), false},
      {:channel, FunctionNames.channel(rpc_name, formatter), false},
      {:validation_channel, FunctionNames.validation_channel(rpc_name, formatter), false},
      {:input_type, FunctionNames.input_type(rpc_name), false},
      {:zod_schema, SchemaCore.action_schema_name(ZodSchemaGenerator, rpc_name, formatter),
       false},
      {:valibot_schema,
       SchemaCore.action_schema_name(ValibotSchemaGenerator, rpc_name, formatter), false}
    ]
  end

  defp typed_query_slots(manifest, formatter) do
    for entrypoint <- manifest.entrypoints,
        typed_query = AshTypescript.Manifest.Custom.typed_query(entrypoint),
        typed_query != nil do
      owner =
        {:typed_query, typed_query.name,
         AshTypescript.Manifest.Custom.entrypoint_domain(entrypoint)}

      [
        binding_slot(
          :typed_query_const,
          :const,
          owner,
          typed_query.name,
          FunctionNames.typed_query_const(typed_query, formatter),
          true,
          option_source(typed_query.ts_fields_const_name, :ts_fields_const_name)
        ),
        binding_slot(
          :typed_query_const,
          :result_type,
          owner,
          typed_query.name,
          FunctionNames.typed_query_result_type(typed_query),
          false,
          option_source(typed_query.ts_result_type_name, :ts_result_type_name)
        )
      ]
    end
    |> List.flatten()
  end

  defp route_slots(manifest, formatter) do
    manifest
    |> AshTypescript.Manifest.Custom.routes()
    |> Enum.flat_map(fn route ->
      owner = {:route, route.name, route.source_module}
      slot = &binding_slot(&1, &2, owner, route.name, &3, &4, &5)

      functions = [
        slot.(
          :route_function,
          :function,
          Codegen.route_function_name(route, nil, :action, formatter),
          true,
          :formatter
        ),
        slot.(
          :route_function,
          :path,
          Codegen.route_function_name(route, nil, :path, formatter),
          false,
          :formatter
        ),
        slot.(
          :route_function,
          :input_type,
          Codegen.route_input_type_name(route, nil),
          false,
          :formatter
        ),
        slot.(
          :route_function,
          :result_type,
          Codegen.route_result_type_name(route, nil),
          false,
          :formatter
        )
      ]

      schemas =
        if route.inputs == [] do
          []
        else
          [
            slot.(
              :route_schema,
              :zod_schema,
              Codegen.route_zod_schema_name(route, nil, formatter),
              false,
              option_source(route.zod_schema_name, :zod_schema_name)
            ),
            slot.(
              :route_schema,
              :valibot_schema,
              Codegen.route_valibot_schema_name(route, nil, formatter),
              false,
              option_source(route.valibot_schema_name, :valibot_schema_name)
            )
          ]
        end

      functions ++ schemas
    end)
  end

  # How the generated code binds a name of this role: as an exported type, or
  # as an exported function or const.
  defp bound_as(role) when role in [:input_type, :result_type, :payload_type], do: :type
  defp bound_as(:event), do: :key
  defp bound_as(_role), do: :value

  defp option_source(nil, _option), do: :formatter
  defp option_source(_value, option), do: {:option, option}

  defp binding_slot(kind, role, owner, raw, name, bare?, source) do
    %{
      family: :binding,
      kind: kind,
      role: role,
      bound_as: bound_as(role),
      owner: owner,
      path: [],
      raw: raw,
      name: name,
      bare?: bare?,
      source: source
    }
  end

  # ── alias slots ─────────────────────────────────────────────────

  defp alias_slots(%Manifest{} = manifest, custom_types) do
    map_alias_slots(manifest, custom_types) ++ scalar_alias_slots(manifest, custom_types)
  end

  defp map_alias_slots(%Manifest{types: types}, custom_types) do
    for %Type{module: module} = type <- types,
        %{typescript: name} when is_binary(name) <- [
          AshTypescript.Manifest.Custom.type_alias_names(type)
        ] do
      alias_slot(:map_alias, module, name, map_alias_source(module, custom_types))
    end
  end

  # The source `CustomTypes.alias_name/3` takes the alias from, in its order.
  defp map_alias_source(module, %{declared: declared, builtin: builtin}) do
    cond do
      match?(%CustomTypes.MapType{ts_alias: name} when is_binary(name), declared[module]) ->
        {:ts_alias, module}

      Code.ensure_loaded?(module) and function_exported?(module, :typescript_type_alias, 0) ->
        {:typescript_type_alias, module}

      match?(%CustomTypes.MapType{ts_alias: name} when is_binary(name), builtin[module]) ->
        {:builtin, module}

      true ->
        :module_name
    end
  end

  # One slot per scalar module whose uses get a static alias: a string
  # `ts_alias` of its entry, or its `typescript_type_alias/0` (read unchecked,
  # so this check reports it). MFA aliases are named per use at codegen.
  defp scalar_alias_slots(manifest, %{declared: declared} = custom_types) do
    manifest
    |> TypeUses.nodes()
    |> Enum.flat_map(fn node ->
      case ScalarAliases.source(node, custom_types) do
        {:entry, %CustomTypes.Scalar{ts_alias: name} = entry} when is_binary(name) ->
          source =
            if Map.get(declared, node.module) == entry,
              do: {:ts_alias, node.module},
              else: {:builtin, node.module}

          [alias_slot(:scalar_alias, node.module, name, source)]

        :callback ->
          case CustomTypes.callback_alias(node.module) do
            {:ok, name} ->
              [
                alias_slot(
                  :scalar_alias,
                  node.module,
                  name,
                  {:typescript_type_alias, node.module}
                )
              ]

            {:error, _not_a_string} ->
              []
          end

        _none_or_mfa ->
          []
      end
    end)
  end

  defp alias_slot(kind, module, name, source) do
    %{
      family: :alias,
      kind: kind,
      owner: {:type, module},
      path: [],
      raw: module,
      name: name,
      bare?: false,
      source: source
    }
  end

  # ── the report ──────────────────────────────────────────────────

  @intro %{
    client: """
    Client names (keys of generated objects) must be TypeScript identifiers
    ([A-Za-z_$][A-Za-z0-9_$]*). A name the formatter makes from a raw name with an underscore
    before a digit (line_1) is rejected too, since its client name (line1) doesn't tell line_1
    from line1.\
    """,
    binding: """
    Function, const, type and schema names must be TypeScript identifiers that aren't
    JavaScript reserved words, and a type name can't be a predefined TypeScript type name
    (string, any, …).\
    """,
    alias: "Type aliases:"
  }

  defp report(problems) do
    sections =
      problems
      |> Enum.chunk_by(& &1.slot.family)
      |> Enum.map(fn [%{slot: %{family: family}} | _] = family_problems ->
        groups =
          family_problems
          |> Enum.chunk_by(&group(&1.slot))
          |> Enum.map(fn [first | _] = group_problems ->
            {_key, heading} = group(first.slot)

            lines =
              group_problems
              |> collapse_derived()
              |> Enum.map_join("\n", fn {problem, derived} -> "    " <> line(problem, derived) end)

            "  #{heading}#{heading_note(group_problems)}:\n" <> lines
          end)

        Enum.join([@intro[family] | groups], "\n\n")
      end)

    "Invalid generated names found.\n\n" <> Enum.join(sections, "\n\n") <> "\n"
  end

  # One line for the formatter-made binding names of one owner that break the
  # same rule: the first (the bare one), with the count of the others.
  defp collapse_derived(problems) do
    {derived, others} =
      Enum.split_with(problems, &match?(%{slot: %{family: :binding, source: :formatter}}, &1))

    collapsed =
      derived
      |> Enum.group_by(& &1.reason)
      |> Enum.map(fn {_reason, [first | rest]} -> {first, length(rest)} end)

    Enum.sort_by(collapsed ++ Enum.map(others, &{&1, 0}), fn {problem, _} ->
      report_key(problem)
    end)
  end

  defp heading_note(problems) do
    if Enum.any?(problems, &match?(%{slot: %{container: {:map_entry, _}}}, &1)),
      do: " (custom_types map entry)",
      else: ""
  end

  # The owner group a slot is reported under, with its sort rank.
  defp group(%{family: :client, owner: owner}) do
    case owner do
      {:resource, r} ->
        {{0, r}, "Resource #{inspect(r)}"}

      {:calculation, _calc, r} ->
        {{0, r}, "Resource #{inspect(r)}"}

      {:action, _action, r, _rpc_names} ->
        {{0, r}, "Resource #{inspect(r)}"}

      {:rpc_action, _rpc_name, r} ->
        {{0, r}, "Resource #{inspect(r)}"}

      {:field, _kind, _name, r} ->
        {{0, r}, "Resource #{inspect(r)}"}

      {:calculation_argument, _calc, _arg, r} ->
        {{0, r}, "Resource #{inspect(r)}"}

      {kind, _name, _action, r, _rpc_names} when kind in [:action_argument, :action_metadata] ->
        {{0, r}, "Resource #{inspect(r)}"}

      {:action_returns, _action, r, _rpc_names} ->
        {{0, r}, "Resource #{inspect(r)}"}

      {:type, m} ->
        {{1, m}, "Type #{inspect(m)}"}

      {:route, route, source} ->
        route_group(route, source)

      {:route_argument, _arg, route, source} ->
        route_group(route, source)

      {:route_returns, route, source} ->
        route_group(route, source)

      {:publication, event, _r, channel} ->
        publication_group(event, channel)

      :static ->
        {{4, :static}, "The generated code's own keys"}
    end
  end

  defp group(%{family: :binding, owner: owner}) do
    case owner do
      {:rpc_action, name, domain} ->
        {{0, {domain, name}}, "RPC action #{inspect(name)} in #{inspect(domain)}"}

      {:typed_query, name, domain} ->
        {{1, {domain, name}}, "Typed query #{inspect(name)} in #{inspect(domain)}"}

      {:route, route, source} ->
        route_group(route, source)

      {:publication, event, _r, channel} ->
        publication_group(event, channel)
    end
  end

  defp group(%{family: :alias, owner: {:type, m}}), do: {{0, m}, inspect(m)}

  defp route_group(route, source),
    do: {{2, {source, route}}, "Route #{inspect(route)} of #{inspect(source)}"}

  defp publication_group(event, channel),
    do: {{3, {channel, event}}, "Publication #{inspect(event)} of #{inspect(channel)}"}

  # ── lines ───────────────────────────────────────────────────────

  defp line(%{slot: %{family: :alias}, reason: {:alias, message}}, _derived), do: "- " <> message

  defp line(%{slot: %{family: :binding} = slot, reason: :invalid_raw_name}, _derived) do
    "- name #{inspect(slot.raw)}, a question mark or an underscore before a digit: rename the " <>
      "#{binding_thing(slot.kind)}, e.g. :#{NameValidation.make_name_better(slot.raw)}"
  end

  defp line(%{slot: %{family: :binding} = slot, reason: reason}, derived) do
    derived = if derived > 0, do: " (and #{derived} derived names)", else: ""

    "- #{binding_what(slot.role)} #{inspect(slot.name)}#{option_note(slot.source)}#{derived}, " <>
      "#{reason_text(reason)}: #{binding_fix(slot, reason)}"
  end

  defp line(%{slot: %{family: :client} = slot, reason: reason}, _derived) do
    "- #{client_subject(slot)} → #{inspect(slot.name)} (#{provenance(slot.source)}), " <>
      "#{reason_text(reason)}: #{client_fix(slot)}"
  end

  defp option_note({:option, option}), do: " (#{option})"
  defp option_note(_source), do: ""

  defp reason_text(:not_identifier), do: "not an identifier"
  defp reason_text(:digit_after_underscore), do: "underscore before a digit"
  defp reason_text(:reserved_word), do: "a JavaScript reserved word"
  defp reason_text(:type_keyword), do: "a predefined TypeScript type name"

  defp binding_what(role) do
    case role do
      :execution -> "function"
      :validation -> "validation function"
      :channel -> "channel function"
      :validation_channel -> "validation channel function"
      :input_type -> "input type"
      :zod_schema -> "zod schema"
      :valibot_schema -> "valibot schema"
      :const -> "const"
      :result_type -> "result type"
      :function -> "function"
      :path -> "path helper"
      :event -> "event"
      :payload_type -> "payload type"
    end
  end

  defp binding_thing(:rpc_function), do: "rpc_action"
  defp binding_thing(:typed_query_const), do: "typed_query"
  defp binding_thing(kind) when kind in [:route_function, :route_schema], do: "route"
  defp binding_thing(:channel_event), do: "event"

  defp binding_fix(%{source: {:option, option}}, _reason), do: "change #{option}"

  defp binding_fix(%{kind: :route_schema, role: role}, _reason),
    do: "rename the route, or set #{role}_name"

  defp binding_fix(%{kind: :typed_query_const} = slot, :reserved_word),
    do: "rename the typed_query, for example :#{slot.raw}_item, or set ts_fields_const_name"

  defp binding_fix(slot, reason) when reason in [:reserved_word, :type_keyword],
    do: "rename the #{binding_thing(slot.kind)}, for example :#{slot.raw}_item"

  defp binding_fix(slot, :not_identifier),
    do: "rename the #{binding_thing(slot.kind)}, e.g. :#{NameValidation.suggest_name(slot.raw)}"

  defp client_subject(%{kind: :resource_field, raw: raw}), do: "field #{inspect(raw)}"
  defp client_subject(%{kind: :static_field, raw: raw}), do: "key #{inspect(raw)}"
  defp client_subject(%{kind: :route_argument, raw: raw}), do: "argument #{inspect(raw)}"

  defp client_subject(%{kind: :calculation_argument, owner: {:calculation, calc, _r}, raw: raw}),
    do: "argument #{inspect(raw)} of calculation #{inspect(calc)}"

  defp client_subject(%{
         kind: :action_argument,
         owner: {:action, action, _r, rpc_names},
         raw: raw
       }),
       do: "argument #{inspect(raw)}#{action_context(action, rpc_names)}"

  defp client_subject(%{kind: :metadata_field, owner: {:rpc_action, rpc_name, _r}, raw: raw}),
    do: "metadata #{inspect(raw)} of RPC action #{inspect(rpc_name)}"

  defp client_subject(%{kind: kind, owner: owner, path: path, raw: raw})
       when kind in [:type_field, :union_member] do
    what = if kind == :type_field, do: "field", else: "member"
    "#{what} #{path_label(owner, path, raw)}#{owner_context(owner)}"
  end

  defp action_context(action, rpc_names),
    do: " of action #{inspect(action)} (RPC actions #{Enum.join(rpc_names, ", ")})"

  defp owner_context({kind, _name, action, _r, rpc_names})
       when kind in [:action_argument, :action_metadata],
       do: action_context(action, rpc_names)

  defp owner_context({:action_returns, action, _r, rpc_names}),
    do: action_context(action, rpc_names)

  defp owner_context(_owner), do: ""

  # `:settings.colors[].is_on?`: the owner's root name, the path, the raw name.
  defp path_label(owner, path, raw) do
    case root_name(owner) ++ path do
      [] ->
        inspect(raw)

      prefix ->
        joined = Enum.reduce(prefix, "", &join_segment(&2, &1))
        ":" <> join_segment(joined, String.trim_leading(inspect(raw), ":"))
    end
  end

  defp join_segment("", segment), do: segment
  defp join_segment(acc, "[]"), do: acc <> "[]"
  defp join_segment(acc, segment), do: acc <> "." <> segment

  defp root_name({:type, _m}), do: []
  defp root_name({:field, _kind, name, _r}), do: [to_string(name)]
  defp root_name({:calculation_argument, _calc, arg, _r}), do: [to_string(arg)]

  defp root_name({kind, name, _action, _r, _rpc})
       when kind in [:action_argument, :action_metadata], do: [to_string(name)]

  defp root_name({:action_returns, _action, _r, _rpc}), do: ["returns"]
  defp root_name({:route_argument, arg, _route, _source}), do: [to_string(arg)]
  defp root_name({:route_returns, _route, _source}), do: ["returns"]
  defp root_name({:publication, _event, _r, _channel}), do: ["payload"]

  defp provenance(:formatter), do: "formatted"
  defp provenance({:field_names, _r}), do: "field_names"
  defp provenance({:argument_names, _r, _a}), do: "argument_names"
  defp provenance({:metadata_field_names, _rpc}), do: "metadata_field_names"
  defp provenance({:typescript_field_names, _m}), do: "typescript_field_names/0"
  defp provenance({:client_name, _m}), do: "client_name"

  defp client_fix(%{source: {:field_names, _r}}), do: "change the field_names value"
  defp client_fix(%{source: {:argument_names, _r, _a}}), do: "change the argument_names value"

  defp client_fix(%{source: {:metadata_field_names, _rpc}}),
    do: "change the metadata_field_names value"

  defp client_fix(%{source: {:typescript_field_names, m}}),
    do: "change #{inspect(m)}.typescript_field_names/0"

  defp client_fix(%{source: {:client_name, _m}}),
    do: "change the field's client_name in the map entry"

  # A formatter-made name from a raw name that can be used as is: the
  # formatter made it bad. Only argument_names and metadata_field_names
  # take such a raw name as a key.
  defp client_fix(slot) do
    if NameValidation.field_names_key?(slot.raw),
      do: formatted_fix(slot),
      else:
        "the output_field_formatter turns it into #{inspect(slot.name)}: " <>
          "change the formatter#{formatter_mapping(slot.kind)}"
  end

  defp formatter_mapping(:action_argument), do: ", or map it with argument_names"
  defp formatter_mapping(:metadata_field), do: ", or map it with metadata_field_names"
  defp formatter_mapping(_kind), do: ""

  defp formatted_fix(%{kind: :resource_field, exposed?: false} = slot),
    do:
      "add the AshTypescript.Resource extension and a field_names entry, " <>
        "e.g. #{mapping(slot)}, or rename it"

  defp formatted_fix(%{kind: :resource_field} = slot),
    do: "add it to field_names in the resource's typescript block, e.g. #{mapping(slot)}"

  defp formatted_fix(%{kind: :action_argument, owner: {:action, action, _r, _rpc}} = slot),
    do: "add it to argument_names for the action, e.g. #{action}: [#{mapping(slot)}]"

  defp formatted_fix(%{kind: :metadata_field} = slot),
    do: "add it to the RPC action's metadata_field_names, e.g. #{mapping(slot)}"

  defp formatted_fix(%{kind: :type_field, container: {:map_entry, _m}} = slot),
    do: "set client_name on the field, e.g. client_name: #{inspect(suggestion(slot))}"

  defp formatted_fix(%{kind: :type_field, container: {:module, m}} = slot),
    do: "add typescript_field_names/0 to #{inspect(m)}, e.g. #{mapping(slot)}"

  defp formatted_fix(%{kind: :type_field, owner: owner} = slot)
       when elem(owner, 0) in [:route_argument, :route_returns, :publication],
       do: "rename the field, e.g. :#{NameValidation.suggest_name(slot.raw)}"

  defp formatted_fix(%{kind: :type_field}),
    do: "wrap it in an Ash.Type.NewType with typescript_field_names/0"

  defp formatted_fix(slot), do: "rename it, e.g. :#{NameValidation.suggest_name(slot.raw)}"

  # `is_done?: "isDone"`: the raw name as a keyword key, and the suggestion.
  defp mapping(slot), do: "#{Macro.inspect_atom(:key, slot.raw)} #{inspect(suggestion(slot))}"

  defp suggestion(slot),
    do:
      AshRpc.FieldFormatter.format_field_name(
        NameValidation.suggest_name(slot.raw),
        slot.formatter
      )
end
