# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

if Code.ensure_loaded?(Igniter) do
  defmodule AshTypescript.Installer.Vite do
    @moduledoc false

    @doc "Add the framework's vite plugin and update the input config."
    def update_vite_config_with_framework(igniter, framework) do
      {check_string, import_line, plugin_call, entry_file} = vite_framework_config(framework)

      Igniter.update_file(igniter, "assets/vite.config.mjs", fn source ->
        content = source.content

        updated_content =
          if String.contains?(content, check_string) do
            replace_spa_vite_input_config(content, entry_file)
          else
            content
            |> String.replace(
              ~s|import { defineConfig } from 'vite'|,
              ~s|import { defineConfig } from 'vite'\n#{import_line}|
            )
            |> String.replace(
              ~s|plugins: [|,
              ~s|plugins: [\n    #{plugin_call},|
            )
            |> replace_spa_vite_input_config(entry_file)
          end

        if updated_content == content do
          source
        else
          Rewrite.Source.update(source, :content, updated_content)
        end
      end)
    end

    @doc """
    Guard against a PhoenixVite bug where cache_static_manifest_latest in runtime.exs
    fails during MIX_ENV=prod assets.deploy because the manifest doesn't exist yet.
    """
    def maybe_fix_runtime_manifest_cache(igniter, "vite", app_name) do
      runtime_path = "config/runtime.exs"

      direct_call =
        "cache_static_manifest_latest: PhoenixVite.cache_static_manifest_latest(:#{app_name})"

      tuple_call =
        ~s|cache_static_manifest_latest: PhoenixVite.cache_static_manifest_latest({:#{app_name}, "priv/static/.vite/manifest.json"})|

      guarded_call =
        ~s|cache_static_manifest_latest: if(File.exists?(Application.app_dir(:#{app_name}, "priv/static/.vite/manifest.json")), do: PhoenixVite.cache_static_manifest_latest(:#{app_name}), else: %{})|

      Igniter.update_file(igniter, runtime_path, fn source ->
        content = source.content

        updated_content =
          content
          |> String.replace(direct_call, guarded_call)
          |> String.replace(tuple_call, guarded_call)

        if updated_content == content do
          source
        else
          Rewrite.Source.update(source, :content, updated_content)
        end
      end)
    end

    def maybe_fix_runtime_manifest_cache(igniter, _bundler, _app_name), do: igniter

    # -- Private --

    defp vite_framework_config("vue") do
      {"@vitejs/plugin-vue", ~s|import vue from '@vitejs/plugin-vue'|, "vue()", "js/index.ts"}
    end

    defp vite_framework_config("svelte") do
      {"@sveltejs/vite-plugin-svelte", ~s|import { svelte } from '@sveltejs/vite-plugin-svelte'|,
       "svelte()", "js/index.ts"}
    end

    defp vite_framework_config("react") do
      {"@vitejs/plugin-react", ~s|import react from '@vitejs/plugin-react'|, "react()",
       "js/index.tsx"}
    end

    defp vite_framework_config("solid") do
      {"vite-plugin-solid", ~s|import solid from 'vite-plugin-solid'|, "solid()", "js/index.tsx"}
    end

    defp replace_spa_vite_input_config(content, spa_entry) do
      input_config = ~s|input: ["#{spa_entry}", "js/app.js", "css/app.css"]|

      content
      |> String.replace(~s|input: ["js/app.js", "css/app.css"]|, input_config)
      |> String.replace(~s|input: ["js/index.ts", "js/app.js", "css/app.css"]|, input_config)
      |> String.replace(~s|input: ["js/index.tsx", "js/app.js", "css/app.css"]|, input_config)
      |> String.replace(
        ~s|input: {"js/index.js": "js/index.ts", "js/app.js": "js/app.js", "css/app.css": "css/app.css"}|,
        input_config
      )
      |> String.replace(
        ~s|input: {"js/index.js": "js/index.tsx", "js/app.js": "js/app.js", "css/app.css": "css/app.css"}|,
        input_config
      )
    end
  end
end
