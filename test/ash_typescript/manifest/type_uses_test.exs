# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.TypeUsesTest do
  # `TypeUses.nodes/1` over the test manifest: the type nodes at every
  # position the manifest reaches, for the compile-time checks.
  use ExUnit.Case, async: true

  alias Ash.Info.Manifest.Resource
  alias Ash.Info.Manifest.Type
  alias AshTypescript.Manifest.Custom
  alias AshTypescript.Manifest.TypeUses

  defmodule PrivateAccept do
    @moduledoc false
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "TypeUsesPrivateAccept"
    end

    attributes do
      uuid_primary_key :id
      attribute :name, :string, public?: true

      attribute :secret_settings, :map,
        public?: false,
        constraints: [fields: [secret_line: [type: :string]]]
    end

    actions do
      defaults [:read]
      create :create, accept: [:name, :secret_settings]
    end
  end

  defmodule PrivateAcceptDomain do
    @moduledoc false
    use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

    typescript_rpc do
      resource PrivateAccept do
        rpc_action :create_private_accept, :create
      end
    end

    resources do
      resource PrivateAccept
    end
  end

  setup_all do
    manifest = AshTypescript.manifest()
    %{manifest: manifest, nodes: TypeUses.nodes(manifest)}
  end

  defp resource(manifest, module), do: Enum.find(manifest.resources, &(&1.module == module))
  defp definition(manifest, module), do: Enum.find(manifest.types, &(&1.module == module))

  defp field_type(manifest, module, name),
    do: Resource.get_field(resource(manifest, module), name).type

  test "resource fields' :unknown nodes", %{manifest: manifest, nodes: nodes} do
    custom_id = field_type(manifest, AshTypescript.Test.Task, :custom_id)

    assert %Type{kind: :unknown, module: AshTypescript.Test.CustomIdentifier} = custom_id
    assert custom_id in nodes

    hierarchy = field_type(manifest, AshTypescript.Test.Todo, :hierarchy)
    strict = field_type(manifest, AshTypescript.Test.Todo, :strict_hierarchy)

    assert %Type{kind: :unknown, module: AshPostgres.Ltree} = hierarchy
    refute Keyword.has_key?(hierarchy.constraints || [], :escape?)
    assert hierarchy in nodes

    assert %Type{kind: :unknown, module: AshPostgres.Ltree} = strict
    assert Keyword.get(strict.constraints, :escape?) == true
    assert strict in nodes
  end

  test "definition fields, descending arrays", %{manifest: manifest, nodes: nodes} do
    theme = definition(manifest, AshTypescript.Test.Theme)
    fields = Map.new(theme.fields, &{&1.name, &1.type})

    assert %Type{kind: :unknown, module: AshTypescript.Test.ExternalCode} = fields.code
    assert fields.code in nodes

    assert %Type{kind: :array, item_type: item} = fields.codes
    assert fields.codes in nodes
    assert %Type{module: AshTypescript.Test.ExternalCode} = item
    assert item in nodes
  end

  test "a :type_ref is returned, not descended", %{manifest: manifest, nodes: nodes} do
    stats = field_type(manifest, AshTypescript.Test.Task, :stats)

    assert %Type{kind: :type_ref, module: AshTypescript.Test.TaskStats} = stats
    assert stats in nodes

    # Its fields come from its definition in `manifest.types`, walked once.
    task_stats = definition(manifest, AshTypescript.Test.TaskStats)
    assert task_stats.fields != []
    assert Enum.count(nodes, &(&1 == task_stats)) == 1
  end

  test "typed controller route inputs and returns", %{manifest: manifest, nodes: nodes} do
    routes =
      manifest
      |> Custom.routes()
      |> Enum.filter(&(&1.source_module == AshTypescript.Test.Session))

    assert routes != []

    for route <- routes, input <- route.inputs, do: assert(input.type in nodes)

    search = Enum.find(routes, &(&1.name == :search))
    tags = Enum.find(search.inputs, &(&1.name == :tags)).type
    assert %Type{kind: :array, item_type: tag} = tags
    assert tag in nodes

    login = Enum.find(routes, &(&1.name == :login))
    assert login.returns in nodes

    user_id = Enum.find(login.returns.fields, &(&1.name == :user_id)).type
    assert %Type{kind: :uuid} = user_id
    assert user_id in nodes
  end

  test "typed channel publication returns", %{manifest: manifest, nodes: nodes} do
    publications = Custom.publications(manifest)
    assert publications != []

    for %{returns: %Type{} = returns} <- publications, do: assert(returns in nodes)

    report =
      Enum.find(
        publications,
        &(&1.resource == AshTypescript.Test.ChannelTracker and &1.event == "tracker_report")
      )

    assert %Type{} = report.returns
    assert report.returns in nodes
  end

  describe "positions/1" do
    setup %{manifest: manifest} do
      %{positions: TypeUses.positions(manifest)}
    end

    test "positions/1 labels a resource attribute's inline map field with the resource",
         %{manifest: manifest, positions: positions} do
      options = field_type(manifest, AshTypescript.Test.Todo, :options)
      assert %Type{kind: :keyword} = options

      owner = {:field, :attribute, :options, AshTypescript.Test.Todo}
      assert {owner, [], options} in positions

      priority = Enum.find(options.fields, &(&1.name == :priority)).type
      assert {owner, ["priority"], priority} in positions
    end

    test "an action shared by several entrypoints is labelled once with every RPC name",
         %{manifest: manifest, positions: positions} do
      entrypoints =
        Enum.filter(
          manifest.entrypoints,
          &(&1.resource == AshTypescript.Test.Todo and &1.action.name == :read)
        )

      rpc_names =
        entrypoints
        |> Enum.map(&(Custom.rpc_action(&1) || Custom.typed_query(&1)).name)
        |> Enum.sort()

      # RPC actions and typed queries alike.
      assert :list_todos in rpc_names
      assert :list_todos_user_page in rpc_names

      inputs = hd(entrypoints).action.inputs
      assert Enum.map(inputs, & &1.name) == [:filter_completed, :priority_filter]

      for input <- inputs do
        matches =
          for {{:action_argument, name, :read, AshTypescript.Test.Todo, names}, [], node} <-
                positions,
              name == input.name,
              do: {names, node}

        assert matches == [{rpc_names, input.type}]
      end
    end

    test "a private accepted attribute is walked as an action input (it is no resource field)" do
      manifest = AshTypescript.Test.InlineManifest.build!(domains: [PrivateAcceptDomain])
      resource = Enum.find(manifest.resources, &(&1.module == PrivateAccept))
      refute Map.has_key?(resource.fields, :secret_settings)

      assert Enum.any?(
               TypeUses.positions(manifest),
               &match?(
                 {{:action_argument, :secret_settings, :create, PrivateAccept,
                   [:create_private_accept]}, ["secret_line"], _},
                 &1
               )
             )
    end

    test "an accepted attribute isn't a separate root", %{
      manifest: manifest,
      positions: positions
    } do
      create =
        Enum.find(manifest.entrypoints, &match?(%{name: :create_todo}, Custom.rpc_action(&1)))

      assert Enum.any?(create.action.inputs, &(&1.name == :options))
      options = field_type(manifest, AshTypescript.Test.Todo, :options)

      assert [{{:field, :attribute, :options, AshTypescript.Test.Todo}, [], ^options}] =
               Enum.filter(positions, fn {_owner, _path, node} -> node == options end)

      refute Enum.any?(
               positions,
               &match?(
                 {{:action_argument, :options, :create, AshTypescript.Test.Todo, _}, _, _},
                 &1
               )
             )
    end

    test "a :type_ref is yielded but not descended", %{manifest: manifest, positions: positions} do
      stats = field_type(manifest, AshTypescript.Test.Task, :stats)
      assert %Type{kind: :type_ref, module: AshTypescript.Test.TaskStats} = stats

      field_owner = {:field, :attribute, :stats, AshTypescript.Test.Task}
      assert {field_owner, [], stats} in positions
      refute Enum.any?(positions, &match?({^field_owner, [_ | _], _}, &1))

      task_stats = definition(manifest, AshTypescript.Test.TaskStats)
      type_owner = {:type, AshTypescript.Test.TaskStats}
      assert {type_owner, [], task_stats} in positions

      for field <- task_stats.fields,
          do: assert({type_owner, [to_string(field.name)], field.type} in positions)
    end

    test "every unique node of the old walk is a position", %{manifest: manifest, nodes: nodes} do
      assert MapSet.new(old_nodes(manifest)) == MapSet.new(nodes)
    end

    test "no inline node is positioned twice", %{positions: positions} do
      pairs = Enum.map(positions, fn {owner, path, _node} -> {owner, path} end)
      assert pairs -- Enum.uniq(pairs) == []
    end
  end

  # The walk `nodes/1` did before `positions/1`, kept to show the node set is unchanged.
  defp old_nodes(manifest) do
    roots =
      Enum.flat_map(manifest.resources, &old_resource_roots/1) ++
        Enum.flat_map(manifest.entrypoints, fn %{action: action} ->
          Enum.map(action.inputs || [], & &1.type) ++
            Enum.map(action.metadata || [], & &1.type) ++ [action.returns]
        end) ++
        Enum.flat_map(manifest.types, fn
          %Type{kind: :embedded_resource, resource: %Resource{} = r} = t ->
            [t | old_resource_roots(r)]

          type ->
            [type]
        end) ++
        Enum.flat_map(Custom.routes(manifest), fn route ->
          Enum.map(route.inputs, & &1.type) ++ [route.returns]
        end) ++
        Enum.map(Custom.publications(manifest), & &1.returns)

    roots |> Enum.reject(&is_nil/1) |> Enum.flat_map(&old_walk/1)
  end

  defp old_resource_roots(resource) do
    resource
    |> Resource.all_fields()
    |> Enum.flat_map(fn field ->
      [field.type | Enum.map(Map.get(field, :arguments) || [], & &1.type)]
    end)
  end

  defp old_walk(%Type{} = type), do: [type | Enum.flat_map(old_children(type), &old_walk/1)]
  defp old_walk(_other), do: []

  defp old_children(%Type{kind: :array, item_type: item}), do: [item]

  defp old_children(%Type{kind: :union, members: members}) when is_list(members),
    do: Enum.map(members, & &1.type)

  defp old_children(%Type{kind: kind, fields: fields})
       when kind in [:map, :keyword, :tuple, :struct] and is_list(fields),
       do: Enum.map(fields, & &1.type)

  defp old_children(%Type{kind: :tuple, element_types: elements}) when is_list(elements),
    do: Enum.map(elements, & &1.type)

  defp old_children(_type), do: []
end
