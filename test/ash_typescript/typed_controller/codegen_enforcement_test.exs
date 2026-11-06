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

      defmodule DuplicateRoutes do
        use AshTypescript.TypedController

        typed_controller do
          module_name AshTypescript.TypedController.CodegenEnforcementTest.DuplicateRoutesController

          get :status do
            run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
          end

          post :status do
            run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
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

  defmodule MapQueryArgument do
    use AshTypescript.TypedController

    typed_controller do
      module_name AshTypescript.TypedController.CodegenEnforcementTest.MapQueryArgumentController

      get :search do
        run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
        argument :tags, {:array, :string}

        argument :range, :map,
          constraints: [fields: [from: [type: :integer], to: [type: :integer]]]
      end

      post :save_range do
        run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end

        argument :range, :map,
          constraints: [fields: [from: [type: :integer], to: [type: :integer]]]
      end
    end
  end

  defmodule MapPathParam do
    use AshTypescript.TypedController

    typed_controller do
      module_name AshTypescript.TypedController.CodegenEnforcementTest.MapPathParamController

      get :by_range do
        run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end

        argument :range, :map,
          allow_nil?: false,
          constraints: [fields: [from: [type: :integer], to: [type: :integer]]]
      end
    end
  end

  defmodule MapPathParamRouter do
    use Phoenix.Router

    get(
      "/ranges/:range",
      AshTypescript.TypedController.CodegenEnforcementTest.MapPathParamController,
      :by_range
    )
  end

  defmodule MapArrayQueryArgument do
    use AshTypescript.TypedController

    typed_controller do
      module_name AshTypescript.TypedController.CodegenEnforcementTest.MapArrayQueryArgumentController

      get :by_points do
        run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end

        argument :points, {:array, :map}, constraints: [items: [fields: [x: [type: :integer]]]]
      end
    end
  end

  defmodule StructQueryArgument do
    use AshTypescript.TypedController

    typed_controller do
      module_name AshTypescript.TypedController.CodegenEnforcementTest.StructQueryArgumentController

      get :by_stats do
        run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
        argument :stats, AshTypescript.Test.TaskStats
      end
    end
  end

  defmodule NewTypeQueryArgument do
    use AshTypescript.TypedController

    typed_controller do
      module_name AshTypescript.TypedController.CodegenEnforcementTest.NewTypeQueryArgumentController

      get :by_settings do
        run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
        argument :settings, AshTypescript.Test.RouteSettings
      end
    end
  end

  defmodule CustomTypeQueryArgument do
    use AshTypescript.TypedController

    typed_controller do
      module_name AshTypescript.TypedController.CodegenEnforcementTest.CustomTypeQueryArgumentController

      get :near do
        run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
        argument :point, AshTypescript.Test.GeoPoint
      end
    end
  end

  defmodule ScalarArrayQueryArgument do
    use AshTypescript.TypedController

    typed_controller do
      module_name AshTypescript.TypedController.CodegenEnforcementTest.ScalarArrayQueryArgumentController

      get :tagged do
        run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
        argument :tags, {:array, :string}
      end
    end
  end

  defp url_error(controller, router \\ nil) do
    manifest =
      AshTypescript.Test.InlineManifest.build!(
        typed_controllers: [controller],
        typed_channels: []
      )

    error =
      assert_raise RuntimeError, fn ->
        AshTypescript.with_manifest(manifest, fn ->
          CodegenTestHelper.generate_controller_content(router: router)
        end)
      end

    Exception.message(error)
  end

  defp url_sentence(route, args),
    do:
      "Route :#{route} sends the arguments #{args} in its URL, but their types are not " <>
        "scalars, so they can't be written to a path segment or query string.\n"

  describe "URL argument types" do
    test "a path param of map type is not URL-safe" do
      assert url_error(MapPathParam, MapPathParamRouter) =~ url_sentence(:by_range, ":range")
    end

    test "a GET query argument that is an array of maps is not URL-safe" do
      assert url_error(MapArrayQueryArgument) =~ url_sentence(:by_points, ":points")
    end

    test "a GET query argument of a struct type is not URL-safe" do
      assert url_error(StructQueryArgument) =~ url_sentence(:by_stats, ":stats")
    end

    test "a GET query argument of a NewType over a map is not URL-safe" do
      assert url_error(NewTypeQueryArgument) =~ url_sentence(:by_settings, ":settings")
    end

    test "a GET query argument of a declared map custom type is not URL-safe" do
      assert url_error(CustomTypeQueryArgument) =~ url_sentence(:near, ":point")
    end

    test "a GET query argument that is an array of scalars generates" do
      manifest =
        AshTypescript.Test.InlineManifest.build!(
          typed_controllers: [ScalarArrayQueryArgument],
          typed_channels: []
        )

      typescript =
        AshTypescript.with_manifest(manifest, fn ->
          CodegenTestHelper.generate_controller_content(router: nil)
        end)

      assert typescript =~ "export function taggedPath(query?: { tags?: Array<string> | null })"
    end

    test "codegen fails for a GET route with a map query argument" do
      manifest =
        AshTypescript.Test.InlineManifest.build!(
          typed_controllers: [MapQueryArgument],
          typed_channels: []
        )

      error =
        assert_raise RuntimeError, fn ->
          CodegenTestHelper.generate_files(:ash_typescript, manifest: manifest)
        end

      message = Exception.message(error)
      assert message =~ "Route :search sends the arguments :range in its URL"
      refute message =~ ":tags"
      refute message =~ ":save_range"
    end
  end

  describe "verifier enforcement" do
    test "VerifierChecker reports typed controller verifier failures" do
      assert {:error, message} =
               AshTypescript.VerifierChecker.check_all_verifiers([__MODULE__.DuplicateRoutes])

      assert message =~ "Verifier: AshTypescript.TypedController.Verifiers.VerifyTypedController"
      assert message =~ "Duplicate route names found: :status"
    end

    test "VerifierChecker accepts valid typed controllers and channels" do
      modules =
        Enum.map(
          AshTypescript.TypedController.Codegen.RouteConfigCollector.manifest_routes_config(),
          &elem(&1, 0)
        ) ++ Enum.map(AshTypescript.Codegen.Orchestrator.channel_entries(), &elem(&1, 0))

      assert :ok = AshTypescript.VerifierChecker.check_all_verifiers(modules)
    end

    # The manifest compile reports `done?`, so codegen never runs on it.
    test "codegen fails for a manifest typed controller with invalid names" do
      %{message: message} =
        assert_raise RuntimeError, fn ->
          AshTypescript.Test.InlineManifest.build!(
            typed_controllers: [__MODULE__.InvalidFieldNames],
            typed_channels: []
          )
        end

      assert message =~ "Invalid generated names found."

      assert message =~
               "  Route :status of #{inspect(__MODULE__.InvalidFieldNames)}:\n" <>
                 ~s{    - field :returns.done? → "done?" (formatted), not an identifier: } <>
                 "rename the field, e.g. :done\n"
    end
  end

  describe "named types referenced only by routes" do
    setup do
      manifest =
        AshTypescript.Test.InlineManifest.build!(
          typed_controllers: [RouteOnlyTypes],
          typed_channels: []
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
