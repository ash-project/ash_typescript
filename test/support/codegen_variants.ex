# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.CodegenVariants do
  @moduledoc """
  Codegen output under non-default settings, compiled by TypeScript.

  `mix test.codegen_variants` calls `generate!/0`, which generates each
  variant into `test/ts/variants/<name>/` (gitignored, except the
  hand-written `usage.ts` and `*Hooks.ts`); `npm run compileVariants` (in
  `test/ts/`) then compiles every variant's `usage.ts` against its generated
  files.

  Each variant sets its codegen settings with `Application.put_env` in the
  `mix run` process, restored after it, and never runs from ExUnit.
  `redecorate:` options generate against
  `AshTypescript.Manifest.redecorate/2` of the app manifest.
  """

  alias AshTypescript.Test.CodegenTestHelper

  @root "test/ts/variants"

  # Written above each generated file: while nothing under
  # `test/ts/variants/` is committed, git doesn't report the outputs as
  # ignored, so `reuse lint` checks them for a license header.
  # REUSE-IgnoreStart
  @header """
  // SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
  //
  // SPDX-License-Identifier: MIT

  """

  # REUSE-IgnoreEnd

  @output_files [
    output_file: "generated.ts",
    types_output_file: "ash_types.ts",
    zod_output_file: "ash_zod.ts",
    valibot_output_file: "ash_valibot.ts",
    routes_output_file: "generated_routes.ts",
    typed_channels_output_file: "generated_typed_channels.ts"
  ]

  @doc "The variants: a name, the settings it changes and its manifest's redecoration."
  def variants do
    [
      # Without RPC output, as in `no_rpc_types_file_test.exs`.
      %{name: "no_rpc_types", env: [output_file: nil], redecorate: nil},
      %{name: "paths_only", env: [typed_controller_mode: :paths_only], redecorate: nil},
      %{
        name: "path_params_args",
        env: [typed_controller_path_params_style: :args],
        redecorate: nil
      },
      %{
        name: "base_path_string",
        env: [typed_controller_base_path: "https://api.example.com"],
        redecorate: nil
      },
      %{
        name: "base_path_runtime",
        env: [typed_controller_base_path: {:runtime_expr, "AppConfig.getBasePath()"}],
        redecorate: nil
      },
      # Its hooks are typed against its own generated file.
      %{
        name: "pascal_rpc",
        env: [import_into_generated: variant_hooks("pascal_rpc")],
        redecorate: [output_formatter: :pascal_case]
      }
    ]
  end

  @doc "Generates every variant into `test/ts/variants/<name>/`."
  def generate! do
    # `CodegenTestHelper` captures stderr, which needs ExUnit's capture server.
    {:ok, _} = Application.ensure_all_started(:ex_unit)
    Enum.each(variants(), &generate_variant!/1)
  end

  defp generate_variant!(%{name: name} = variant) do
    dir = Path.join(@root, name)
    clean!(dir)

    env =
      Enum.map(@output_files, fn {key, file} -> {key, "./" <> Path.join(dir, file)} end)
      |> Keyword.merge(variant.env)

    files =
      with_env(env, fn ->
        case CodegenTestHelper.generate_files(:ash_typescript, manifest_opts(variant)) do
          {:ok, files} -> files
          {:error, message} -> raise "codegen variant #{name} failed:\n#{message}"
        end
      end)

    Enum.each(files, fn {path, content} ->
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, @header <> content)
    end)

    Mix.shell().info("#{name}: #{map_size(files)} files")
  end

  defp manifest_opts(%{redecorate: nil}), do: []

  defp manifest_opts(%{redecorate: opts}),
    do: [manifest: AshTypescript.Manifest.redecorate(AshTypescript.manifest(), opts)]

  # The app's `import_into_generated`, with the hook modules taken from the
  # variant's committed `rpcHooks.ts` and `channelHooks.ts`.
  defp variant_hooks(name) do
    hooks = %{"RpcHooks" => "rpcHooks.ts", "ChannelHooks" => "channelHooks.ts"}

    :ash_typescript
    |> Application.get_env(:import_into_generated, [])
    |> Enum.map(fn import ->
      case hooks[import.import_name] do
        nil -> import
        file -> %{import | file: "./" <> Path.join([@root, name, file])}
      end
    end)
  end

  # Everything but the committed files (`.gitignore`), so no file of an
  # earlier run stays.
  defp clean!(dir) do
    File.mkdir_p!(dir)

    dir
    |> File.ls!()
    |> Enum.reject(&(&1 == "usage.ts" or String.ends_with?(&1, "Hooks.ts")))
    |> Enum.each(&File.rm_rf!(Path.join(dir, &1)))
  end

  defp with_env(env, fun) do
    saved = Enum.map(env, fn {key, _} -> {key, Application.fetch_env(:ash_typescript, key)} end)
    Enum.each(env, fn {key, value} -> put_env(key, value) end)

    try do
      fun.()
    after
      Enum.each(saved, fn
        {key, {:ok, value}} -> Application.put_env(:ash_typescript, key, value)
        {key, :error} -> Application.delete_env(:ash_typescript, key)
      end)
    end
  end

  defp put_env(key, nil), do: Application.delete_env(:ash_typescript, key)
  defp put_env(key, value), do: Application.put_env(:ash_typescript, key, value)
end
