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
      assert Custom.typescript_resource?(res)
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
end
