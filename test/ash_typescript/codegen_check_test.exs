# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.CodegenCheckTest do
  # Not async because tests modify global Application config
  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    original_config =
      Map.new(
        ~w[output_file always_regenerate enable_namespace_files namespace_output_dir]a,
        &{&1, Application.get_env(:ash_typescript, &1)}
      )

    output_file = Path.join(tmp_dir, "generated.ts")
    Application.put_env(:ash_typescript, :output_file, output_file)
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
