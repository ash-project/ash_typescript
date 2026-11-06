# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.TypedController.RouteJsdocTest do
  @moduledoc """
  A route's `description` and `deprecated` options in the JSDoc of its path
  helper and its fetch function, and a router module that isn't a Phoenix
  router, which leaves the routes without paths as no router does.
  """
  use ExUnit.Case, async: false

  alias AshTypescript.Test.{CodegenTestHelper, InlineManifest}
  alias AshTypescript.TypedController.Codegen
  alias AshTypescript.TypedController.Codegen.RouteConfigCollector

  defmodule Documented do
    @moduledoc false
    use AshTypescript.TypedController

    typed_controller do
      module_name AshTypescript.TypedController.RouteJsdocTest.DocumentedController

      get :old_page do
        description "The old page"
        deprecated true
        run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
      end

      post :old_save do
        description "Saves the old way"
        deprecated "Use newSave"
        run fn conn, _params -> Plug.Conn.send_resp(conn, 200, "OK") end
        argument :name, :string
      end
    end
  end

  setup_all do
    manifest = InlineManifest.build!(typed_controllers: [Documented], typed_channels: [])

    typescript =
      AshTypescript.with_manifest(manifest, fn ->
        CodegenTestHelper.generate_controller_content(router: nil)
      end)

    %{manifest: manifest, typescript: typescript}
  end

  test "a path helper's JSDoc has the route's description and the default deprecation", %{
    typescript: typescript
  } do
    assert typescript =~
             "/**\n * The old page\n * @deprecated This route is deprecated\n */\nexport function oldPagePath("
  end

  test "a fetch function's JSDoc has the route's description and its deprecation message", %{
    typescript: typescript
  } do
    assert typescript =~
             "/**\n * Saves the old way\n * @deprecated Use newSave\n */\nexport async function oldSave("
  end

  test "a router module without routes resolves like no router", %{manifest: manifest} do
    AshTypescript.with_manifest(manifest, fn ->
      config = RouteConfigCollector.manifest_routes_config()

      assert [_ | _] = without_router = Codegen.resolve_route_infos(nil, config)
      assert Codegen.resolve_route_infos(String, config) == without_router
    end)
  end
end
