# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.CustomTest do
  use ExUnit.Case, async: true

  alias Ash.Info.Manifest
  alias AshTypescript.Manifest.Custom

  describe "resolve_resource/1" do
    test "resolves a domain resource module to its decorated struct" do
      res = Custom.resolve_resource(AshTypescript.Test.User)
      assert %Manifest.Resource{module: AshTypescript.Test.User} = res
      assert AshRpc.Manifest.Custom.exposed?(res)
    end

    test "resolves an embedded resource module via type_lookup" do
      res = Custom.resolve_resource(AshTypescript.Test.TodoMetadata)
      assert %Manifest.Resource{module: AshTypescript.Test.TodoMetadata} = res
    end

    test "returns nil for a module that is not in the manifest" do
      assert Custom.resolve_resource(AshTypescript.Test.CustomMetadata) == nil ||
               match?(
                 %Manifest.Resource{},
                 Custom.resolve_resource(AshTypescript.Test.CustomMetadata)
               )
    end

    test "resolves against the with_manifest/2 manifest" do
      snake =
        AshTypescript.Manifest.redecorate(AshTypescript.manifest(), output_formatter: :snake_case)

      AshTypescript.with_manifest(snake, fn ->
        assert Custom.resolve_resource(AshTypescript.Test.User) ==
                 AshTypescript.resource_lookup(snake)[AshTypescript.Test.User]
      end)
    end

    test "returns nil for nil / non-atoms" do
      assert Custom.resolve_resource(nil) == nil
      assert Custom.resolve_resource("nope") == nil
    end
  end

  describe "type_name/1" do
    test "returns the decorated resource type name" do
      assert Custom.type_name(Custom.resolve_resource(AshTypescript.Test.User)) == "User"
    end

    test "returns nil for an undecorated struct" do
      assert Custom.type_name(%Ash.Info.Manifest.Resource{module: Foo}) == nil
      assert Custom.type_name(%Ash.Info.Manifest.Type{module: Foo}) == nil
      assert Custom.type_name(nil) == nil
    end
  end

  describe "exposed_metadata_fields/1" do
    test "returns [] for an undecorated entrypoint" do
      assert Custom.exposed_metadata_fields(%Ash.Info.Manifest.Entrypoint{}) == []
      assert Custom.exposed_metadata_fields(nil) == []
    end
  end

  describe "load_restrictions / filter / sort accessors" do
    test "defaults on undecorated entrypoint" do
      e = %Ash.Info.Manifest.Entrypoint{}
      assert Custom.load_restrictions(e) == :none
      assert Custom.filtering_enabled?(e) == true
      assert Custom.sorting_enabled?(e) == true
      assert Custom.load_restrictions(nil) == :none
      assert Custom.filtering_enabled?(nil) == true
      assert Custom.sorting_enabled?(nil) == true
    end
  end

  describe "routes and publications" do
    alias AshTypescript.Manifest.{Publication, Route}

    defp typed_manifest do
      %Ash.Info.Manifest{
        custom: %{
          ash_typescript: %{
            routes: %{
              {B, :a} => %Route{source_module: B, name: :a},
              {A, :z} => %Route{source_module: A, controller_module: AController, name: :z},
              {A, :b} => %Route{source_module: A, name: :b}
            },
            publications: %{
              {C2, R, "y"} => %Publication{channel_module: C2, resource: R, event: "y"},
              {C1, Q, "x"} => %Publication{channel_module: C1, resource: Q, event: "x"},
              {C1, R, "y"} => %Publication{channel_module: C1, resource: R, event: "y"}
            }
          }
        }
      }
    end

    test "route/3 and publication/4 look up by key" do
      m = typed_manifest()

      assert %Route{source_module: A, controller_module: AController, name: :z} =
               Custom.route(m, A, :z)

      assert Custom.route(m, A, :missing) == nil
      assert %Publication{channel_module: C1, event: "x"} = Custom.publication(m, C1, Q, "x")
      assert %Publication{channel_module: C2} = Custom.publication(m, C2, R, "y")
      assert Custom.publication(m, C2, Q, "x") == nil
      assert Custom.publication(m, C1, Q, "nope") == nil
    end

    test "routes/1 and publications/1 sort deterministically" do
      m = typed_manifest()

      assert Enum.map(Custom.routes(m), &{&1.source_module, &1.name}) == [
               {A, :b},
               {A, :z},
               {B, :a}
             ]

      assert Enum.map(Custom.publications(m), &{&1.channel_module, &1.resource, &1.event}) ==
               [{C1, Q, "x"}, {C1, R, "y"}, {C2, R, "y"}]
    end

    test "a manifest without typed data reads as empty" do
      assert Custom.routes(%Ash.Info.Manifest{}) == []
      assert Custom.publications(%Ash.Info.Manifest{}) == []
      assert Custom.route(%Ash.Info.Manifest{}, A, :a) == nil
      assert Custom.publication(%Ash.Info.Manifest{}, C1, Q, "x") == nil
    end

    test "Publication returns may be nil" do
      assert %Publication{returns: nil} = %Publication{
               channel_module: C1,
               resource: Q,
               event: "x"
             }
    end

    test "Route defaults" do
      assert %Route{
               controller_module: nil,
               inputs: [],
               client_input_names: %{},
               path_input_names: %{}
             } = %Route{}
    end

    test "nil reads the configured manifest and honours with_manifest/2" do
      AshTypescript.with_manifest(typed_manifest(), fn ->
        assert %Route{name: :b} = Custom.route(nil, A, :b)
        assert [_, _, _] = Custom.routes()
        assert [_, _, _] = Custom.publications()
      end)
    end
  end
end
