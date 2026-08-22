# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.CodegenCheckTest do
  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    original_config =
      Map.new(
        ~w[output_file types_output_file zod_output_file valibot_output_file always_regenerate enable_namespace_files namespace_output_dir routes_output_file typed_channels_output_file manifest_file json_manifest_file warn_on_missing_rpc_config warn_on_non_rpc_references]a,
        &{&1, Application.get_env(:ash_typescript, &1)}
      )

    # These tests exercise the real Mix task, whose codegen would otherwise emit
    # the NotExposed RPC-reference warnings on every run (restored via on_exit).
    Application.put_env(:ash_typescript, :warn_on_missing_rpc_config, false)
    Application.put_env(:ash_typescript, :warn_on_non_rpc_references, false)

    output_file = Path.join(tmp_dir, "generated.ts")
    Application.put_env(:ash_typescript, :output_file, output_file)
    Application.put_env(:ash_typescript, :types_output_file, Path.join(tmp_dir, "ash_types.ts"))
    Application.put_env(:ash_typescript, :zod_output_file, Path.join(tmp_dir, "ash_zod.ts"))

    Application.put_env(
      :ash_typescript,
      :valibot_output_file,
      Path.join(tmp_dir, "ash_valibot.ts")
    )

    Application.put_env(
      :ash_typescript,
      :routes_output_file,
      Path.join(tmp_dir, "generated_routes.ts")
    )

    # Every generated artifact must be redirected into tmp_dir, manifests
    # included — otherwise the real test/ts manifests get overwritten with
    # tmp paths and the next `mix test.codegen --check` reports a false diff.
    Application.put_env(:ash_typescript, :manifest_file, Path.join(tmp_dir, "MANIFEST.md"))

    Application.put_env(
      :ash_typescript,
      :json_manifest_file,
      Path.join(tmp_dir, "ash_rpc_manifest.json")
    )

    Application.put_env(
      :ash_typescript,
      :typed_channels_output_file,
      Path.join(tmp_dir, "generated_typed_channels.ts")
    )

    File.write!(output_file, "")

    on_exit(fn ->
      Enum.each(original_config, fn {key, value} ->
        if value do
          Application.put_env(:ash_typescript, key, value)
        else
          Application.delete_env(:ash_typescript, key)
        end
      end)
    end)

    :ok
  end

  describe "single-file output" do
    test "--check raises PendingCodegen when file is stale" do
      assert_raise Ash.Error.Framework.PendingCodegen, fn ->
        Mix.Tasks.AshTypescript.Codegen.run(["--check"])
      end
    end

    test "--check raises PendingCodegen even with always_regenerate enabled" do
      Application.put_env(:ash_typescript, :always_regenerate, true)

      assert_raise Ash.Error.Framework.PendingCodegen, fn ->
        Mix.Tasks.AshTypescript.Codegen.run(["--check"])
      end
    end

    test "--dev --check raises PendingCodegen when always_regenerate is false" do
      Application.put_env(:ash_typescript, :always_regenerate, false)

      assert_raise Ash.Error.Framework.PendingCodegen, fn ->
        Mix.Tasks.AshTypescript.Codegen.run(["--dev", "--check"])
      end
    end

    test "--dev --check silently regenerates when always_regenerate is true" do
      Application.put_env(:ash_typescript, :always_regenerate, true)

      Mix.Tasks.AshTypescript.Codegen.run(["--dev", "--check"])
    end
  end

  describe "manifests" do
    test "--check flags a stale JSON manifest", %{tmp_dir: tmp_dir} do
      # Bring every other artifact up to date so the manifest is the only delta
      Mix.Tasks.AshTypescript.Codegen.run([])

      json_path = Path.join(tmp_dir, "ash_rpc_manifest.json")
      assert File.exists?(json_path)
      File.write!(json_path, ~s({"version": "1.0"}\n))

      assert_raise Ash.Error.Framework.PendingCodegen, fn ->
        Mix.Tasks.AshTypescript.Codegen.run(["--check"])
      end
    end

    test "--check flags a stale Markdown manifest", %{tmp_dir: tmp_dir} do
      Mix.Tasks.AshTypescript.Codegen.run([])

      md_path = Path.join(tmp_dir, "MANIFEST.md")
      assert File.exists?(md_path)
      File.write!(md_path, "# stale\n")

      assert_raise Ash.Error.Framework.PendingCodegen, fn ->
        Mix.Tasks.AshTypescript.Codegen.run(["--check"])
      end
    end

    test "--check passes when only generatedAt differs", %{tmp_dir: tmp_dir} do
      Mix.Tasks.AshTypescript.Codegen.run([])

      json_path = Path.join(tmp_dir, "ash_rpc_manifest.json")
      stale = json_path |> File.read!() |> Jason.decode!()
      File.write!(json_path, Jason.encode!(%{stale | "generatedAt" => "2020-01-01"}))

      # The date stamp changes daily; treating it as a diff would fail CI on any
      # day the manifest was not regenerated
      Mix.Tasks.AshTypescript.Codegen.run(["--check"])

      # ...and the existing stamp is left untouched rather than rewritten
      assert Jason.decode!(File.read!(json_path))["generatedAt"] == "2020-01-01"
    end

    test "--dry-run previews a stale manifest without writing it", %{tmp_dir: tmp_dir} do
      Mix.Tasks.AshTypescript.Codegen.run([])

      md_path = Path.join(tmp_dir, "MANIFEST.md")
      File.write!(md_path, "# stale\n")

      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Mix.Tasks.AshTypescript.Codegen.run(["--dry-run"])
        end)

      assert output =~ md_path
      assert File.read!(md_path) == "# stale\n"
    end
  end

  describe "multi-file output" do
    setup %{tmp_dir: tmp_dir} do
      Application.put_env(:ash_typescript, :enable_namespace_files, true)
      Application.put_env(:ash_typescript, :namespace_output_dir, tmp_dir)
      :ok
    end

    test "--check raises PendingCodegen when files are stale" do
      assert_raise Ash.Error.Framework.PendingCodegen, fn ->
        Mix.Tasks.AshTypescript.Codegen.run(["--check"])
      end
    end

    test "--check raises PendingCodegen even with always_regenerate enabled" do
      Application.put_env(:ash_typescript, :always_regenerate, true)

      assert_raise Ash.Error.Framework.PendingCodegen, fn ->
        Mix.Tasks.AshTypescript.Codegen.run(["--check"])
      end
    end

    test "--dev --check raises PendingCodegen when always_regenerate is false" do
      Application.put_env(:ash_typescript, :always_regenerate, false)

      assert_raise Ash.Error.Framework.PendingCodegen, fn ->
        Mix.Tasks.AshTypescript.Codegen.run(["--dev", "--check"])
      end
    end

    test "--dev --check silently regenerates when always_regenerate is true" do
      Application.put_env(:ash_typescript, :always_regenerate, true)

      Mix.Tasks.AshTypescript.Codegen.run(["--dev", "--check"])
    end
  end
end
