# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.CodegenOutputOptionTest do
  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    keys =
      ~w[output_file types_output_file zod_output_file valibot_output_file routes_output_file typed_channels_output_file]a

    original_config =
      Map.new(keys, &{&1, Application.get_env(:ash_typescript, &1)})

    Enum.each(keys, &Application.delete_env(:ash_typescript, &1))

    Application.put_env(:ash_typescript, :output_file, Path.join(tmp_dir, "ash_rpc.ts"))

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

  describe "--output option" do
    test "writes the RPC file to the explicit .ts path", %{tmp_dir: tmp_dir} do
      target = Path.join(tmp_dir, "ash_generated.ts")

      Mix.Tasks.AshTypescript.Codegen.run(["--output", target])

      assert File.exists?(target)
      assert AshTypescript.types_output_file() == Path.join(tmp_dir, "ash_types.ts")
      assert File.exists?(Path.join(tmp_dir, "ash_types.ts"))
      refute File.exists?(Path.join(tmp_dir, "ash_rpc.ts"))
    end

    test "treats a directory path as an output dir using default file names",
         %{tmp_dir: tmp_dir} do
      dir = Path.join(tmp_dir, "out") <> "/"

      Mix.Tasks.AshTypescript.Codegen.run(["--output", dir])

      assert File.exists?(Path.join([tmp_dir, "out", "ash_rpc.ts"]))
      assert File.exists?(Path.join([tmp_dir, "out", "ash_types.ts"]))
    end

    test "-o alias works the same as --output", %{tmp_dir: tmp_dir} do
      target = Path.join(tmp_dir, "alias.ts")

      Mix.Tasks.AshTypescript.Codegen.run(["-o", target])

      assert File.exists?(target)
    end
  end
end
