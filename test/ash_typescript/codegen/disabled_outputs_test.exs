# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.DisabledOutputsTest do
  @moduledoc """
  Codegen with the optional outputs turned off: no validation or channel
  functions (nor their helpers, config interfaces, namespace re-exports and
  JSON manifest names), no `import_into_generated` lines, no schema files,
  and a JSON manifest that lists only the files that are generated. The test
  config turns all of them on, so only these tests reach the "off" side.
  """
  # Changes the app env, so must not run async.
  use ExUnit.Case, async: false

  alias AshTypescript.Rpc.Codegen.JsonManifestGenerator
  alias AshTypescript.Test.{CodegenTestHelper, InlineManifest, TestHelpers}

  setup do
    TestHelpers.restore_application_env_on_exit([
      :generate_validation_functions,
      :generate_phx_channel_rpc_actions,
      :generate_zod_schemas,
      :generate_valibot_schemas,
      :import_into_generated,
      :zod_import_into_generated,
      :enable_namespace_files,
      :output_file,
      :typed_channels_output_file,
      :json_manifest_file
    ])
  end

  describe "without validation and channel functions" do
    setup do
      Application.put_env(:ash_typescript, :generate_validation_functions, false)
      Application.put_env(:ash_typescript, :generate_phx_channel_rpc_actions, false)
      Application.put_env(:ash_typescript, :enable_namespace_files, true)
      {:ok, files} = CodegenTestHelper.generate_files()
      %{files: files, rpc: CodegenTestHelper.rpc_content(files)}
    end

    test "the RPC file has only the execution functions and their helper", %{rpc: rpc} do
      assert rpc =~ "export async function listTodos<"
      assert rpc =~ "export async function executeActionRpcRequest<T>("
      assert rpc =~ "export interface ActionConfig {"

      for name <- [
            "validateListTodos",
            "listTodosChannel",
            "executeValidationRpcRequest",
            "executeActionChannelPush",
            "executeValidationChannelPush",
            "interface ValidationConfig",
            "interface ActionChannelConfig",
            "interface ValidationChannelConfig",
            ~s(import { Channel } from "phoenix";)
          ] do
        refute rpc =~ name
      end
    end

    test "namespace files re-export only the execution functions", %{files: files} do
      dir = Path.dirname(Application.get_env(:ash_typescript, :output_file))
      todos = Map.fetch!(files, Path.join(dir, "todos.ts"))

      assert todos =~ "listTodos"
      refute todos =~ "validateListTodos"
      refute todos =~ "listTodosChannel"
    end

    test "the JSON manifest names only the execution function" do
      %{"actions" => actions} =
        :ash_typescript |> JsonManifestGenerator.generate_json_manifest() |> Jason.decode!()

      entry = Enum.find(actions, &(&1["functionName"] == "listTodos"))

      assert entry["variantNames"] == %{
               "zod" => "listTodosZodSchema",
               "valibot" => "listTodosValibotSchema"
             }
    end
  end

  test "channel functions without validation functions re-export no channel validation" do
    Application.put_env(:ash_typescript, :generate_validation_functions, false)
    Application.put_env(:ash_typescript, :enable_namespace_files, true)
    {:ok, files} = CodegenTestHelper.generate_files()

    dir = Path.dirname(Application.get_env(:ash_typescript, :output_file))
    todos = Map.fetch!(files, Path.join(dir, "todos.ts"))

    assert todos =~ "listTodosChannel"
    refute todos =~ "validateListTodosChannel"
  end

  test "without zod and valibot schemas, no schema files" do
    Application.put_env(:ash_typescript, :generate_zod_schemas, false)
    Application.put_env(:ash_typescript, :generate_valibot_schemas, false)
    {:ok, files} = CodegenTestHelper.generate_files()

    refute Map.has_key?(files, AshTypescript.zod_output_file())
    refute Map.has_key?(files, AshTypescript.valibot_output_file())
  end

  test "without output_file, no RPC file" do
    rpc_path = Application.fetch_env!(:ash_typescript, :output_file)
    Application.delete_env(:ash_typescript, :output_file)
    {:ok, files} = CodegenTestHelper.generate_files()

    refute Map.has_key?(files, rpc_path)
    refute Enum.any?(Map.values(files), &(&1 =~ "export async function listTodos<"))
  end

  test "without import_into_generated, the RPC and types files import no custom modules" do
    Application.delete_env(:ash_typescript, :import_into_generated)
    Application.put_env(:ash_typescript, :generate_phx_channel_rpc_actions, false)
    {:ok, files} = CodegenTestHelper.generate_files()

    refute CodegenTestHelper.rpc_content(files) =~ "import * as CustomTypes"
    refute CodegenTestHelper.types_content(files) =~ "import * as CustomTypes"

    assert CodegenTestHelper.rpc_content(files) =~
             ~r/\A\/\/ Generated by AshTypescript - RPC Actions\n\/\/ Do not edit this file manually\n\n\nimport type \{/
  end

  test "without typed_channels_output_file, no typed channels file" do
    path = Application.fetch_env!(:ash_typescript, :typed_channels_output_file)
    Application.delete_env(:ash_typescript, :typed_channels_output_file)
    {:ok, files} = CodegenTestHelper.generate_files()

    refute Map.has_key?(files, path)
    refute Enum.any?(Map.values(files), &(&1 =~ "export function createContentFeedChannel"))
  end

  test "without zod_import_into_generated, the zod file imports no custom modules" do
    Application.delete_env(:ash_typescript, :zod_import_into_generated)
    {:ok, files} = CodegenTestHelper.generate_files()

    zod = CodegenTestHelper.zod_content(files)
    assert zod =~ ~s(import { z } from "zod";\nimport type {)
    refute zod =~ "import * as CustomZodSchemas"
  end

  describe "the JSON manifest's files" do
    test "leave out the RPC, schema and typed-channel files that aren't generated" do
      Application.delete_env(:ash_typescript, :output_file)
      Application.put_env(:ash_typescript, :generate_zod_schemas, false)
      Application.put_env(:ash_typescript, :generate_valibot_schemas, false)
      Application.delete_env(:ash_typescript, :typed_channels_output_file)

      %{"files" => files} =
        :ash_typescript |> JsonManifestGenerator.generate_json_manifest() |> Jason.decode!()

      assert Map.keys(files) |> Enum.sort() == ["routes", "types"]
    end

    test "leave out the routes file when no typed controller has routes" do
      manifest = InlineManifest.build!(domains: [AshTypescript.Test.Domain])

      %{"files" => files} =
        AshTypescript.with_manifest(manifest, fn ->
          :ash_typescript |> JsonManifestGenerator.generate_json_manifest() |> Jason.decode!()
        end)

      refute Map.has_key?(files, "routes")
    end

    test "name a file outside the manifest's directory by its relative path" do
      Application.put_env(:ash_typescript, :json_manifest_file, "./test/ts/manifest/rpc.json")

      %{"files" => %{"rpc" => rpc}} =
        :ash_typescript |> JsonManifestGenerator.generate_json_manifest() |> Jason.decode!()

      assert rpc["filename"] == "../generated.ts"
    end
  end
end
