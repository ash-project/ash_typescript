# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.UnlistedTypedModulesWarningTest.UnlistedSession do
  @moduledoc false
  use AshTypescript.TypedController

  typed_controller do
    module_name AshTypescript.Codegen.UnlistedTypedModulesWarningTest.UnlistedController

    get :ping do
      run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
    end
  end
end

defmodule AshTypescript.Codegen.UnlistedTypedModulesWarningTest.EmptySession do
  @moduledoc false
  use AshTypescript.TypedController

  typed_controller do
    module_name AshTypescript.Codegen.UnlistedTypedModulesWarningTest.EmptyController
  end
end

defmodule AshTypescript.Codegen.UnlistedTypedModulesWarningTest do
  # Mutates the global `warn_on_unlisted_typed_modules` flag and captures
  # stderr around a full codegen run.
  use ExUnit.Case, async: false

  alias AshTypescript.Codegen.{Orchestrator, TypeDiscovery}
  alias AshTypescript.Test.InlineManifest
  alias AshTypescript.Test.TypedChannel.StaticTopicChannel
  alias __MODULE__.{EmptySession, UnlistedSession}

  @header "Found typed controllers or typed channels not listed in the manifest"

  setup do
    AshTypescript.Test.TestHelpers.restore_application_env_on_exit([
      :warn_on_unlisted_typed_modules
    ])
  end

  defp warning(modules, manifest),
    do: TypeDiscovery.build_unlisted_typed_modules_warning(:ash_typescript, modules, manifest)

  describe "build_unlisted_typed_modules_warning/3" do
    test "names an unlisted typed controller and points at typed_controllers:" do
      manifest = InlineManifest.build!(typed_controllers: [AshTypescript.Test.Session])

      message = warning([AshTypescript.Test.Session, UnlistedSession], manifest)

      assert message =~ @header
      assert message =~ "• #{inspect(UnlistedSession)} (typed controller)"
      assert message =~ "typed_controllers: [#{inspect(UnlistedSession)}]"
      refute message =~ "typed_channels: ["
      refute message =~ "• AshTypescript.Test.Session "
    end

    test "names an unlisted typed channel and points at typed_channels:" do
      manifest = InlineManifest.build!(typed_channels: [AshTypescript.Test.OrgChannel])

      message = warning([AshTypescript.Test.OrgChannel, StaticTopicChannel], manifest)

      assert message =~ @header
      assert message =~ "• #{inspect(StaticTopicChannel)} (typed channel)"
      assert message =~ "typed_channels: [#{inspect(StaticTopicChannel)}]"
      refute message =~ "typed_controllers: ["
      refute message =~ "• AshTypescript.Test.OrgChannel "
    end

    test "lists unlisted controllers and channels in one block" do
      manifest = InlineManifest.build!(typed_controllers: [], typed_channels: [])

      message = warning([UnlistedSession, StaticTopicChannel], manifest)

      assert length(String.split(message, @header)) == 2
      assert message =~ "typed_controllers: [#{inspect(UnlistedSession)}]"
      assert message =~ "typed_channels: [#{inspect(StaticTopicChannel)}]"
    end

    test "returns nil when every typed module is listed" do
      manifest =
        InlineManifest.build!(
          typed_controllers: [AshTypescript.Test.Session],
          typed_channels: [StaticTopicChannel]
        )

      assert warning([AshTypescript.Test.Session, StaticTopicChannel], manifest) == nil
    end

    test "ignores modules without the DSL and typed modules that declare nothing" do
      manifest = InlineManifest.build!(typed_controllers: [], typed_channels: [])

      assert warning([AshTypescript.Test.Todo, String, EmptySession], manifest) == nil
    end

    test "reads the listed set from the with_manifest/2 override" do
      manifest = InlineManifest.build!(typed_controllers: [UnlistedSession])

      assert AshTypescript.with_manifest(manifest, fn ->
               warning([UnlistedSession], nil)
             end) == nil

      assert warning([UnlistedSession], nil) =~ inspect(UnlistedSession)
    end

    test "returns nil when warn_on_unlisted_typed_modules is false" do
      Application.put_env(:ash_typescript, :warn_on_unlisted_typed_modules, false)
      manifest = InlineManifest.build!(typed_controllers: [], typed_channels: [])

      assert warning([UnlistedSession, StaticTopicChannel], manifest) == nil
    end
  end

  describe "Orchestrator.generate/2" do
    test "warns on stderr about the app's unlisted typed modules" do
      {{:ok, _files}, stderr} =
        ExUnit.CaptureIO.with_io(:stderr, fn -> Orchestrator.generate(:ash_typescript, []) end)

      assert stderr =~ @header
      assert stderr =~ "• #{inspect(StaticTopicChannel)} (typed channel)"
      assert stderr =~ "• AshTypescript.Test.PublicationFixtures.FeedChannel (typed channel)"
      refute stderr =~ "• AshTypescript.Test.Session "
      refute stderr =~ "• AshTypescript.Test.OrgChannel "
    end

    test "stays silent when warn_on_unlisted_typed_modules is false" do
      Application.put_env(:ash_typescript, :warn_on_unlisted_typed_modules, false)

      {{:ok, _files}, stderr} =
        ExUnit.CaptureIO.with_io(:stderr, fn -> Orchestrator.generate(:ash_typescript, []) end)

      refute stderr =~ @header
    end
  end
end
