# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.TypedController.CodegenEnforcementTest do
  @moduledoc """
  Codegen-time behavior for typed controllers that depends on which modules are
  in the manifest: verifier failures (which Spark only reports as compile
  warnings) must fail codegen, and named types referenced only by routes, which
  the manifest stores alongside the routes, must generate.
  """
  use ExUnit.Case, async: false

  alias AshTypescript.Test.CodegenTestHelper

  @moduletag :ash_typescript

  setup_all do
    # Defined at runtime under a stderr capture: compiling it emits the Spark
    # verifier warning this module is about.
    ExUnit.CaptureIO.capture_io(:stderr, fn ->
      defmodule InvalidFieldNames do
        use AshTypescript.TypedController

        typed_controller do
          module_name AshTypescript.TypedController.CodegenEnforcementTest.InvalidFieldNamesController

          get :status do
            run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
            returns :map
            constraints fields: [done?: [type: :boolean]]
          end
        end
      end
    end)

    :ok
  end

  defmodule RouteOnlyTypes do
    use AshTypescript.TypedController

    typed_controller do
      module_name AshTypescript.TypedController.CodegenEnforcementTest.RouteOnlyTypesController

      post :save_settings do
        run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
        argument :settings, AshTypescript.Test.RouteSettings, allow_nil?: false
        argument :summary, AshTypescript.Test.RouteResultSummary
        returns AshTypescript.Test.RouteSettings
      end
    end
  end

  describe "verifier enforcement" do
    test "VerifierChecker reports typed controller verifier failures" do
      assert {:error, message} =
               AshTypescript.VerifierChecker.check_all_verifiers([__MODULE__.InvalidFieldNames])

      assert message =~ "Verifier: AshTypescript.TypedController.Verifiers.VerifyTypedController"
      assert message =~ "route :status, returns field `done?`"
    end

    test "VerifierChecker accepts valid typed controllers and channels" do
      modules =
        Enum.map(
          AshTypescript.TypedController.Codegen.RouteConfigCollector.manifest_routes_config(),
          &elem(&1, 0)
        ) ++ Enum.map(AshTypescript.Codegen.Orchestrator.channel_entries(), &elem(&1, 0))

      assert :ok = AshTypescript.VerifierChecker.check_all_verifiers(modules)
    end

    # Building the manifest succeeds (decorating `done?` is fine); the
    # verifier run during codegen is what fails.
    test "codegen fails for a manifest typed controller with invalid names" do
      manifest =
        AshTypescript.Test.InlineManifest.build!(
          typed_controllers: [__MODULE__.InvalidFieldNames],
          typed_channels: []
        )

      assert {:error, message} =
               CodegenTestHelper.generate_files(:ash_typescript, manifest: manifest)

      assert message =~ "route :status, returns field `done?`"
    end
  end

  describe "named types referenced only by routes" do
    setup do
      manifest =
        AshTypescript.Test.InlineManifest.build!(
          typed_controllers: [RouteOnlyTypes],
          typed_channels: [],
          body: AshTypescript.Test.InlineManifest.app_custom_types()
        )

      assert {:ok, files} = CodegenTestHelper.generate_files(:ash_typescript, manifest: manifest)
      %{routes: CodegenTestHelper.routes_content(files), files: files}
    end

    test "argument and result types are expanded inline, honoring field name mappings", %{
      routes: routes
    } do
      assert routes =~
               "export type SaveSettingsInput = {\n" <>
                 "  settings: {enabled: boolean, level1?: number | null};\n"

      assert routes =~
               "export type SaveSettingsResult = {enabled: boolean, level1: number | null};"

      assert routes =~ "summary?: {totalCount: number, "
    end

    test "validation schemas are generated for them", %{files: files} do
      zod = CodegenTestHelper.zod_content(files) <> CodegenTestHelper.routes_content(files)
      assert zod =~ "saveSettingsZodSchema"
      assert zod =~ "enabled: z.boolean()"
      assert zod =~ "level1:"
    end
  end
end
