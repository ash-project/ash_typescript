# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.TypedRouteCollectorTest.Inner do
  @moduledoc false
  use Ash.Type.NewType, subtype_of: :map, constraints: [fields: [hit_count: [type: :integer]]]
end

defmodule AshTypescript.Manifest.TypedRouteCollectorTest.Outer do
  @moduledoc false
  use Ash.Type.NewType,
    subtype_of: :map,
    constraints: [fields: [inner: [type: AshTypescript.Manifest.TypedRouteCollectorTest.Inner]]]
end

defmodule AshTypescript.Manifest.TypedRouteCollectorTest do
  use ExUnit.Case, async: true

  alias Ash.Info.Manifest.Generator.TypeResolver
  alias AshTypescript.Manifest.{Publication, Route, RouteArgument, TypedRouteCollector}
  alias __MODULE__.{Inner, Outer}

  @moduletag :ash_typescript

  describe "collect/2" do
    test "reads every route of a typed controller, undecorated" do
      {routes, []} = TypedRouteCollector.collect([AshTypescript.Test.Session], [])

      login = Enum.find(routes, &(&1.name == :login))

      assert %Route{
               source_module: AshTypescript.Test.Session,
               controller_module: controller,
               client_input_names: %{}
             } = login

      assert controller ==
               AshTypescript.TypedController.Info.typed_controller_module_name!(
                 AshTypescript.Test.Session
               )

      assert [
               %RouteArgument{name: :code, allow_nil?: false, client_name: nil},
               %RouteArgument{name: :remember_me, allow_nil?: true}
             ] = login.inputs

      assert %Ash.Info.Manifest.Type{kind: :map} = login.returns
      refute Map.has_key?(login.returns.custom, :ash_rpc)

      create_task = Enum.find(routes, &(&1.name == :create_task))
      metadata = Enum.find(create_task.inputs, &(&1.name == :metadata))
      assert metadata.type.kind == :map
    end

    test "reads declared events that have a returns type" do
      {[], pubs} = TypedRouteCollector.collect([], [AshTypescript.Test.OrgChannel])

      assert Enum.map(pubs, & &1.event) |> Enum.sort() ==
               ["item_created", "item_deleted", "item_updated"]

      assert Enum.all?(
               pubs,
               &match?(
                 %Publication{
                   channel_module: AshTypescript.Test.OrgChannel,
                   resource: AshTypescript.Test.ChannelItem,
                   returns: %Ash.Info.Manifest.Type{}
                 },
                 &1
               )
             )
    end

    test "skips modules that don't use the DSLs" do
      assert TypedRouteCollector.collect([String], [String]) == {[], []}
    end
  end

  describe "named_modules/1" do
    test "named types, walking into definitions and skipping resources" do
      types = [
        TypeResolver.resolve(Outer, []),
        TypeResolver.resolve({:array, AshTypescript.Test.TaskMetadata}, []),
        TypeResolver.resolve(Ash.Type.Struct, instance_of: AshTypescript.Test.User),
        TypeResolver.resolve(Ash.Type.Union, types: [a: [type: :string]]),
        nil
      ]

      assert TypedRouteCollector.named_modules(types) == [Inner, Outer]
    end
  end
end
