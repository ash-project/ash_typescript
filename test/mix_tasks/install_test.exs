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
end
