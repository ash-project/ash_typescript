# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.RoutesTest do
  use ExUnit.Case, async: true

  alias AshTypescript.Test.InlineManifest

  @moduletag :ash_typescript

  describe "scoped typed modules" do
    test "typed_controllers/typed_channels options are persisted on the manifest module" do
      opts = [
        typed_controllers: [AshTypescript.Test.Session],
        typed_channels: [AshTypescript.Test.OrgChannel]
      ]

      assert %Ash.Info.Manifest{} = InlineManifest.build!(opts)
      module = InlineManifest.module_for(opts)

      assert Spark.Dsl.Extension.get_persisted(module, :typed_controllers) ==
               [AshTypescript.Test.Session]

      assert Spark.Dsl.Extension.get_persisted(module, :typed_channels) ==
               [AshTypescript.Test.OrgChannel]
    end

    test "build!/1 reuses the compiled module for the same options" do
      opts = [typed_controllers: [AshTypescript.Test.Session], typed_channels: []]
      assert InlineManifest.build!(opts) == InlineManifest.build!(opts)
      assert InlineManifest.module_for(opts) != InlineManifest.module_for(typed_channels: [])
    end

    test "options default to []" do
      opts = [domains: [AshTypescript.Test.SecondDomain]]
      InlineManifest.build!(opts)
      module = InlineManifest.module_for(opts)

      assert Spark.Dsl.Extension.get_persisted(module, :typed_controllers) == []
      assert Spark.Dsl.Extension.get_persisted(module, :typed_channels) == []
    end

    test "the test manifest declares the fixture lists on the module" do
      assert Spark.Dsl.Extension.get_persisted(AshTypescript.Test.Manifest, :typed_controllers) ==
               [AshTypescript.Test.Session]

      assert Spark.Dsl.Extension.get_persisted(AshTypescript.Test.Manifest, :typed_channels) == [
               AshTypescript.Test.OrgChannel,
               AshTypescript.Test.ContentFeedChannel,
               AshTypescript.Test.ModerationChannel,
               AshTypescript.Test.FullActivityChannel,
               AshTypescript.Test.TrackerChannel
             ]
    end

    test "the typed config keys are gone from the app env" do
      assert Application.get_env(:ash_typescript, :typed_controllers) == nil
      assert Application.get_env(:ash_typescript, :typed_channels) == nil
    end
  end
end
