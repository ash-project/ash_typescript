# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

if Code.ensure_loaded?(Igniter) do
  defmodule AshTypescript.Installer.Inertia do
    @moduledoc false

    alias AshTypescript.Installer.{Esbuild, Layout, PackageJson}

    @doc "Run the full Inertia installation pipeline."
    def setup(igniter, app_name, web_module, bundler, use_bun, framework) do
      igniter
      |> add_inertia_dep()
      |> add_inertia_npm_deps(framework)
      |> add_inertia_config(web_module)
      |> setup_inertia_web_module(web_module)
      |> add_inertia_plug_to_router()
      |> setup_framework_bundler(app_name, bundler, use_bun, framework)
      |> Layout.create_inertia_root_layout(web_module, bundler, framework)
      |> create_inertia_entry_point(framework)
      |> create_inertia_ssr_entry_point(framework)
      |> setup_inertia_ssr_support(app_name, web_module, bundler, framework)
      |> create_inertia_page_component(framework)
      |> create_inertia_page_controller(web_module)
      |> add_inertia_pipeline_and_routes(web_module)
    end

    # -- Dependency management --

    defp add_inertia_dep(igniter) do
      Igniter.Project.Deps.add_dep(igniter, {:inertia, "~> 2.6.0"})
    end

    defp add_inertia_npm_deps(igniter, framework) do
      inertia_pkg = get_inertia_npm_package(framework)

      PackageJson.update_package_json(igniter, fn package_json ->
        PackageJson.merge_package_section(package_json, "dependencies", %{
          inertia_pkg => "^2.0.0"
        })
      end)
    end

    defp get_inertia_npm_package("react"), do: "@inertiajs/react"
    defp get_inertia_npm_package("vue"), do: "@inertiajs/vue3"
    defp get_inertia_npm_package("svelte"), do: "@inertiajs/svelte"
    defp get_inertia_npm_package(_), do: "@inertiajs/react"

    # -- Config --

    defp add_inertia_config(igniter, web_module) do
      clean = web_module |> to_string() |> String.replace_prefix("Elixir.", "")

      igniter
      |> Igniter.Project.Config.configure_new(
        "config.exs",
        :inertia,
        [:endpoint],
        {:code, Sourceror.parse_string!("#{clean}.Endpoint")}
      )
      |> Igniter.Project.Config.configure_new(
        "config.exs",
        :inertia,
        [:static_paths],
        ["/assets/index.js"]
      )
      |> Igniter.Project.Config.configure_new("config.exs", :inertia, [:default_version], "1")
      |> Igniter.Project.Config.configure_new("config.exs", :inertia, [:camelize_props], false)
    end

    # -- Web module setup --

    defp setup_inertia_web_module(igniter, web_module) do
      {igniter, source, _zipper} =
        case Igniter.Project.Module.find_module(igniter, web_module) do
          {:ok, result} -> result
          {:error, igniter} -> {igniter, nil, nil}
        end

      if is_nil(source) do
        Igniter.add_warning(
          igniter,
          "Could not find web module #{inspect(web_module)}. " <>
            "Please manually add `import Inertia.Controller` to your controller helper " <>
            "and `import Inertia.HTML` to your html helper."
        )
      else
        web_content = Rewrite.Source.get(source, :content)

        updated_content =
          web_content
          |> maybe_add_import(
            "Inertia.Controller",
            "import Plug.Conn\n\n      unquote(verified_routes())",
            "import Plug.Conn\n      import Inertia.Controller\n\n      unquote(verified_routes())"
          )
          |> maybe_add_import(
            "Inertia.HTML",
            "import Phoenix.HTML",
            "import Phoenix.HTML\n      import Inertia.HTML"
          )

        if web_content == updated_content do
          igniter
        else
          path = Rewrite.Source.get(source, :path)

          Igniter.update_file(igniter, path, fn source ->
            Rewrite.Source.update(source, :content, updated_content)
          end)
        end
      end
    end

    defp maybe_add_import(content, check, find, replace) do
      if String.contains?(content, check),
        do: content,
        else: String.replace(content, find, replace)
    end

    # -- Router --

    defp add_inertia_plug_to_router(igniter) do
      {igniter, router_module} = Igniter.Libs.Phoenix.select_router(igniter)

      case Igniter.Project.Module.find_module(igniter, router_module) do
        {:ok, {igniter, source, _zipper}} ->
          router_content = Rewrite.Source.get(source, :content)

          if String.contains?(router_content, "Inertia.Plug") do
            igniter
          else
            path = Rewrite.Source.get(source, :path)

            Igniter.update_file(igniter, path, fn source ->
              content = source.content

              updated_content =
                String.replace(
                  content,
                  "plug :put_secure_browser_headers",
                  "plug :put_secure_browser_headers\n    plug Inertia.Plug"
                )

              if content == updated_content,
                do: source,
                else: Rewrite.Source.update(source, :content, updated_content)
            end)
          end

        {:error, igniter} ->
          Igniter.add_warning(
            igniter,
            "Could not find router. Please manually add `plug Inertia.Plug` to your browser pipeline."
          )
      end
    end

    defp add_inertia_pipeline_and_routes(igniter, web_module) do
      {igniter, router_module} = Igniter.Libs.Phoenix.select_router(igniter)

      case Igniter.Project.Module.find_module(igniter, router_module) do
        {:ok, {igniter, source, _zipper}} ->
          router_content = Rewrite.Source.get(source, :content)
          clean = web_module |> to_string() |> String.replace_prefix("Elixir.", "")
          path = Rewrite.Source.get(source, :path)

          igniter =
            if String.contains?(router_content, "pipeline :inertia") do
              igniter
            else
              Igniter.update_file(igniter, path, fn source ->
                content = source.content

                pipeline_code = """

                  pipeline :inertia do
                    plug :put_root_layout, html: {#{clean}.Layouts, :inertia_root}
                  end
                """

                updated_content =
                  Regex.replace(
                    ~r/(pipeline :browser do.*?end)/s,
                    content,
                    "\\1\n#{pipeline_code}",
                    global: false
                  )

                if content == updated_content,
                  do: source,
                  else: Rewrite.Source.update(source, :content, updated_content)
              end)
            end

          # Re-read source after potential pipeline addition
          {igniter, source, _zipper} =
            case Igniter.Project.Module.find_module(igniter, router_module) do
              {:ok, result} -> result
              {:error, igniter} -> {igniter, nil, nil}
            end

          if is_nil(source) do
            igniter
          else
            router_content = Rewrite.Source.get(source, :content)

            if String.contains?(router_content, "pipe_through :inertia") do
              igniter
            else
              inertia_scope = """
                  scope "/" do
                    pipe_through :inertia
                    get "/ash-typescript", PageController, :index
                  end
              """

              Igniter.update_file(igniter, path, fn source ->
                content = source.content

                updated_content =
                  Regex.replace(
                    ~r/(scope "\/", #{Regex.escape(clean)} do\s*\n\s*pipe_through :browser)/s,
                    content,
                    "\\1\n\n#{inertia_scope}",
                    global: false
                  )

                if content == updated_content,
                  do: source,
                  else: Rewrite.Source.update(source, :content, updated_content)
              end)
            end
          end

        {:error, igniter} ->
          Igniter.add_warning(
            igniter,
            "Could not find router. Please manually add the :inertia pipeline and route."
          )
      end
    end

    # -- Bundler setup for Inertia --

    defp setup_framework_bundler(igniter, app_name, "esbuild", use_bun, framework)
         when framework in ["vue", "svelte"] do
      igniter
      |> Esbuild.create_esbuild_script(framework, ssr: true)
      |> Esbuild.update_esbuild_config_with_script(app_name, use_bun)
      |> Esbuild.update_root_layout_for_esbuild()
    end

    defp setup_framework_bundler(igniter, app_name, "esbuild", use_bun, framework) do
      igniter
      |> Esbuild.update_esbuild_config_for_inertia(app_name, use_bun, framework)
      |> Esbuild.update_root_layout_for_esbuild()
    end

    defp setup_framework_bundler(igniter, _app_name, _bundler, _use_bun, _framework), do: igniter

    # -- SSR support --

    defp setup_inertia_ssr_support(igniter, app_name, web_module, "esbuild", framework)
         when framework == "react" do
      igniter
      |> configure_inertia_ssr_esbuild_profile(framework)
      |> add_inertia_ssr_dev_watcher(app_name)
      |> add_inertia_ssr_mix_aliases()
      |> add_inertia_ssr_gitignore_entry()
      |> add_inertia_ssr_application_child(app_name, web_module)
      |> enable_inertia_ssr_config()
    end

    defp setup_inertia_ssr_support(igniter, app_name, web_module, "esbuild", framework)
         when framework in ["vue", "svelte"] do
      igniter
      |> add_inertia_ssr_gitignore_entry()
      |> add_inertia_ssr_application_child(app_name, web_module)
      |> enable_inertia_ssr_config()
    end

    defp setup_inertia_ssr_support(igniter, _app_name, _web_module, _bundler, _framework),
      do: igniter

    defp configure_inertia_ssr_esbuild_profile(igniter, framework) do
      ssr_entry = if framework == "react", do: "js/ssr.tsx", else: "js/ssr.ts"

      ssr_profile_ast =
        Sourceror.parse_string!("""
        [
          args: ~w(#{ssr_entry} --bundle --platform=node --outdir=../priv --format=cjs),
          cd: Path.expand("../assets", __DIR__),
          env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
        ]
        """)

      Igniter.Project.Config.configure(
        igniter,
        "config.exs",
        :esbuild,
        [:ssr],
        {:code, ssr_profile_ast},
        updater: fn zipper ->
          {:ok, Igniter.Code.Common.replace_code(zipper, ssr_profile_ast)}
        end
      )
    end

    defp add_inertia_ssr_dev_watcher(igniter, app_name) do
      {igniter, endpoint} = Igniter.Libs.Phoenix.select_endpoint(igniter)

      endpoint =
        case endpoint do
          nil ->
            web_module = Igniter.Libs.Phoenix.web_module(igniter)
            Module.concat(web_module, Endpoint)

          endpoint ->
            endpoint
        end

      default_watchers =
        Sourceror.parse_string!("""
        [
          esbuild: {Esbuild, :install_and_run, [#{inspect(app_name)}, ~w(--sourcemap=inline --watch)]},
          ssr: {Esbuild, :install_and_run, [:ssr, ~w(--sourcemap=inline --watch)]},
          tailwind: {Tailwind, :install_and_run, [#{inspect(app_name)}, ~w(--watch)]}
        ]
        """)

      ssr_watcher =
        Sourceror.parse_string!(
          "{Esbuild, :install_and_run, [:ssr, ~w(--sourcemap=inline --watch)]}"
        )

      Igniter.Project.Config.configure(
        igniter,
        "dev.exs",
        app_name,
        [endpoint, :watchers],
        {:code, default_watchers},
        updater: fn zipper ->
          Igniter.Code.Keyword.set_keyword_key(zipper, :ssr, ssr_watcher, &{:ok, &1})
        end
      )
    end

    defp add_inertia_ssr_mix_aliases(igniter) do
      igniter
      |> Igniter.Project.TaskAliases.add_alias("assets.build", "esbuild ssr", if_exists: :append)
      |> Igniter.Project.TaskAliases.add_alias("assets.deploy", "esbuild ssr", if_exists: :append)
    end

    defp add_inertia_ssr_gitignore_entry(igniter) do
      if Igniter.exists?(igniter, ".gitignore") do
        Igniter.update_file(igniter, ".gitignore", fn source ->
          content = source.content

          if String.contains?(content, "/priv/ssr.js") do
            source
          else
            updated_content =
              if String.ends_with?(content, "\n"),
                do: content <> "/priv/ssr.js\n",
                else: content <> "\n/priv/ssr.js\n"

            Rewrite.Source.update(source, :content, updated_content)
          end
        end)
      else
        Igniter.create_new_file(igniter, ".gitignore", "/priv/ssr.js\n")
      end
    end

    defp add_inertia_ssr_application_child(igniter, app_name, web_module) do
      clean = web_module |> to_string() |> String.replace_prefix("Elixir.", "")
      app_module = String.replace_suffix(clean, "Web", "")
      app_path = Macro.underscore(app_module)
      application_path = "lib/#{app_path}/application.ex"

      ssr_child =
        "      {Inertia.SSR, path: Path.join([Application.app_dir(:#{app_name}), \"priv\"])}"

      endpoint_child = "      #{clean}.Endpoint"

      Igniter.update_file(igniter, application_path, fn source ->
        content = source.content

        if String.contains?(content, "Inertia.SSR") do
          source
        else
          updated_content =
            String.replace(content, endpoint_child, ssr_child <> ",\n" <> endpoint_child,
              global: false
            )

          if updated_content == content,
            do: source,
            else: Rewrite.Source.update(source, :content, updated_content)
        end
      end)
    end

    defp enable_inertia_ssr_config(igniter) do
      raise_setting = Sourceror.parse_string!("config_env() != :prod")

      igniter
      |> Igniter.Project.Config.configure(
        "config.exs",
        :inertia,
        [:ssr],
        true,
        updater: fn zipper ->
          {:ok, Igniter.Code.Common.replace_code(zipper, true)}
        end
      )
      |> Igniter.Project.Config.configure(
        "config.exs",
        :inertia,
        [:raise_on_ssr_failure],
        {:code, raise_setting},
        updater: fn zipper ->
          {:ok, Igniter.Code.Common.replace_code(zipper, raise_setting)}
        end
      )
    end

    # -- Entry points (simplified, no Prism) --

    defp create_inertia_entry_point(igniter, "react") do
      content = """
      import { createInertiaApp } from "@inertiajs/react";
      import { hydrateRoot } from "react-dom/client";

      createInertiaApp({
        resolve: async (name) => {
          return await import(`./pages/${name}.tsx`);
        },
        setup({ el, App, props }) {
          hydrateRoot(el, <App {...props} />);
        },
      });
      """

      Igniter.create_new_file(igniter, "assets/js/index.tsx", content, on_exists: :warning)
    end

    defp create_inertia_entry_point(igniter, "vue") do
      content = """
      import { createSSRApp, h } from "vue";
      import { createInertiaApp } from "@inertiajs/vue3";

      createInertiaApp({
        resolve: async (name) => {
          return await import(`./pages/${name}.vue`);
        },
        setup({ el, App, props, plugin }) {
          createSSRApp({ render: () => h(App, props) })
            .use(plugin)
            .mount(el);
        },
      });
      """

      Igniter.create_new_file(igniter, "assets/js/index.ts", content, on_exists: :warning)
    end

    defp create_inertia_entry_point(igniter, "svelte") do
      content = """
      import { mount, hydrate } from "svelte";
      import { createInertiaApp } from "@inertiajs/svelte";

      createInertiaApp({
        resolve: async (name) => {
          return await import(`./pages/${name}.svelte`);
        },
        setup({ el, App, props }) {
          if (el.dataset.serverRendered === "true") {
            hydrate(App, { target: el, props });
          } else {
            mount(App, { target: el, props });
          }
        },
      });
      """

      Igniter.create_new_file(igniter, "assets/js/index.ts", content, on_exists: :warning)
    end

    defp create_inertia_ssr_entry_point(igniter, framework)
         when framework == "react" do
      content = """
      import { createInertiaApp } from "@inertiajs/react";
      import ReactDOMServer from "react-dom/server";

      export function render(page) {
        return createInertiaApp({
          page,
          render: ReactDOMServer.renderToString,
          resolve: async (name) => {
            return await import(`./pages/${name}.tsx`);
          },
          setup: ({ App, props }) => <App {...props} />,
        });
      }
      """

      Igniter.create_new_file(igniter, "assets/js/ssr.tsx", content, on_exists: :warning)
    end

    defp create_inertia_ssr_entry_point(igniter, "vue") do
      content = """
      import { createInertiaApp } from "@inertiajs/vue3";
      import { renderToString } from "vue/server-renderer";
      import { createSSRApp, h } from "vue";

      export function render(page) {
        return createInertiaApp({
          page,
          render: renderToString,
          resolve: async (name) => {
            return await import(`./pages/${name}.vue`);
          },
          setup({ App, props, plugin }) {
            return createSSRApp({
              render: () => h(App, props),
            }).use(plugin);
          },
        });
      }
      """

      Igniter.create_new_file(igniter, "assets/js/ssr.ts", content, on_exists: :warning)
    end

    defp create_inertia_ssr_entry_point(igniter, "svelte") do
      content = """
      import { createInertiaApp } from "@inertiajs/svelte";
      import { render as renderSvelte } from "svelte/server";

      export function render(page) {
        return createInertiaApp({
          page,
          resolve: async (name) => {
            return await import(`./pages/${name}.svelte`);
          },
          setup({ App, props }) {
            return renderSvelte(App, { props });
          },
        });
      }
      """

      Igniter.create_new_file(igniter, "assets/js/ssr.ts", content, on_exists: :warning)
    end

    # -- Page components --

    alias AshTypescript.Installer.LandingPage

    defp create_inertia_page_component(igniter, framework)
         when framework == "react" do
      page_body = LandingPage.page_jsx()

      content = """
      import React, { useEffect } from "react";
      import { initLandingPage } from "../animation";

      export default function App() {
        useEffect(() => {
          const el = document.getElementById("animation-container");
          if (el) return initLandingPage(el);
        }, []);

        return (
      #{page_body}
        );
      }
      """

      igniter
      |> write_animation_module()
      |> Igniter.create_new_file("assets/js/pages/App.tsx", content, on_exists: :warning)
    end

    defp create_inertia_page_component(igniter, "vue") do
      {script_content, template_content} = LandingPage.page_vue()
      # For Inertia pages, animation import path is ../animation
      script_content =
        String.replace(script_content, ~s|from "./animation"|, ~s|from "../animation"|)

      content = script_content <> "\n" <> template_content

      igniter
      |> write_animation_module()
      |> Igniter.create_new_file("assets/js/pages/App.vue", content, on_exists: :warning)
    end

    defp create_inertia_page_component(igniter, "svelte") do
      {script_content, template_content} = LandingPage.page_svelte()
      # For Inertia pages, animation import path is ../animation
      script_content =
        String.replace(script_content, ~s|from "./animation"|, ~s|from "../animation"|)

      content = script_content <> "\n" <> template_content

      igniter
      |> write_animation_module()
      |> Igniter.create_new_file("assets/js/pages/App.svelte", content, on_exists: :warning)
    end

    defp write_animation_module(igniter) do
      Igniter.create_new_file(
        igniter,
        "assets/js/animation.ts",
        LandingPage.animation_module(),
        on_exists: :warning
      )
    end

    # -- Page controller --

    defp create_inertia_page_controller(igniter, web_module) do
      clean = web_module |> to_string() |> String.replace_prefix("Elixir.", "")
      page_name = "App"

      controller_path =
        clean
        |> String.replace_suffix("Web", "")
        |> Macro.underscore()

      page_controller_path = "lib/#{controller_path}_web/controllers/page_controller.ex"

      page_controller_content = """
      defmodule #{clean}.PageController do
        use #{clean}, :controller

        def index(conn, _params) do
          render_inertia(conn, "#{page_name}")
        end
      end
      """

      case Igniter.exists?(igniter, page_controller_path) do
        false ->
          Igniter.create_new_file(igniter, page_controller_path, page_controller_content)

        true ->
          Igniter.update_elixir_file(igniter, page_controller_path, fn zipper ->
            case Igniter.Code.Common.move_to(zipper, &function_named?(&1, :index, 2)) do
              {:ok, _zipper} ->
                zipper

              :error ->
                case Igniter.Code.Module.move_to_defmodule(zipper) do
                  {:ok, zipper} ->
                    case Igniter.Code.Common.move_to_do_block(zipper) do
                      {:ok, zipper} ->
                        index_function_code =
                          quote do
                            def index(conn, _params) do
                              render_inertia(conn, unquote(page_name))
                            end
                          end

                        Igniter.Code.Common.add_code(zipper, index_function_code)

                      :error ->
                        zipper
                    end

                  :error ->
                    zipper
                end
            end
          end)
      end
    end

    defp function_named?(zipper, name, arity) do
      case Sourceror.Zipper.node(zipper) do
        {:def, _, [{^name, _, args}, _]} when length(args) == arity -> true
        _ -> false
      end
    end
  end
end
