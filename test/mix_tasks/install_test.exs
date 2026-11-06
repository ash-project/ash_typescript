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

  test "the installer writes no input_field_formatter" do
    config = scaffolded_config()

    assert config =~ "output_field_formatter: :camel_case"
    refute config =~ "input_field_formatter"
  end

  test "the generated RPC controller uses AshRpc.Plug with AshTypescript.RpcProfile" do
    igniter =
      test_project()
      |> Igniter.compose_task("ash_typescript.install", ["--yes"])

    path = "lib/test_web/controllers/ash_typescript_rpc_controller.ex"
    source = igniter.rewrite |> Rewrite.source!(path) |> Rewrite.Source.get(:content)

    assert source =~ "AshRpc.Plug.run(conn, AshTypescript.RpcProfile)"
    assert source =~ "AshRpc.Plug.validate(conn, AshTypescript.RpcProfile)"
    refute source =~ "AshTypescript.Rpc.run_action"
  end

  test "the generated RPC controller lets AshRpc.Plug send the response" do
    source = generated_controller()

    assert {:ok, ast} = Code.string_to_quoted(source)
    assert defined_functions(ast) == [run: 2, validate: 2]

    assert remote_calls(ast) == [
             {AshRpc.Plug, :run, 2},
             {AshRpc.Plug, :validate, 2}
           ]

    for {module, function, arity} <- remote_calls(ast) do
      assert Code.ensure_loaded?(module) and function_exported?(module, function, arity),
             "#{inspect(module)}.#{function}/#{arity} does not exist"
    end

    assert Code.ensure_loaded?(AshTypescript.RpcProfile)
    refute source =~ "json("
  end

  defp generated_controller do
    test_project()
    |> Igniter.compose_task("ash_typescript.install", ["--yes"])
    |> Map.fetch!(:rewrite)
    |> Rewrite.source!("lib/test_web/controllers/ash_typescript_rpc_controller.ex")
    |> Rewrite.Source.get(:content)
  end

  defp defined_functions(ast) do
    ast
    |> Macro.prewalk([], fn
      {:def, _, [{name, _, args} | _]} = node, acc -> {node, [{name, length(args)} | acc]}
      node, acc -> {node, acc}
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp remote_calls(ast) do
    ast
    |> Macro.prewalk([], fn
      {{:., _, [{:__aliases__, _, parts}, function]}, _, args} = node, acc ->
        {node, [{Module.concat(parts), function, length(args)} | acc]}

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
    |> Enum.reverse()
  end
end
