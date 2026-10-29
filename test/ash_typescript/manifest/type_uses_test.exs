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
end
