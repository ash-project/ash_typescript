# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.AshTypescript.InstallTest do
  use ExUnit.Case, async: false

  import Igniter.Test

  @moduletag :ash_typescript

  defp scaffolded_config do
    test_project()
    |> Igniter.compose_task("ash_typescript.install", ["--yes"])
    |> then(fn igniter ->
      igniter.rewrite
      |> Rewrite.source!("config/config.exs")
      |> Rewrite.Source.get(:content)
    end)
  end

  @router """
  defmodule TestWeb.Router do
    use TestWeb, :router

    pipeline :browser do
      plug :accepts, ["html"]
    end

    scope "/", TestWeb do
      pipe_through :browser
      get "/", PageController, :home
    end
  end
  """

  @router_with_rpc_routes """
  defmodule TestWeb.Router do
    use TestWeb, :router

    pipeline :browser do
      plug :accepts, ["html"]
    end

    scope "/", TestWeb do
      pipe_through :browser
      get "/", PageController, :home
      post "/rpc/run", AshTypescriptRpcController, :run
      post "/rpc/validate", AshTypescriptRpcController, :validate
    end
  end
  """

  defp installed_router(router \\ @router) do
    test_project(files: %{"lib/test_web/router.ex" => router})
    |> Igniter.compose_task("ash_typescript.install", ["--yes"])
    |> then(fn igniter ->
      igniter.rewrite
      |> Rewrite.source!("lib/test_web/router.ex")
      |> Rewrite.Source.get(:content)
    end)
  end

  defp put_endpoints(run_endpoint, validate_endpoint) do
    original_run = Application.get_env(:ash_typescript, :run_endpoint)
    original_validate = Application.get_env(:ash_typescript, :validate_endpoint)

    set_env(:run_endpoint, run_endpoint)
    set_env(:validate_endpoint, validate_endpoint)

    on_exit(fn ->
      set_env(:run_endpoint, original_run)
      set_env(:validate_endpoint, original_validate)
    end)
  end

  defp set_env(key, nil), do: Application.delete_env(:ash_typescript, key)
  defp set_env(key, value), do: Application.put_env(:ash_typescript, key, value)
  defp count(string, pattern), do: length(String.split(string, pattern)) - 1

  test "scaffolds zod and valibot config symmetrically" do
    config = scaffolded_config()

    assert config =~ "generate_zod_schemas: false"
    assert config =~ ~s(zod_import_path: "zod")
    assert config =~ ~s(zod_schema_suffix: "ZodSchema")

    assert config =~ "generate_valibot_schemas: false"
    assert config =~ ~s(valibot_import_path: "valibot")
    assert config =~ ~s(valibot_schema_suffix: "ValibotSchema")
  end

  test "scaffolds the required manifest module and core options" do
    config = scaffolded_config()

    assert config =~ "manifest: Test.AshTypescriptManifest"
    assert config =~ ~s(output_file: "assets/js/ash_rpc.ts")
    assert config =~ ~s(run_endpoint: "/rpc/run")
    assert config =~ ~s(validate_endpoint: "/rpc/validate")
  end

  test "adds RPC routes with real paths to the router" do
    put_endpoints(nil, nil)

    router = installed_router()

    assert router =~ ~s("/rpc/run", AshTypescriptRpcController, :run)
    assert router =~ ~s("/rpc/validate", AshTypescriptRpcController, :validate)
    refute router =~ ~s("", AshTypescriptRpcController)
  end

  test "falls back to the default for whichever endpoint is not configured" do
    put_endpoints("/api/rpc/run", nil)

    router = installed_router()

    assert router =~ ~s("/api/rpc/run", AshTypescriptRpcController, :run)
    assert router =~ ~s("/rpc/validate", AshTypescriptRpcController, :validate)
    refute router =~ ~s("", AshTypescriptRpcController)
  end

  test "uses configured endpoint paths when adding RPC routes" do
    put_endpoints("/api/rpc/run", "/api/rpc/validate")

    router = installed_router()

    assert router =~ ~s("/api/rpc/run", AshTypescriptRpcController, :run)
    assert router =~ ~s("/api/rpc/validate", AshTypescriptRpcController, :validate)
    refute router =~ ~s("/rpc/run")
    refute router =~ ~s("/rpc/validate")
  end

  test "does not add RPC routes that are already in the router" do
    router = installed_router(@router_with_rpc_routes)

    assert count(router, "AshTypescriptRpcController, :run") == 1
    assert count(router, "AshTypescriptRpcController, :validate") == 1
  end
end
