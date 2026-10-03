# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.TypedController.CodegenEnforcementTest do
  @moduledoc """
  Codegen-time behavior for typed controllers that depends on which modules are
  configured: verifier failures (which Spark only reports as compile warnings)
  must fail codegen, and named types referenced only by routes — absent from
  the manifest — must still generate.
  """
  use ExUnit.Case, async: false

  alias AshTypescript.Test.CodegenTestHelper

  @moduletag :ash_typescript

  setup_all do
    AshTypescript.Test.TestHelpers.restore_application_env_on_exit([:typed_controllers])

    # Defined at runtime under a stderr capture: compiling it emits the Spark
    # verifier warning this module is about.
    ExUnit.CaptureIO.capture_io(:stderr, fn ->
      defmodule InvalidFieldNames do
        use AshTypescript.TypedController

        typed_controller do
          module_name(
            AshTypescript.TypedController.CodegenEnforcementTest.InvalidFieldNamesController
          )

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

  defp with_typed_controllers(modules) do
    previous = Application.get_env(:ash_typescript, :typed_controllers)
    Application.put_env(:ash_typescript, :typed_controllers, modules)
    on_exit(fn -> Application.put_env(:ash_typescript, :typed_controllers, previous) end)
  end

  defmodule RouteOnlyTypes do
    use AshTypescript.TypedController

    typed_controller do
      module_name(AshTypescript.TypedController.CodegenEnforcementTest.RouteOnlyTypesController)

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
      assert :ok =
               AshTypescript.VerifierChecker.check_all_verifiers(
                 AshTypescript.typed_controllers() ++ AshTypescript.typed_channels()
               )
    end

    test "codegen fails for a configured typed controller with invalid names" do
      with_typed_controllers([__MODULE__.InvalidFieldNames])

      assert {:error, message} = CodegenTestHelper.generate_files()
      assert message =~ "route :status, returns field `done?`"
    end
  end

  describe "named types referenced only by routes" do
    setup do
      with_typed_controllers([RouteOnlyTypes])
      assert {:ok, files} = CodegenTestHelper.generate_files()
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
