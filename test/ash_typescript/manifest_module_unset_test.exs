# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.ManifestModuleUnsetTest do
  # Changes the app env, so it runs alone.
  use ExUnit.Case, async: false

  alias AshTypescript.Codegen.Helpers
  alias AshTypescript.Manifest.Custom
  alias AshTypescript.Test.InlineManifest

  describe "decoration" do
    setup do
      AshTypescript.Test.TestHelpers.restore_application_env_on_exit([:manifest])
      Application.delete_env(:ash_typescript, :manifest)
    end

    test "decorating needs no configured manifest module" do
      # Options no other test uses, so the module compiles here, with no
      # configured manifest module.
      manifest =
        InlineManifest.build!(
          domains: [AshTypescript.Test.Domain],
          typed_channels: [],
          typed_controllers: []
        )

      todo = Enum.find(manifest.resources, &(&1.module == AshTypescript.Test.Todo))
      assert Custom.type_name(todo) == "Todo"
    end

    test "manifest_module/0 raises when none is configured" do
      error = assert_raise RuntimeError, fn -> AshTypescript.manifest_module() end
      assert error.message =~ "No `:manifest` module configured for AshTypescript."
      assert error.message =~ "config :ash_typescript, manifest: MyApp.AshTypescriptManifest"
    end

    test "manifest/0 raises the same error" do
      assert_raise RuntimeError, ~r/No `:manifest` module configured/, fn ->
        AshTypescript.manifest()
      end
    end
  end

  test "decorated type_name follows the resource's typescript type_name" do
    exposed =
      AshTypescript.manifest().resources
      |> Enum.filter(&AshRpc.Manifest.Custom.exposed?/1)

    assert exposed != []

    for resource <- exposed do
      assert Custom.type_name(resource) == Helpers.derive_resource_type_name(resource.module),
             "type_name of #{inspect(resource.module)}"
    end
  end
end
