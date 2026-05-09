# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

if Code.ensure_loaded?(Igniter) do
  defmodule AshTypescript.Installer.Framework do
    @moduledoc false

    @valid_frameworks ["react", "vue", "svelte", "solid"]

    def validate_framework(igniter, nil), do: igniter
    def validate_framework(igniter, f) when f in @valid_frameworks, do: igniter

    def validate_framework(igniter, invalid) do
      Igniter.add_issue(
        igniter,
        "Invalid framework '#{invalid}'. Supported: #{Enum.join(@valid_frameworks, ", ")}"
      )
    end

    def validate_bundler(igniter, nil), do: igniter
    def validate_bundler(igniter, "esbuild"), do: igniter
    def validate_bundler(igniter, "vite"), do: igniter

    def validate_bundler(igniter, invalid) do
      Igniter.add_issue(
        igniter,
        "Invalid bundler '#{invalid}'. Supported: esbuild, vite"
      )
    end

    alias AshTypescript.Installer.LandingPage

    @doc "Create the framework's entry point file (index.tsx / index.ts + App component)."
    def create_index_page(igniter, "react") do
      page_body = LandingPage.page_jsx()

      content = """
      import React, { useEffect } from "react";
      import { createRoot } from "react-dom/client";
      import { initLandingPage } from "./animation";

      function App() {
        useEffect(() => {
          const el = document.getElementById("animation-container");
          if (el) return initLandingPage(el);
        }, []);

        return (
      #{page_body}
        );
      }

      createRoot(document.getElementById("app")!).render(
        <React.StrictMode>
          <App />
        </React.StrictMode>,
      );
      """

      igniter
      |> write_animation_module()
      |> Igniter.create_new_file("assets/js/index.tsx", content, on_exists: :warning)
    end

    def create_index_page(igniter, "vue") do
      {script_content, template_content} = LandingPage.page_vue()
      vue_component = script_content <> "\n" <> template_content

      vue_index = """
      import { createApp } from "vue";
      import App from "./App.vue";

      createApp(App).mount("#app");
      """

      igniter
      |> write_animation_module()
      |> Igniter.create_new_file("assets/js/App.vue", vue_component, on_exists: :warning)
      |> Igniter.create_new_file("assets/js/index.ts", vue_index, on_exists: :warning)
    end

    def create_index_page(igniter, "svelte") do
      {script_content, template_content} = LandingPage.page_svelte()
      svelte_component = script_content <> "\n" <> template_content

      svelte_index = """
      import App from "./App.svelte";
      import { mount } from "svelte";

      mount(App, { target: document.getElementById("app")! });
      """

      igniter
      |> write_animation_module()
      |> Igniter.create_new_file("assets/js/App.svelte", svelte_component, on_exists: :warning)
      |> Igniter.create_new_file("assets/js/index.ts", svelte_index, on_exists: :warning)
    end

    def create_index_page(igniter, "solid") do
      page_body = LandingPage.page_jsx()

      content = """
      import { onMount, onCleanup } from "solid-js";
      import { render } from "solid-js/web";
      import { initLandingPage } from "./animation";

      function App() {
        onMount(() => {
          const el = document.getElementById("animation-container");
          if (el) {
            const cleanup = initLandingPage(el);
            onCleanup(cleanup);
          }
        });

        return (
      #{page_body}
        );
      }

      render(() => <App />, document.getElementById("app")!);
      """

      igniter
      |> write_animation_module()
      |> Igniter.create_new_file("assets/js/index.tsx", content, on_exists: :warning)
    end

    defp write_animation_module(igniter) do
      Igniter.create_new_file(
        igniter,
        "assets/js/animation.ts",
        LandingPage.animation_module(),
        on_exists: :warning
      )
    end

    @doc "Update tsconfig.json with framework-specific compiler options."
    def update_tsconfig(igniter, framework) do
      Igniter.update_file(igniter, "assets/tsconfig.json", fn source ->
        content = source.content

        jsx_setting =
          case framework do
            "react" -> "react-jsx"
            "solid" -> "preserve"
            _ -> nil
          end

        needs_jsx =
          if is_nil(jsx_setting),
            do: false,
            else: not String.contains?(content, ~s("jsx":))

        needs_jsx_import_source =
          framework == "solid" and not String.contains?(content, ~s("jsxImportSource":))

        needs_interop = not String.contains?(content, ~s("esModuleInterop":))

        if needs_jsx or needs_jsx_import_source or needs_interop do
          updated_content =
            case Regex.run(~r/"compilerOptions":\s*\{/, content, return: :index) do
              [{start, length}] ->
                insertion_point = start + length

                options_to_add = []

                options_to_add =
                  if needs_jsx,
                    do: [~s(\n    "jsx": "#{jsx_setting}",) | options_to_add],
                    else: options_to_add

                options_to_add =
                  if needs_jsx_import_source,
                    do: [~s(\n    "jsxImportSource": "solid-js",) | options_to_add],
                    else: options_to_add

                options_to_add =
                  if needs_interop,
                    do: [~s(\n    "esModuleInterop": true,) | options_to_add],
                    else: options_to_add

                options_string = Enum.join(options_to_add)

                String.slice(content, 0, insertion_point) <>
                  options_string <>
                  String.slice(content, insertion_point, String.length(content))

              _ ->
                content
            end

          Rewrite.Source.update(source, :content, updated_content)
        else
          source
        end
      end)
    end
  end
end
