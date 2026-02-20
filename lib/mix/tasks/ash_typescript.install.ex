# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.AshTypescript.Install do
    @shortdoc "Installs AshTypescript into a project. Should be called with `mix igniter.install ash_typescript`"

    @moduledoc """
    #{@shortdoc}
    """

    use Igniter.Mix.Task

    @impl Igniter.Mix.Task
    def info(_argv, _source) do
      %Igniter.Mix.Task.Info{
        group: :ash,
        installs: [],
        schema: [framework: :string, bundler: :string, bun: :boolean, inertia: :boolean],
        defaults: [framework: nil, bundler: "esbuild", bun: false, inertia: false],
        composes: []
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      app_name = Igniter.Project.Application.app_name(igniter)
      web_module = Igniter.Libs.Phoenix.web_module(igniter)
      framework = Keyword.get(igniter.args.options, :framework, nil)
      bundler = Keyword.get(igniter.args.options, :bundler, "esbuild")
      use_bun = Keyword.get(igniter.args.options, :bun, false)
      use_inertia = Keyword.get(igniter.args.options, :inertia, false)

      # Validate framework parameter
      igniter = validate_framework(igniter, framework)
      # Validate bundler
      igniter = validate_bundler(igniter, bundler)

      # Inertia requires a framework
      igniter =
        if use_inertia and is_nil(framework) do
          Igniter.add_issue(
            igniter,
            "The --inertia flag requires a --framework to be specified (react, react18, vue, or svelte)"
          )
        else
          igniter
        end

      # Store of args for use after fresh igniter
      args = igniter.args

      igniter =
        if bundler == "vite" do
          install_args =
            if use_bun, do: ["--yes", "--bun"], else: ["--yes"]

          # Install phoenix_vite and return the resulting igniter
          # The install function modifies the project, so we need to start fresh
          # but preserve our args
          Igniter.Util.Install.install(
            [{:phoenix_vite, "~> 0.4.0"}],
            install_args,
            igniter
          )

          # After phoenix_vite install completes, we get a fresh igniter
          # but need to preserve our original args
          Igniter.new()
          |> Map.put(:args, args)
        else
          igniter
        end

      igniter =
        igniter
        |> Igniter.Project.IgniterConfig.add_extension(Igniter.Extensions.Phoenix)
        |> Igniter.Project.Formatter.import_dep(:ash_typescript)
        |> add_ash_typescript_config()
        |> create_rpc_controller(app_name, web_module)
        |> add_rpc_routes(web_module)

      igniter =
        case {framework, use_inertia} do
          {nil, _} ->
            igniter

          {framework, true} ->
            # Inertia flow: separate entry point, layout, controller, and routes
            igniter
            |> create_package_json(bundler, framework)
            |> add_inertia_deps(framework)
            |> update_tsconfig(framework)
            |> setup_framework_bundler_for_inertia(app_name, bundler, use_bun, framework)
            |> add_inertia_dep()
            |> add_inertia_config(web_module)
            |> setup_inertia_web_module(web_module)
            |> add_inertia_plug_to_router()
            |> create_inertia_root_layout(web_module, bundler, framework)
            |> create_inertia_entry_point(framework, bundler)
            |> create_inertia_page_component(framework)
            |> create_inertia_page_controller(web_module, framework)
            |> add_inertia_pipeline_and_routes(web_module)

          {framework, false} ->
            # SPA flow: client-side routing with spa_root layout
            igniter
            |> create_package_json(bundler, framework)
            |> create_index_page(framework)
            |> update_tsconfig(framework)
            |> setup_framework_bundler(app_name, bundler, use_bun, framework)
            |> create_spa_root_layout(web_module, bundler, framework)
            |> create_or_update_page_controller(web_module, bundler)
            |> create_index_template(web_module, bundler, framework)
            |> add_page_index_route(web_module)
        end

      igniter
      |> add_next_steps_notice(framework, bundler, use_inertia)
    end

    defp setup_framework_bundler(igniter, app_name, "esbuild", use_bun, framework)
         when framework in ["vue", "svelte"] do
      # Vue and Svelte need custom build scripts with esbuild plugins
      igniter
      |> create_esbuild_script(framework)
      |> update_esbuild_config_with_script(app_name, use_bun, framework)
      |> update_root_layout_for_esbuild()
    end

    defp setup_framework_bundler(igniter, app_name, "esbuild", use_bun, framework) do
      igniter
      |> update_esbuild_config(app_name, use_bun, framework)
      |> update_root_layout_for_esbuild()
    end

    defp setup_framework_bundler(igniter, _app_name, "vite", _use_bun, framework)
         when framework in ["vue", "svelte"] do
      # Add vite plugins for Vue/Svelte
      igniter
      |> update_vite_config_with_framework(framework)
    end

    defp setup_framework_bundler(igniter, _app_name, "vite", _use_bun, framework)
         when framework in ["react", "react18"] do
      # Add React entry point to vite config
      igniter
      |> update_vite_config_with_framework("react")
    end

    defp setup_framework_bundler(igniter, _app_name, "vite", _use_bun, _framework), do: igniter

    defp validate_framework(igniter, framework) do
      case framework do
        nil ->
          igniter

        "react" ->
          igniter

        "react18" ->
          igniter

        "vue" ->
          igniter

        "svelte" ->
          igniter

        invalid_framework ->
          Igniter.add_issue(
            igniter,
            "Invalid framework '#{invalid_framework}'. Currently supported frameworks: react, react18, vue, svelte"
          )
      end
    end

    defp validate_bundler(igniter, bundler) do
      case bundler do
        nil ->
          igniter

        "vite" ->
          igniter

        "esbuild" ->
          igniter

        invalid_bundler ->
          Igniter.add_issue(
            igniter,
            "Invalid bundler #{invalid_bundler}. Currently supported bundlers: vite, esbuild"
          )
      end
    end

    defp create_rpc_controller(igniter, app_name, web_module) do
      clean_web_module = web_module |> to_string() |> String.replace_prefix("Elixir.", "")

      controller_content = """
      defmodule #{clean_web_module}.AshTypescriptRpcController do
        use #{clean_web_module}, :controller

        def run(conn, params) do
          result = AshTypescript.Rpc.run_action(:#{app_name}, conn, params)
          json(conn, result)
        end

        def validate(conn, params) do
          result = AshTypescript.Rpc.validate_action(:#{app_name}, conn, params)
          json(conn, result)
        end
      end
      """

      web_folder = Macro.underscore(clean_web_module)

      controller_path =
        Path.join(["lib", web_folder, "controllers", "ash_typescript_rpc_controller.ex"])

      igniter
      |> Igniter.create_new_file(controller_path, controller_content, on_exists: :warning)
    end

    defp add_rpc_routes(igniter, web_module) do
      run_endpoint = Application.get_env(:ash_typescript, :run_endpoint)
      validate_endpoint = Application.get_env(:ash_typescript, :validate_endpoint)

      {igniter, router_module} = Igniter.Libs.Phoenix.select_router(igniter)

      case Igniter.Project.Module.find_module(igniter, router_module) do
        {:ok, {igniter, source, _zipper}} ->
          router_content = Rewrite.Source.get(source, :content)
          run_route_exists = String.contains?(router_content, "AshTypescriptRpcController, :run")

          validate_route_exists =
            String.contains?(router_content, "AshTypescriptRpcController, :validate")

          routes_to_add = []

          routes_to_add =
            if run_route_exists do
              routes_to_add
            else
              ["  post \"#{run_endpoint}\", AshTypescriptRpcController, :run" | routes_to_add]
            end

          routes_to_add =
            if validate_route_exists do
              routes_to_add
            else
              [
                "  post \"#{validate_endpoint}\", AshTypescriptRpcController, :validate"
                | routes_to_add
              ]
            end

          if routes_to_add != [] do
            routes_string = Enum.join(Enum.reverse(routes_to_add), "\n") <> "\n"

            igniter
            |> Igniter.Libs.Phoenix.append_to_scope("/", routes_string,
              arg2: web_module,
              placement: :after
            )
          else
            igniter
          end

        {:error, igniter} ->
          Igniter.add_warning(
            igniter,
            "Could not find router module #{inspect(router_module)}. " <>
              "Please manually add RPC routes to your router."
          )
      end
    end

    defp add_ash_typescript_config(igniter) do
      igniter
      |> Igniter.Project.Config.configure_new(
        "config.exs",
        :ash_typescript,
        [:output_file],
        "assets/js/ash_rpc.ts"
      )
      |> Igniter.Project.Config.configure_new(
        "config.exs",
        :ash_typescript,
        [:run_endpoint],
        "/rpc/run"
      )
      |> Igniter.Project.Config.configure_new(
        "config.exs",
        :ash_typescript,
        [:validate_endpoint],
        "/rpc/validate"
      )
      |> Igniter.Project.Config.configure_new(
        "config.exs",
        :ash_typescript,
        [:input_field_formatter],
        :camel_case
      )
      |> Igniter.Project.Config.configure_new(
        "config.exs",
        :ash_typescript,
        [:output_field_formatter],
        :camel_case
      )
      |> Igniter.Project.Config.configure_new(
        "config.exs",
        :ash_typescript,
        [:require_tenant_parameters],
        false
      )
      |> Igniter.Project.Config.configure_new(
        "config.exs",
        :ash_typescript,
        [:generate_zod_schemas],
        false
      )
      |> Igniter.Project.Config.configure_new(
        "config.exs",
        :ash_typescript,
        [:generate_phx_channel_rpc_actions],
        false
      )
      |> Igniter.Project.Config.configure_new(
        "config.exs",
        :ash_typescript,
        [:generate_validation_functions],
        true
      )
      |> Igniter.Project.Config.configure_new(
        "config.exs",
        :ash_typescript,
        [:zod_import_path],
        "zod"
      )
      |> Igniter.Project.Config.configure_new(
        "config.exs",
        :ash_typescript,
        [:zod_schema_suffix],
        "ZodSchema"
      )
      |> Igniter.Project.Config.configure_new(
        "config.exs",
        :ash_typescript,
        [:phoenix_import_path],
        "phoenix"
      )
    end

    defp create_package_json(igniter, "vite", framework) do
      update_package_json_with_framework(igniter, framework, "vite")
    end

    defp create_package_json(igniter, bundler, framework) do
      # For esbuild, ensure package.json exists with Phoenix deps,
      # then merge in framework-specific deps
      base_package_json =
        %{
          "dependencies" => %{
            "phoenix" => "file:../deps/phoenix",
            "phoenix_html" => "file:../deps/phoenix_html",
            "phoenix_live_view" => "file:../deps/phoenix_live_view",
            "topbar" => "^3.0.0"
          },
          "devDependencies" => %{
            "daisyui" => "^5.0.0"
          }
        }
        |> encode_pretty_json()

      igniter
      |> Igniter.create_or_update_file("assets/package.json", base_package_json, fn source ->
        source
      end)
      |> update_package_json_with_framework(framework, bundler)
      |> update_vendor_imports()
    end

    defp get_framework_deps("vue", "vite") do
      %{
        dependencies: %{
          "@tanstack/vue-query" => "^5.89.0",
          "@tanstack/vue-table" => "^8.21.3",
          "@tanstack/vue-virtual" => "^3.13.12",
          "vue" => "^3.5.16"
        },
        dev_dependencies: %{
          "@vitejs/plugin-vue" => "^5.2.4"
        }
      }
    end

    defp get_framework_deps("vue", _bundler) do
      %{
        dependencies: %{
          "@tanstack/vue-query" => "^5.89.0",
          "@tanstack/vue-table" => "^8.21.3",
          "@tanstack/vue-virtual" => "^3.13.12",
          "vue" => "^3.5.16"
        },
        dev_dependencies: %{
          "esbuild-plugin-vue3" => "^0.4.2"
        }
      }
    end

    defp get_framework_deps("svelte", "vite") do
      %{
        dependencies: %{
          "@tanstack/svelte-query" => "^5.89.0",
          "svelte" => "^5.33.0"
        },
        dev_dependencies: %{
          "@sveltejs/vite-plugin-svelte" => "^5.0.3"
        }
      }
    end

    defp get_framework_deps("svelte", _bundler) do
      %{
        dependencies: %{
          "@tanstack/svelte-query" => "^5.89.0",
          "svelte" => "^5.33.0"
        },
        dev_dependencies: %{
          "esbuild-svelte" => "^0.9.3"
        }
      }
    end

    defp get_framework_deps("react", "vite") do
      %{
        dependencies: %{
          "@tanstack/react-query" => "^5.89.0",
          "@tanstack/react-table" => "^8.21.3",
          "@tanstack/react-virtual" => "^3.13.12",
          "react" => "^19.1.1",
          "react-dom" => "^19.1.1"
        },
        dev_dependencies: %{
          "@types/react" => "^19.1.13",
          "@types/react-dom" => "^19.1.9",
          "@vitejs/plugin-react" => "^4.5.0"
        }
      }
    end

    defp get_framework_deps("react18", "vite") do
      %{
        dependencies: %{
          "@tanstack/react-query" => "^5.89.0",
          "@tanstack/react-table" => "^8.21.3",
          "@tanstack/react-virtual" => "^3.13.12",
          "react" => "^18.3.1",
          "react-dom" => "^18.3.1"
        },
        dev_dependencies: %{
          "@types/react" => "^18.3.23",
          "@types/react-dom" => "^18.3.7",
          "@vitejs/plugin-react" => "^4.5.0"
        }
      }
    end

    defp get_framework_deps("react", _bundler) do
      %{
        dependencies: %{
          "@tanstack/react-query" => "^5.89.0",
          "@tanstack/react-table" => "^8.21.3",
          "@tanstack/react-virtual" => "^3.13.12",
          "react" => "^19.1.1",
          "react-dom" => "^19.1.1"
        },
        dev_dependencies: %{
          "@types/react" => "^19.1.13",
          "@types/react-dom" => "^19.1.9"
        }
      }
    end

    defp get_framework_deps("react18", _bundler) do
      %{
        dependencies: %{
          "@tanstack/react-query" => "^5.89.0",
          "@tanstack/react-table" => "^8.21.3",
          "@tanstack/react-virtual" => "^3.13.12",
          "react" => "^18.3.1",
          "react-dom" => "^18.3.1"
        },
        dev_dependencies: %{
          "@types/react" => "^18.3.23",
          "@types/react-dom" => "^18.3.7"
        }
      }
    end

    defp update_vendor_imports(igniter) do
      # Update app.js to use npm imports instead of vendor paths
      igniter
      |> Igniter.update_file("assets/js/app.js", fn source ->
        Rewrite.Source.update(source, :content, fn content ->
          String.replace(content, "../vendor/topbar", "topbar")
        end)
      end)
      |> Igniter.update_file("assets/css/app.css", fn source ->
        Rewrite.Source.update(source, :content, fn content ->
          content
          |> String.replace("../vendor/daisyui-theme", "daisyui/theme")
          |> String.replace("../vendor/daisyui", "daisyui")
        end)
      end)
      |> delete_vendor_files()
    end

    defp delete_vendor_files(igniter) do
      # Delete vendor files except heroicons
      igniter
      |> Igniter.rm("assets/vendor/topbar.js")
      |> Igniter.rm("assets/vendor/daisyui.js")
      |> Igniter.rm("assets/vendor/daisyui-theme.js")
    end

    defp update_package_json_with_framework(igniter, framework, bundler) do
      deps = get_framework_deps(framework, bundler)

      update_package_json(igniter, fn package_json ->
        package_json
        |> merge_package_section("dependencies", deps.dependencies)
        |> merge_package_section("devDependencies", deps.dev_dependencies)
      end)
    end

    defp update_package_json(igniter, updater) do
      Igniter.update_file(igniter, "assets/package.json", fn source ->
        case Jason.decode(source.content) do
          {:ok, package_json} ->
            updated_package_json = updater.(package_json)

            if updated_package_json == package_json do
              source
            else
              Rewrite.Source.update(source, :content, encode_pretty_json(updated_package_json))
            end

          {:error, _error} ->
            source
        end
      end)
    end

    defp merge_package_section(package_json, section, deps) when is_map(deps) do
      current_deps = Map.get(package_json, section, %{})
      Map.put(package_json, section, Map.merge(current_deps, deps))
    end

    defp encode_pretty_json(data) do
      Jason.encode!(data, pretty: true) <> "\n"
    end

    defp create_index_page(igniter, "react18"), do: create_index_page(igniter, "react")

    defp create_index_page(igniter, "react") do
      page_body = get_react_page_body()

      react_index_content = """
      import React from "react";
      import { createRoot } from "react-dom/client";

      // Declare Prism for TypeScript
      declare global {
        interface Window {
          Prism: any;
        }
      }

      export default function App() {
        React.useEffect(() => {
          // Trigger Prism highlighting after component mounts
          if (window.Prism) {
            window.Prism.highlightAll();
          }
        }, []);

        return (
      #{page_body}
        );
      }

      const root = createRoot(document.getElementById("app")!);

      root.render(
        <React.StrictMode>
          <App />
        </React.StrictMode>,
      );
      """

      igniter
      |> Igniter.create_new_file("assets/js/index.tsx", react_index_content, on_exists: :warning)
    end

    defp create_index_page(igniter, "vue") do
      {script_content, template_content} = get_vue_page_content()

      vue_component = script_content <> "\n" <> template_content

      vue_index_content = """
      import { createApp } from "vue";
      import App from "./App.vue";

      const app = createApp(App);
      app.mount("#app");
      """

      igniter
      |> Igniter.create_new_file("assets/js/App.vue", vue_component, on_exists: :warning)
      |> Igniter.create_new_file("assets/js/index.ts", vue_index_content, on_exists: :warning)
    end

    defp create_index_page(igniter, "svelte") do
      {script_content, template_content} = get_svelte_page_content()

      svelte_component = script_content <> "\n" <> template_content

      svelte_index_content = """
      import App from "./App.svelte";
      import { mount } from "svelte";

      const app = mount(App, {
        target: document.getElementById("app")!,
      });

      export default app;
      """

      igniter
      |> Igniter.create_new_file("assets/js/App.svelte", svelte_component, on_exists: :warning)
      |> Igniter.create_new_file("assets/js/index.ts", svelte_index_content, on_exists: :warning)
    end

    defp update_tsconfig(igniter, framework) do
      igniter
      |> Igniter.update_file("assets/tsconfig.json", fn source ->
        content = source.content

        needs_jsx =
          framework in ["react", "react18"] and not String.contains?(content, ~s("jsx":))

        needs_interop = not String.contains?(content, ~s("esModuleInterop":))

        if needs_jsx or needs_interop do
          updated_content = content

          updated_content =
            if needs_jsx or needs_interop do
              case Regex.run(~r/"compilerOptions":\s*\{/, updated_content, return: :index) do
                [{start, length}] ->
                  insertion_point = start + length
                  before = String.slice(updated_content, 0, insertion_point)
                  after_text = String.slice(updated_content, insertion_point..-1//1)

                  options_to_add = []

                  options_to_add =
                    if needs_jsx,
                      do: [~s(\n    "jsx": "react-jsx",) | options_to_add],
                      else: options_to_add

                  options_to_add =
                    if needs_interop,
                      do: [~s(\n    "esModuleInterop": true,) | options_to_add],
                      else: options_to_add

                  before <> Enum.join(options_to_add, "") <> after_text

                nil ->
                  updated_content
              end
            else
              updated_content
            end

          Rewrite.Source.update(source, :content, updated_content)
        else
          source
        end
      end)
    end

    defp update_esbuild_config(igniter, app_name, use_bun, framework) do
      npm_install_task =
        if use_bun, do: "ash_typescript.npm_install --bun", else: "ash_typescript.npm_install"

      entry_file = get_entry_file(framework)

      igniter
      |> Igniter.Project.TaskAliases.add_alias("assets.setup", npm_install_task,
        if_exists: :append
      )
      |> Igniter.update_elixir_file("config/config.exs", fn zipper ->
        is_esbuild_node = fn
          {:config, _, [{:__block__, _, [:esbuild]} | _rest]} -> true
          _ -> false
        end

        is_app_node = fn
          {{:__block__, _, [^app_name]}, _} -> true
          _ -> false
        end

        {:ok, zipper} =
          Igniter.Code.Common.move_to(zipper, fn zipper ->
            zipper
            |> Sourceror.Zipper.node()
            |> is_esbuild_node.()
          end)

        {:ok, zipper} =
          Igniter.Code.Common.move_to(zipper, fn zipper ->
            zipper
            |> Sourceror.Zipper.node()
            |> is_app_node.()
          end)

        is_args_node = fn
          {{:__block__, _, [:args]}, {:sigil_w, _, _}} -> true
          _ -> false
        end

        {:ok, zipper} =
          Igniter.Code.Common.move_to(zipper, fn zipper ->
            zipper
            |> Sourceror.Zipper.node()
            |> is_args_node.()
          end)

        args_node = Sourceror.Zipper.node(zipper)

        case args_node do
          {{:__block__, block_meta, [:args]},
           {:sigil_w, sigil_meta, [{:<<>>, string_meta, [args_string]}, sigil_opts]}} ->
            # Add entry file and change output dir from /assets/js to /assets
            new_args_string =
              if String.contains?(args_string, entry_file) do
                args_string
              else
                entry_file <> " " <> args_string
              end

            # Change output directory from assets/js to assets (flat output like build.js)
            new_args_string =
              String.replace(
                new_args_string,
                "--outdir=../priv/static/assets/js",
                "--outdir=../priv/static/assets"
              )

            # Add code splitting flags for module support (CSS imported via JS)
            new_args_string =
              if String.contains?(new_args_string, "--splitting") do
                new_args_string
              else
                new_args_string <> " --splitting"
              end

            new_args_string =
              if String.contains?(new_args_string, "--format=esm") do
                new_args_string
              else
                new_args_string <> " --format=esm"
              end

            new_args_node =
              {{:__block__, block_meta, [:args]},
               {:sigil_w, sigil_meta, [{:<<>>, string_meta, [new_args_string]}, sigil_opts]}}

            Sourceror.Zipper.replace(zipper, new_args_node)

          _ ->
            zipper
        end
      end)
    end

    defp get_entry_file("react"), do: "js/index.tsx"
    defp get_entry_file("react18"), do: "js/index.tsx"
    defp get_entry_file("vue"), do: "js/index.ts"
    defp get_entry_file("svelte"), do: "js/index.ts"
    defp get_entry_file(_), do: "js/index.ts"

    defp create_esbuild_script(igniter, "vue") do
      build_script = """
      const esbuild = require("esbuild");
      const vuePlugin = require("esbuild-plugin-vue3");
      const path = require("path");

      const args = process.argv.slice(2);
      const watch = args.includes("--watch");
      const deploy = args.includes("--deploy");

      const loader = {
        ".js": "js",
        ".ts": "ts",
        ".tsx": "tsx",
        ".css": "css",
        ".json": "json",
        ".svg": "file",
        ".png": "file",
        ".jpg": "file",
        ".gif": "file",
      };

      const plugins = [vuePlugin()];

      let opts = {
        entryPoints: ["js/index.ts", "js/app.js"],
        bundle: true,
        target: "es2020",
        outdir: "../priv/static/assets",
        logLevel: "info",
        loader,
        plugins,
        nodePaths: ["../deps", ...(process.env.NODE_PATH ? process.env.NODE_PATH.split(path.delimiter) : [])],
        splitting: true,
        format: "esm",
      };

      if (deploy) {
        opts = {
          ...opts,
          minify: true,
        };
      }

      if (watch) {
        opts = {
          ...opts,
          sourcemap: "linked",
        };
        esbuild.context(opts).then((ctx) => {
          ctx.watch();
        });
      } else {
        esbuild.build(opts);
      }
      """

      igniter
      |> Igniter.create_new_file("assets/build.js", build_script, on_exists: :warning)
    end

    defp create_esbuild_script(igniter, "svelte") do
      build_script = """
      const esbuild = require("esbuild");
      const sveltePlugin = require("esbuild-svelte");
      const path = require("path");

      const args = process.argv.slice(2);
      const watch = args.includes("--watch");
      const deploy = args.includes("--deploy");

      const loader = {
        ".js": "js",
        ".ts": "ts",
        ".tsx": "tsx",
        ".css": "css",
        ".json": "json",
        ".svg": "file",
        ".png": "file",
        ".jpg": "file",
        ".gif": "file",
      };

      const plugins = [
        sveltePlugin({
          compilerOptions: { css: "injected" },
        }),
      ];

      let opts = {
        entryPoints: ["js/index.ts", "js/app.js"],
        bundle: true,
        target: "es2020",
        outdir: "../priv/static/assets",
        logLevel: "info",
        loader,
        plugins,
        nodePaths: ["../deps", ...(process.env.NODE_PATH ? process.env.NODE_PATH.split(path.delimiter) : [])],
        mainFields: ["svelte", "browser", "module", "main"],
        conditions: ["svelte", "browser"],
        splitting: true,
        format: "esm",
      };

      if (deploy) {
        opts = {
          ...opts,
          minify: true,
        };
      }

      if (watch) {
        opts = {
          ...opts,
          sourcemap: "linked",
        };
        esbuild.context(opts).then((ctx) => {
          ctx.watch();
        });
      } else {
        esbuild.build(opts);
      }
      """

      igniter
      |> Igniter.create_new_file("assets/build.js", build_script, on_exists: :warning)
    end

    defp update_esbuild_config_with_script(igniter, app_name, use_bun, _framework) do
      npm_install_task =
        if use_bun, do: "ash_typescript.npm_install --bun", else: "ash_typescript.npm_install"

      # For Vue/Svelte we use a custom build.js with esbuild's JS API (needed for plugins).
      # The vendored esbuild Elixir package is no longer needed since esbuild is installed
      # via npm instead, so we remove the vendored config and dep to avoid confusion.
      # We need to:
      # 1. Add esbuild as an npm dependency (replaces the vendored Elixir esbuild package)
      # 2. Remove the vendored esbuild config from config.exs
      # 3. Remove the :esbuild dep from mix.exs
      # 4. Update dev.exs watchers to use node/bun build.js --watch
      # 5. Update assets.setup/build/deploy aliases

      igniter
      |> add_esbuild_npm_dep()
      |> Igniter.Project.Config.remove_application_configuration("config.exs", :esbuild)
      |> Igniter.Project.Deps.remove_dep(:esbuild)
      |> remove_esbuild_install_from_assets_setup()
      |> Igniter.Project.TaskAliases.add_alias("assets.setup", npm_install_task,
        if_exists: :append
      )
      |> update_dev_watcher_for_build_script(app_name, use_bun)
      |> update_build_aliases_for_script(app_name, use_bun)
    end

    defp remove_esbuild_install_from_assets_setup(igniter) do
      Igniter.Project.TaskAliases.modify_existing_alias(igniter, "assets.setup", fn zipper ->
        Igniter.Code.List.remove_from_list(zipper, fn item_zipper ->
          case Sourceror.Zipper.node(item_zipper) do
            {:__block__, _, [str]} when is_binary(str) ->
              String.contains?(str, "esbuild.install")

            str when is_binary(str) ->
              String.contains?(str, "esbuild.install")

            _ ->
              false
          end
        end)
      end)
    end

    defp add_esbuild_npm_dep(igniter) do
      update_package_json(igniter, fn package_json ->
        merge_package_section(package_json, "devDependencies", %{"esbuild" => "^0.24.0"})
      end)
    end

    defp update_dev_watcher_for_build_script(igniter, app_name, use_bun) do
      runner = if use_bun, do: "bun", else: "node"

      {igniter, endpoint} = Igniter.Libs.Phoenix.select_endpoint(igniter)

      endpoint =
        case endpoint do
          nil ->
            # Fallback: construct the endpoint module name from the web module
            web_module = Igniter.Libs.Phoenix.web_module(igniter)
            Module.concat(web_module, Endpoint)

          endpoint ->
            endpoint
        end

      Igniter.Project.Config.configure(
        igniter,
        "dev.exs",
        app_name,
        [endpoint, :watchers],
        {:code,
         Sourceror.parse_string!("""
         [
           #{runner}: ["build.js", "--watch",
             cd: Path.expand("../assets", __DIR__),
             env: %{"NODE_PATH" => Enum.join([Path.expand("../deps", __DIR__), Mix.Project.build_path()], ":")}
           ],
           tailwind: {Tailwind, :install_and_run, [:#{app_name}, ~w(--watch)]}
         ]
         """)},
        updater: fn zipper ->
          {:ok,
           Igniter.Code.Common.replace_code(
             zipper,
             Sourceror.parse_string!("""
             [
               #{runner}: ["build.js", "--watch",
                 cd: Path.expand("../assets", __DIR__),
                 env: %{"NODE_PATH" => Enum.join([Path.expand("../deps", __DIR__), Mix.Project.build_path()], ":")}
               ],
               tailwind: {Tailwind, :install_and_run, [:#{app_name}, ~w(--watch)]}
             ]
             """)
           )}
        end
      )
    end

    defp update_build_aliases_for_script(igniter, app_name, use_bun) do
      runner = if use_bun, do: "bun", else: "node"

      igniter
      |> Igniter.Project.TaskAliases.modify_existing_alias("assets.build", fn zipper ->
        alias_code =
          Sourceror.parse_string!(
            ~s|["tailwind #{app_name}", "cmd --cd assets #{runner} build.js"]|
          )

        {:ok, Igniter.Code.Common.replace_code(zipper, alias_code)}
      end)
      |> Igniter.Project.TaskAliases.modify_existing_alias("assets.deploy", fn zipper ->
        alias_code =
          Sourceror.parse_string!(
            ~s|["tailwind #{app_name} --minify", "cmd --cd assets #{runner} build.js --deploy"]|
          )

        {:ok, Igniter.Code.Common.replace_code(zipper, alias_code)}
      end)
    end

    defp update_vite_config_with_framework(igniter, "vue") do
      Igniter.update_file(igniter, "assets/vite.config.mjs", fn source ->
        content = source.content

        if String.contains?(content, "@vitejs/plugin-vue") do
          source
        else
          updated_content =
            content
            |> String.replace(
              ~s|import { defineConfig } from 'vite'|,
              ~s|import { defineConfig } from 'vite'\nimport vue from '@vitejs/plugin-vue'|
            )
            |> String.replace(
              ~s|plugins: [|,
              ~s|plugins: [\n    vue(),|
            )
            # Add js/index.ts to vite input for production builds
            |> String.replace(
              ~s|input: ["js/app.js"|,
              ~s|input: ["js/index.ts", "js/app.js"|
            )

          Rewrite.Source.update(source, :content, updated_content)
        end
      end)
    end

    defp update_vite_config_with_framework(igniter, "svelte") do
      Igniter.update_file(igniter, "assets/vite.config.mjs", fn source ->
        content = source.content

        if String.contains?(content, "@sveltejs/vite-plugin-svelte") do
          source
        else
          updated_content =
            content
            |> String.replace(
              ~s|import { defineConfig } from 'vite'|,
              ~s|import { defineConfig } from 'vite'\nimport { svelte } from '@sveltejs/vite-plugin-svelte'|
            )
            |> String.replace(
              ~s|plugins: [|,
              ~s|plugins: [\n    svelte(),|
            )
            # Add js/index.ts to vite input for production builds
            |> String.replace(
              ~s|input: ["js/app.js"|,
              ~s|input: ["js/index.ts", "js/app.js"|
            )

          Rewrite.Source.update(source, :content, updated_content)
        end
      end)
    end

    defp update_vite_config_with_framework(igniter, "react") do
      Igniter.update_file(igniter, "assets/vite.config.mjs", fn source ->
        content = source.content

        if String.contains?(content, "@vitejs/plugin-react") do
          source
        else
          updated_content =
            content
            |> String.replace(
              ~s|import { defineConfig } from 'vite'|,
              ~s|import { defineConfig } from 'vite'\nimport react from '@vitejs/plugin-react'|
            )
            |> String.replace(
              ~s|plugins: [|,
              ~s|plugins: [\n    react(),|
            )
            # Add js/index.tsx to vite input for production builds
            |> String.replace(
              ~s|input: ["js/app.js"|,
              ~s|input: ["js/index.tsx", "js/app.js"|
            )

          Rewrite.Source.update(source, :content, updated_content)
        end
      end)
    end

    defp render_install_template(template_name, replacements \\ %{}) do
      priv_dir =
        case :code.priv_dir(:ash_typescript) do
          path when is_list(path) -> to_string(path)
          {:error, _reason} -> Path.expand("../../../priv", __DIR__)
        end

      template =
        priv_dir
        |> Path.join("templates/install/#{template_name}")
        |> File.read!()

      Enum.reduce(replacements, template, fn {placeholder, value}, acc ->
        String.replace(acc, placeholder, value)
      end)
    end

    # Create spa_root.html.heex layout for vite + react (includes React Refresh preamble)
    defp create_spa_root_layout(igniter, web_module, "vite", framework)
         when framework in ["react", "react18"] do
      app_name = Igniter.Project.Application.app_name(igniter)
      clean_web_module = web_module |> to_string() |> String.replace_prefix("Elixir.", "")
      web_path = Macro.underscore(clean_web_module)
      layout_path = "lib/#{web_path}/components/layouts/spa_root.html.heex"

      layout_content =
        render_install_template("spa_root_vite_react.html.heex", %{
          "__WEB_MODULE__" => clean_web_module,
          "__APP_NAME__" => to_string(app_name)
        })

      igniter
      |> Igniter.create_new_file(layout_path, layout_content, on_exists: :warning)
    end

    # Create spa_root.html.heex layout for vite + vue/svelte (no React Refresh needed)
    defp create_spa_root_layout(igniter, web_module, "vite", _framework) do
      app_name = Igniter.Project.Application.app_name(igniter)
      clean_web_module = web_module |> to_string() |> String.replace_prefix("Elixir.", "")
      web_path = Macro.underscore(clean_web_module)
      layout_path = "lib/#{web_path}/components/layouts/spa_root.html.heex"

      layout_content =
        render_install_template("spa_root_vite.html.heex", %{
          "__WEB_MODULE__" => clean_web_module,
          "__APP_NAME__" => to_string(app_name)
        })

      igniter
      |> Igniter.create_new_file(layout_path, layout_content, on_exists: :warning)
    end

    # Create spa_root.html.heex layout for esbuild (SPA pages)
    defp create_spa_root_layout(igniter, web_module, "esbuild", _framework) do
      clean_web_module = web_module |> to_string() |> String.replace_prefix("Elixir.", "")
      web_path = Macro.underscore(clean_web_module)
      layout_path = "lib/#{web_path}/components/layouts/spa_root.html.heex"

      layout_content = render_install_template("spa_root_esbuild.html.heex")

      igniter
      |> Igniter.create_new_file(layout_path, layout_content, on_exists: :warning)
    end

    defp create_spa_root_layout(igniter, _web_module, _bundler, _framework), do: igniter

    # Update root.html.heex for esbuild ESM output
    # Since esbuild outdir changes from /assets/js to /assets, we need to:
    # 1. Update the JS path from /assets/js/app.js to /assets/app.js
    # 2. Change script type from text/javascript to module (for ESM format)
    defp update_root_layout_for_esbuild(igniter) do
      web_module = Igniter.Libs.Phoenix.web_module(igniter)
      clean_web_module = web_module |> to_string() |> String.replace_prefix("Elixir.", "")
      web_path = Macro.underscore(clean_web_module)
      root_layout_path = "lib/#{web_path}/components/layouts/root.html.heex"

      igniter
      |> Igniter.update_file(root_layout_path, fn source ->
        content = source.content

        updated_content =
          content
          # Update JS path: /assets/js/app.js -> /assets/app.js
          |> String.replace(
            ~s|src={~p"/assets/js/app.js"}|,
            ~s|src={~p"/assets/app.js"}|
          )
          # Update script type: text/javascript -> module (for ESM)
          |> String.replace(
            ~s|type="text/javascript"|,
            ~s|type="module"|
          )

        if content == updated_content do
          source
        else
          Rewrite.Source.update(source, :content, updated_content)
        end
      end)
    end

    # For vite, use put_root_layout to use spa_root layout
    defp create_or_update_page_controller(igniter, web_module, "vite") do
      clean_web_module = web_module |> to_string() |> String.replace_prefix("Elixir.", "")

      controller_path =
        clean_web_module
        |> String.replace_suffix("Web", "")
        |> Macro.underscore()

      page_controller_path = "lib/#{controller_path}_web/controllers/page_controller.ex"

      page_controller_content = """
      defmodule #{clean_web_module}.PageController do
        use #{clean_web_module}, :controller

        def index(conn, _params) do
          conn
          |> put_root_layout(html: {#{clean_web_module}.Layouts, :spa_root})
          |> render(:index)
        end
      end
      """

      case Igniter.exists?(igniter, page_controller_path) do
        false ->
          igniter
          |> Igniter.create_new_file(page_controller_path, page_controller_content)

        true ->
          igniter
          |> Igniter.update_elixir_file(page_controller_path, fn zipper ->
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
                              conn
                              |> put_root_layout(
                                html:
                                  {unquote(Module.concat([clean_web_module, Layouts])), :spa_root}
                              )
                              |> render(:index)
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

    # For esbuild, use simple render without layout change
    # For esbuild, use put_root_layout to switch to spa_root layout
    defp create_or_update_page_controller(igniter, web_module, "esbuild") do
      clean_web_module = web_module |> to_string() |> String.replace_prefix("Elixir.", "")

      controller_path =
        clean_web_module
        |> String.replace_suffix("Web", "")
        |> Macro.underscore()

      page_controller_path = "lib/#{controller_path}_web/controllers/page_controller.ex"

      page_controller_content = """
      defmodule #{clean_web_module}.PageController do
        use #{clean_web_module}, :controller

        def index(conn, _params) do
          conn
          |> put_root_layout(html: {#{clean_web_module}.Layouts, :spa_root})
          |> render(:index)
        end
      end
      """

      case Igniter.exists?(igniter, page_controller_path) do
        false ->
          igniter
          |> Igniter.create_new_file(page_controller_path, page_controller_content)

        true ->
          igniter
          |> Igniter.update_elixir_file(page_controller_path, fn zipper ->
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
                              conn
                              |> put_root_layout(
                                html:
                                  {unquote(Module.concat([clean_web_module, Layouts])), :spa_root}
                              )
                              |> render(:index)
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

    defp create_or_update_page_controller(igniter, web_module, _bundler) do
      clean_web_module = web_module |> to_string() |> String.replace_prefix("Elixir.", "")

      controller_path =
        clean_web_module
        |> String.replace_suffix("Web", "")
        |> Macro.underscore()

      page_controller_path = "lib/#{controller_path}_web/controllers/page_controller.ex"

      page_controller_content = """
      defmodule #{clean_web_module}.PageController do
        use #{clean_web_module}, :controller

        def index(conn, _params) do
          render(conn, :index)
        end
      end
      """

      case Igniter.exists?(igniter, page_controller_path) do
        false ->
          igniter
          |> Igniter.create_new_file(page_controller_path, page_controller_content)

        true ->
          igniter
          |> Igniter.update_elixir_file(page_controller_path, fn zipper ->
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
                              render(conn, :index)
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

    defp create_index_template(igniter, web_module, "vite", _framework) do
      clean_web_module = web_module |> to_string() |> String.replace_prefix("Elixir.", "")
      web_path = Macro.underscore(clean_web_module)
      index_template_path = "lib/#{web_path}/controllers/page_html/index.html.heex"

      # For vite, assets are loaded via spa_root.html.heex layout
      # This template just needs the app mount point
      index_template_content = """
      <div id="app"></div>
      """

      igniter
      |> Igniter.create_new_file(index_template_path, index_template_content, on_exists: :warning)
    end

    defp create_index_template(igniter, web_module, "esbuild", _framework) do
      clean_web_module = web_module |> to_string() |> String.replace_prefix("Elixir.", "")
      web_path = Macro.underscore(clean_web_module)
      index_template_path = "lib/#{web_path}/controllers/page_html/index.html.heex"

      # For esbuild, assets are loaded via spa_root.html.heex layout
      # This template just needs the app mount point
      index_template_content = """
      <div id="app"></div>
      """

      igniter
      |> Igniter.create_new_file(index_template_path, index_template_content, on_exists: :warning)
    end

    defp create_index_template(igniter, web_module, _bundler, _framework) do
      clean_web_module = web_module |> to_string() |> String.replace_prefix("Elixir.", "")
      web_path = Macro.underscore(clean_web_module)
      index_template_path = "lib/#{web_path}/controllers/page_html/index.html.heex"

      # Default template for other bundlers
      index_template_content = """
      <link href="https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/themes/prism-tomorrow.min.css" rel="stylesheet" />
      <script src="https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/components/prism-core.min.js"></script>
      <script src="https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/plugins/autoloader/prism-autoloader.min.js"></script>

      <div id="app"></div>
      <script defer phx-track-static type="text/javascript" src={~p"/assets/index.js"}>
      </script>
      """

      igniter
      |> Igniter.create_new_file(index_template_path, index_template_content, on_exists: :warning)
    end

    defp add_page_index_route(igniter, web_module) do
      {igniter, router_module} = Igniter.Libs.Phoenix.select_router(igniter)

      case Igniter.Project.Module.find_module(igniter, router_module) do
        {:ok, {igniter, source, _zipper}} ->
          router_content = Rewrite.Source.get(source, :content)
          route_exists = String.contains?(router_content, "get \"/ash-typescript\"")

          if route_exists do
            igniter
          else
            route_string = "  get \"/ash-typescript\", PageController, :index"

            igniter
            |> Igniter.Libs.Phoenix.append_to_scope("/", route_string,
              arg2: web_module,
              placement: :after
            )
          end

        {:error, igniter} ->
          Igniter.add_warning(
            igniter,
            "Could not find router module #{inspect(router_module)}. " <>
              "Please manually add the /ash-typescript route to your router."
          )
      end
    end

    defp function_named?(zipper, name, arity) do
      case Sourceror.Zipper.node(zipper) do
        {:def, _, [{^name, _, args}, _]} when length(args) == arity -> true
        _ -> false
      end
    end

    # ---- Inertia.js Support Functions ----

    # Add {:inertia, "~> 2.6.0"} to mix.exs
    defp add_inertia_dep(igniter) do
      Igniter.Project.Deps.add_dep(igniter, {:inertia, "~> 2.6.0"})
    end

    # Add @inertiajs/react (or vue/svelte) npm dependency to package.json
    defp add_inertia_deps(igniter, framework) do
      inertia_pkg = get_inertia_npm_package(framework)

      update_package_json(igniter, fn package_json ->
        merge_package_section(package_json, "dependencies", %{inertia_pkg => "^2.0.0"})
      end)
    end

    defp get_inertia_npm_package(framework) when framework in ["react", "react18"],
      do: "@inertiajs/react"

    defp get_inertia_npm_package("vue"), do: "@inertiajs/vue3"
    defp get_inertia_npm_package("svelte"), do: "@inertiajs/svelte"
    defp get_inertia_npm_package(_), do: "@inertiajs/react"

    # Add config :inertia block to config.exs
    defp add_inertia_config(igniter, web_module) do
      clean_web_module = web_module |> to_string() |> String.replace_prefix("Elixir.", "")

      igniter
      |> Igniter.Project.Config.configure_new(
        "config.exs",
        :inertia,
        [:endpoint],
        {:code, Sourceror.parse_string!("#{clean_web_module}.Endpoint")}
      )
      |> Igniter.Project.Config.configure_new(
        "config.exs",
        :inertia,
        [:static_paths],
        ["/assets/inertia.js"]
      )
      |> Igniter.Project.Config.configure_new(
        "config.exs",
        :inertia,
        [:default_version],
        "1"
      )
      |> Igniter.Project.Config.configure_new(
        "config.exs",
        :inertia,
        [:camelize_props],
        false
      )
    end

    # Add import Inertia.Controller to controller helper and import Inertia.HTML to html helper
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

        # Add import Inertia.Controller to the controller function
        updated_content =
          if String.contains?(web_content, "Inertia.Controller") do
            web_content
          else
            String.replace(
              web_content,
              "import Plug.Conn\n\n      unquote(verified_routes())",
              "import Plug.Conn\n      import Inertia.Controller\n\n      unquote(verified_routes())"
            )
          end

        # Add import Inertia.HTML to the html_helpers function
        updated_content =
          if String.contains?(updated_content, "Inertia.HTML") do
            updated_content
          else
            String.replace(
              updated_content,
              "import Phoenix.HTML",
              "import Phoenix.HTML\n      import Inertia.HTML"
            )
          end

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

    # Add plug Inertia.Plug to the browser pipeline in router
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

              # Insert plug Inertia.Plug after plug :put_secure_browser_headers
              # It must come after fetch_session, protect_from_forgery, etc.
              updated_content =
                String.replace(
                  content,
                  "plug :put_secure_browser_headers",
                  "plug :put_secure_browser_headers\n    plug Inertia.Plug"
                )

              if content == updated_content do
                source
              else
                Rewrite.Source.update(source, :content, updated_content)
              end
            end)
          end

        {:error, igniter} ->
          Igniter.add_warning(
            igniter,
            "Could not find router module #{inspect(router_module)}. " <>
              "Please manually add `plug Inertia.Plug` to your browser pipeline."
          )
      end
    end

    # Setup framework bundler for inertia (handles inertia entry point instead of index entry point)
    defp setup_framework_bundler_for_inertia(igniter, app_name, "esbuild", use_bun, framework)
         when framework in ["vue", "svelte"] do
      # Vue and Svelte need custom build scripts with esbuild plugins
      # For Inertia, we add inertia entry point to build.js
      igniter
      |> create_esbuild_script_for_inertia(framework)
      |> update_esbuild_config_with_script(app_name, use_bun, framework)
      |> update_root_layout_for_esbuild()
    end

    defp setup_framework_bundler_for_inertia(igniter, app_name, "esbuild", use_bun, framework) do
      # React/React18 use vendored esbuild CLI directly
      igniter
      |> update_esbuild_config_for_inertia(app_name, use_bun, framework)
      |> update_root_layout_for_esbuild()
    end

    defp setup_framework_bundler_for_inertia(igniter, _app_name, "vite", _use_bun, framework)
         when framework in ["vue", "svelte"] do
      igniter
      |> add_vite_framework_plugin(framework)
      |> update_vite_config_for_inertia(framework)
    end

    defp setup_framework_bundler_for_inertia(igniter, _app_name, "vite", _use_bun, framework)
         when framework in ["react", "react18"] do
      igniter
      |> add_vite_framework_plugin("react")
      |> update_vite_config_for_inertia(framework)
    end

    defp setup_framework_bundler_for_inertia(igniter, _app_name, "vite", _use_bun, _framework),
      do: igniter

    # Update esbuild config for Inertia (adds inertia entry file instead of index)
    defp update_esbuild_config_for_inertia(igniter, app_name, use_bun, framework) do
      npm_install_task =
        if use_bun, do: "ash_typescript.npm_install --bun", else: "ash_typescript.npm_install"

      entry_file = get_inertia_entry_file(framework)

      igniter
      |> Igniter.Project.TaskAliases.add_alias("assets.setup", npm_install_task,
        if_exists: :append
      )
      |> Igniter.update_elixir_file("config/config.exs", fn zipper ->
        is_esbuild_node = fn
          {:config, _, [{:__block__, _, [:esbuild]} | _rest]} -> true
          _ -> false
        end

        is_app_node = fn
          {{:__block__, _, [^app_name]}, _} -> true
          _ -> false
        end

        {:ok, zipper} =
          Igniter.Code.Common.move_to(zipper, fn zipper ->
            zipper
            |> Sourceror.Zipper.node()
            |> is_esbuild_node.()
          end)

        {:ok, zipper} =
          Igniter.Code.Common.move_to(zipper, fn zipper ->
            zipper
            |> Sourceror.Zipper.node()
            |> is_app_node.()
          end)

        is_args_node = fn
          {{:__block__, _, [:args]}, {:sigil_w, _, _}} -> true
          _ -> false
        end

        {:ok, zipper} =
          Igniter.Code.Common.move_to(zipper, fn zipper ->
            zipper
            |> Sourceror.Zipper.node()
            |> is_args_node.()
          end)

        args_node = Sourceror.Zipper.node(zipper)

        case args_node do
          {{:__block__, block_meta, [:args]},
           {:sigil_w, sigil_meta, [{:<<>>, string_meta, [args_string]}, sigil_opts]}} ->
            # Add inertia entry file
            new_args_string =
              if String.contains?(args_string, entry_file) do
                args_string
              else
                entry_file <> " " <> args_string
              end

            # Change output directory from assets/js to assets
            new_args_string =
              String.replace(
                new_args_string,
                "--outdir=../priv/static/assets/js",
                "--outdir=../priv/static/assets"
              )

            # Add code splitting flags
            new_args_string =
              if String.contains?(new_args_string, "--splitting") do
                new_args_string
              else
                new_args_string <> " --splitting"
              end

            new_args_string =
              if String.contains?(new_args_string, "--format=esm") do
                new_args_string
              else
                new_args_string <> " --format=esm"
              end

            new_args_node =
              {{:__block__, block_meta, [:args]},
               {:sigil_w, sigil_meta, [{:<<>>, string_meta, [new_args_string]}, sigil_opts]}}

            Sourceror.Zipper.replace(zipper, new_args_node)

          _ ->
            zipper
        end
      end)
    end

    defp get_inertia_entry_file(framework) when framework in ["react", "react18"],
      do: "js/inertia.tsx"

    defp get_inertia_entry_file(_), do: "js/inertia.ts"

    # Create esbuild build.js for Vue/Svelte with Inertia entry point
    defp create_esbuild_script_for_inertia(igniter, "vue") do
      build_script = """
      const esbuild = require("esbuild");
      const vuePlugin = require("esbuild-plugin-vue3");
      const path = require("path");

      const args = process.argv.slice(2);
      const watch = args.includes("--watch");
      const deploy = args.includes("--deploy");

      const loader = {
        ".js": "js",
        ".ts": "ts",
        ".tsx": "tsx",
        ".css": "css",
        ".json": "json",
        ".svg": "file",
        ".png": "file",
        ".jpg": "file",
        ".gif": "file",
      };

      const plugins = [vuePlugin()];

      let opts = {
        entryPoints: ["js/inertia.ts", "js/app.js"],
        bundle: true,
        target: "es2020",
        outdir: "../priv/static/assets",
        logLevel: "info",
        loader,
        plugins,
        nodePaths: ["../deps", ...(process.env.NODE_PATH ? process.env.NODE_PATH.split(path.delimiter) : [])],
        splitting: true,
        format: "esm",
      };

      if (deploy) {
        opts = {
          ...opts,
          minify: true,
        };
      }

      if (watch) {
        opts = {
          ...opts,
          sourcemap: "linked",
        };
        esbuild.context(opts).then((ctx) => {
          ctx.watch();
        });
      } else {
        esbuild.build(opts);
      }
      """

      igniter
      |> Igniter.create_new_file("assets/build.js", build_script, on_exists: :warning)
    end

    defp create_esbuild_script_for_inertia(igniter, "svelte") do
      build_script = """
      const esbuild = require("esbuild");
      const sveltePlugin = require("esbuild-svelte");
      const path = require("path");

      const args = process.argv.slice(2);
      const watch = args.includes("--watch");
      const deploy = args.includes("--deploy");

      const loader = {
        ".js": "js",
        ".ts": "ts",
        ".tsx": "tsx",
        ".css": "css",
        ".json": "json",
        ".svg": "file",
        ".png": "file",
        ".jpg": "file",
        ".gif": "file",
      };

      const plugins = [
        sveltePlugin({
          compilerOptions: { css: "injected" },
        }),
      ];

      let opts = {
        entryPoints: ["js/inertia.ts", "js/app.js"],
        bundle: true,
        target: "es2020",
        outdir: "../priv/static/assets",
        logLevel: "info",
        loader,
        plugins,
        nodePaths: ["../deps", ...(process.env.NODE_PATH ? process.env.NODE_PATH.split(path.delimiter) : [])],
        mainFields: ["svelte", "browser", "module", "main"],
        conditions: ["svelte", "browser"],
        splitting: true,
        format: "esm",
      };

      if (deploy) {
        opts = {
          ...opts,
          minify: true,
        };
      }

      if (watch) {
        opts = {
          ...opts,
          sourcemap: "linked",
        };
        esbuild.context(opts).then((ctx) => {
          ctx.watch();
        });
      } else {
        esbuild.build(opts);
      }
      """

      igniter
      |> Igniter.create_new_file("assets/build.js", build_script, on_exists: :warning)
    end

    # Add inertia entry point to vite config
    defp update_vite_config_for_inertia(igniter, framework) do
      inertia_entry = get_inertia_entry_file(framework)

      Igniter.update_file(igniter, "assets/vite.config.mjs", fn source ->
        content = source.content

        if String.contains?(content, inertia_entry) do
          source
        else
          # Add inertia entry point to vite input array
          updated_content =
            String.replace(
              content,
              ~s|input: ["js/app.js"|,
              ~s|input: ["#{inertia_entry}", "js/app.js"|
            )

          Rewrite.Source.update(source, :content, updated_content)
        end
      end)
    end

    # Add vite framework plugin (import + plugin entry) WITHOUT adding an SPA entry point.
    # Used by the Inertia flow which has its own entry point (js/inertia.tsx).
    defp add_vite_framework_plugin(igniter, "vue") do
      Igniter.update_file(igniter, "assets/vite.config.mjs", fn source ->
        content = source.content

        if String.contains?(content, "@vitejs/plugin-vue") do
          source
        else
          updated_content =
            content
            |> String.replace(
              ~s|import { defineConfig } from 'vite'|,
              ~s|import { defineConfig } from 'vite'\nimport vue from '@vitejs/plugin-vue'|
            )
            |> String.replace(
              ~s|plugins: [|,
              ~s|plugins: [\n    vue(),|
            )

          Rewrite.Source.update(source, :content, updated_content)
        end
      end)
    end

    defp add_vite_framework_plugin(igniter, "svelte") do
      Igniter.update_file(igniter, "assets/vite.config.mjs", fn source ->
        content = source.content

        if String.contains?(content, "@sveltejs/vite-plugin-svelte") do
          source
        else
          updated_content =
            content
            |> String.replace(
              ~s|import { defineConfig } from 'vite'|,
              ~s|import { defineConfig } from 'vite'\nimport { svelte } from '@sveltejs/vite-plugin-svelte'|
            )
            |> String.replace(
              ~s|plugins: [|,
              ~s|plugins: [\n    svelte(),|
            )

          Rewrite.Source.update(source, :content, updated_content)
        end
      end)
    end

    defp add_vite_framework_plugin(igniter, "react") do
      Igniter.update_file(igniter, "assets/vite.config.mjs", fn source ->
        content = source.content

        if String.contains?(content, "@vitejs/plugin-react") do
          source
        else
          updated_content =
            content
            |> String.replace(
              ~s|import { defineConfig } from 'vite'|,
              ~s|import { defineConfig } from 'vite'\nimport react from '@vitejs/plugin-react'|
            )
            |> String.replace(
              ~s|plugins: [|,
              ~s|plugins: [\n    react(),|
            )

          Rewrite.Source.update(source, :content, updated_content)
        end
      end)
    end

    # Create inertia_root.html.heex layout for vite + react (includes React Refresh preamble)
    defp create_inertia_root_layout(igniter, web_module, "vite", framework)
         when framework in ["react", "react18"] do
      app_name = Igniter.Project.Application.app_name(igniter)
      clean_web_module = web_module |> to_string() |> String.replace_prefix("Elixir.", "")
      web_path = Macro.underscore(clean_web_module)
      layout_path = "lib/#{web_path}/components/layouts/inertia_root.html.heex"

      layout_content =
        render_install_template("inertia_root_vite_react.html.heex", %{
          "__WEB_MODULE__" => clean_web_module,
          "__APP_NAME__" => to_string(app_name)
        })

      igniter
      |> Igniter.create_new_file(layout_path, layout_content, on_exists: :warning)
    end

    # Create inertia_root.html.heex layout for vite + vue/svelte
    defp create_inertia_root_layout(igniter, web_module, "vite", _framework) do
      app_name = Igniter.Project.Application.app_name(igniter)
      clean_web_module = web_module |> to_string() |> String.replace_prefix("Elixir.", "")
      web_path = Macro.underscore(clean_web_module)
      layout_path = "lib/#{web_path}/components/layouts/inertia_root.html.heex"

      layout_content =
        render_install_template("inertia_root_vite.html.heex", %{
          "__WEB_MODULE__" => clean_web_module,
          "__APP_NAME__" => to_string(app_name)
        })

      igniter
      |> Igniter.create_new_file(layout_path, layout_content, on_exists: :warning)
    end

    # Create inertia_root.html.heex layout for esbuild
    defp create_inertia_root_layout(igniter, web_module, "esbuild", _framework) do
      clean_web_module = web_module |> to_string() |> String.replace_prefix("Elixir.", "")
      web_path = Macro.underscore(clean_web_module)
      layout_path = "lib/#{web_path}/components/layouts/inertia_root.html.heex"

      layout_content = render_install_template("inertia_root_esbuild.html.heex")

      igniter
      |> Igniter.create_new_file(layout_path, layout_content, on_exists: :warning)
    end

    defp create_inertia_root_layout(igniter, _web_module, _bundler, _framework), do: igniter

    # Create Inertia entry point file (assets/js/inertia.tsx or .ts)
    defp create_inertia_entry_point(igniter, framework, bundler)
         when framework in ["react", "react18"] do
      # For esbuild, use dynamic import() for code splitting
      # For vite, use import.meta.glob for page resolution
      resolve_code =
        if bundler == "vite" do
          """
            resolve: (name) => {
              const pages = import.meta.glob("./pages/**/*.tsx", { eager: true });
              return pages[`./pages/${name}.tsx`];
            },
          """
        else
          """
            resolve: async (name) => {
              return await import(`./pages/${name}.tsx`);
            },
          """
        end

      entry_content = """
      import React from "react";
      import { createInertiaApp } from "@inertiajs/react";
      import { createRoot } from "react-dom/client";

      createInertiaApp({
      #{String.trim(resolve_code)}
        setup({ el, App, props }) {
          createRoot(el).render(
            <React.StrictMode>
              <App {...props} />
            </React.StrictMode>
          );
        },
      });
      """

      igniter
      |> Igniter.create_new_file("assets/js/inertia.tsx", entry_content, on_exists: :warning)
    end

    defp create_inertia_entry_point(igniter, "vue", bundler) do
      resolve_code =
        if bundler == "vite" do
          """
            resolve: (name) => {
              const pages = import.meta.glob("./**/*.vue", { eager: true });
              return pages[`./${name}.vue`] || pages[`./pages/${name}.vue`];
            },
          """
        else
          """
            resolve: async (name) => {
              return await import(`./pages/${name}.vue`);
            },
          """
        end

      entry_content = """
      import { createApp, h } from "vue";
      import { createInertiaApp } from "@inertiajs/vue3";

      createInertiaApp({
      #{String.trim(resolve_code)}
        setup({ el, App, props, plugin }) {
          createApp({ render: () => h(App, props) })
            .use(plugin)
            .mount(el);
        },
      });
      """

      igniter
      |> Igniter.create_new_file("assets/js/inertia.ts", entry_content, on_exists: :warning)
    end

    defp create_inertia_entry_point(igniter, "svelte", bundler) do
      resolve_code =
        if bundler == "vite" do
          """
            resolve: (name) => {
              const pages = import.meta.glob("./**/*.svelte", { eager: true });
              return pages[`./${name}.svelte`] || pages[`./pages/${name}.svelte`];
            },
          """
        else
          """
            resolve: async (name) => {
              return await import(`./pages/${name}.svelte`);
            },
          """
        end

      entry_content = """
      import { mount } from "svelte";
      import { createInertiaApp } from "@inertiajs/svelte";

      createInertiaApp({
      #{String.trim(resolve_code)}
        setup({ el, App, props }) {
          mount(App, { target: el, props });
        },
      });
      """

      igniter
      |> Igniter.create_new_file("assets/js/inertia.ts", entry_content, on_exists: :warning)
    end

    # Create demo page component that demonstrates AshTypescript RPC client
    defp create_inertia_page_component(igniter, framework)
         when framework in ["react", "react18"] do
      page_body = get_react_page_body()

      component_content = """
      import React from "react";

      declare global {
        interface Window {
          Prism: any;
        }
      }

      export default function App() {
        React.useEffect(() => {
          if (window.Prism) {
            window.Prism.highlightAll();
          }
        }, []);

        return (
      #{page_body}
        );
      }
      """

      igniter
      |> Igniter.create_new_file(
        "assets/js/pages/App.tsx",
        component_content,
        on_exists: :warning
      )
    end

    defp create_inertia_page_component(igniter, "vue") do
      {script_content, template_content} = get_vue_page_content()

      vue_component = script_content <> "\n" <> template_content

      igniter
      |> Igniter.create_new_file("assets/js/pages/App.vue", vue_component, on_exists: :warning)
    end

    defp create_inertia_page_component(igniter, "svelte") do
      {script_content, template_content} = get_svelte_page_content()

      svelte_component = script_content <> "\n" <> template_content

      igniter
      |> Igniter.create_new_file("assets/js/pages/App.svelte", svelte_component,
        on_exists: :warning
      )
    end

    # Create PageController that uses render_inertia
    defp create_inertia_page_controller(igniter, web_module, _framework) do
      clean_web_module = web_module |> to_string() |> String.replace_prefix("Elixir.", "")
      page_name = "App"

      controller_path =
        clean_web_module
        |> String.replace_suffix("Web", "")
        |> Macro.underscore()

      page_controller_path = "lib/#{controller_path}_web/controllers/page_controller.ex"

      page_controller_content = """
      defmodule #{clean_web_module}.PageController do
        use #{clean_web_module}, :controller

        def index(conn, _params) do
          render_inertia(conn, "#{page_name}")
        end
      end
      """

      case Igniter.exists?(igniter, page_controller_path) do
        false ->
          igniter
          |> Igniter.create_new_file(page_controller_path, page_controller_content)

        true ->
          igniter
          |> Igniter.update_elixir_file(page_controller_path, fn zipper ->
            case Igniter.Code.Common.move_to(zipper, &function_named?(&1, :index, 2)) do
              {:ok, _zipper} ->
                # index function already exists, don't modify
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

    # Add :inertia pipeline and nested scope with route to router
    defp add_inertia_pipeline_and_routes(igniter, web_module) do
      {igniter, router_module} = Igniter.Libs.Phoenix.select_router(igniter)

      case Igniter.Project.Module.find_module(igniter, router_module) do
        {:ok, {igniter, source, _zipper}} ->
          router_content = Rewrite.Source.get(source, :content)
          clean_web_module = web_module |> to_string() |> String.replace_prefix("Elixir.", "")
          path = Rewrite.Source.get(source, :path)

          # Add :inertia pipeline if not present
          igniter =
            if String.contains?(router_content, "pipeline :inertia") do
              igniter
            else
              Igniter.update_file(igniter, path, fn source ->
                content = source.content

                # Find the end of the browser pipeline and insert after it
                pipeline_code = """

                  pipeline :inertia do
                    plug :put_root_layout, html: {#{clean_web_module}.Layouts, :inertia_root}
                  end
                """

                # Insert after the browser pipeline's end
                updated_content =
                  Regex.replace(
                    ~r/(pipeline :browser do.*?end)/s,
                    content,
                    "\\1\n#{pipeline_code}",
                    global: false
                  )

                if content == updated_content do
                  source
                else
                  Rewrite.Source.update(source, :content, updated_content)
                end
              end)
            end

          # Re-read the source after potential pipeline addition
          {igniter, source, _zipper} =
            case Igniter.Project.Module.find_module(igniter, router_module) do
              {:ok, result} -> result
              {:error, igniter} -> {igniter, nil, nil}
            end

          if is_nil(source) do
            igniter
          else
            router_content = Rewrite.Source.get(source, :content)

            # Add the nested inertia scope with route if not present
            if String.contains?(router_content, "pipe_through :inertia") do
              igniter
            else
              # Add nested scope inside the main browser scope
              inertia_scope = """
                  scope "/" do
                    pipe_through :inertia
                    get "/ash-typescript", PageController, :index
                  end
              """

              Igniter.update_file(igniter, path, fn source ->
                content = source.content

                # Find the browser scope and append the inertia scope inside it
                # Look for: scope "/", MyAppWeb do\n    pipe_through :browser
                updated_content =
                  Regex.replace(
                    ~r/(scope "\/", #{Regex.escape(clean_web_module)} do\s*\n\s*pipe_through :browser)/s,
                    content,
                    "\\1\n\n#{inertia_scope}",
                    global: false
                  )

                if content == updated_content do
                  source
                else
                  Rewrite.Source.update(source, :content, updated_content)
                end
              end)
            end
          end

        {:error, igniter} ->
          Igniter.add_warning(
            igniter,
            "Could not find router module #{inspect(router_module)}. " <>
              "Please manually add the :inertia pipeline and /ash-typescript route."
          )
      end
    end

    # ---- End Inertia.js Support Functions ----

    # ---- Shared Page Content Generators ----
    # These functions generate the page content that is shared between SPA and Inertia flows.
    # They return the body content without the component wrapper (mount code for SPA, export for Inertia).

    # React page body content (JSX only, no component wrapper)
    defp get_react_page_body do
      """
          <div className="min-h-screen bg-gradient-to-br from-slate-50 to-orange-50">
            <div className="max-w-4xl mx-auto p-8">
              <div className="flex items-center gap-6 mb-12">
                <img
                  src="https://raw.githubusercontent.com/ash-project/ash_typescript/main/logos/ash-typescript.png"
                  alt="AshTypescript Logo"
                  className="w-20 h-20"
                />
                <div>
                  <h1 className="text-5xl font-bold text-slate-900 mb-2">
                    AshTypescript
                  </h1>
                  <p className="text-xl text-slate-600 font-medium">
                    Type-safe TypeScript bindings for Ash Framework
                  </p>
                </div>
              </div>

              <div className="space-y-12">
                <section className="bg-white rounded-xl shadow-sm border border-slate-200 p-8">
                  <div className="flex items-center gap-3 mb-6">
                    <div className="w-8 h-8 bg-orange-500 rounded-lg flex items-center justify-center text-white font-bold text-lg">
                      1
                    </div>
                    <h2 className="text-2xl font-bold text-slate-900">
                      Configure RPC in Your Domain
                    </h2>
                  </div>
                  <p className="text-slate-700 mb-6 text-lg leading-relaxed">
                    Add the AshTypescript.Rpc extension to your domain and configure RPC actions:
                  </p>
                  <pre className="rounded-lg overflow-x-auto text-sm border">
                    <code className="language-elixir">
      {\`defmodule MyApp.Accounts do
        use Ash.Domain, extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource MyApp.Accounts.User do
            rpc_action :get_by_email, :get_by_email
            rpc_action :list_users, :read
            rpc_action :get_user, :read
          end
        end

        resources do
          resource MyApp.Accounts.User
        end
      end\`}
                    </code>
                  </pre>
                </section>

                <section className="bg-white rounded-xl shadow-sm border border-slate-200 p-8">
                  <div className="flex items-center gap-3 mb-6">
                    <div className="w-8 h-8 bg-orange-500 rounded-lg flex items-center justify-center text-white font-bold text-lg">
                      2
                    </div>
                    <h2 className="text-2xl font-bold text-slate-900">
                      TypeScript Auto-Generation
                    </h2>
                  </div>
                  <p className="text-slate-700 mb-6 text-lg leading-relaxed">
                    When running the dev server, TypeScript types are automatically generated for you:
                  </p>
                  <pre className="rounded-lg text-sm border mb-6">
                    <code className="language-bash">mix phx.server</code>
                  </pre>
                  <div className="bg-orange-50 border border-orange-200 rounded-lg p-6 mb-6">
                    <p className="text-slate-700 text-lg leading-relaxed">
                      <strong className="text-orange-700">✨ Automatic regeneration:</strong> TypeScript files are automatically regenerated whenever you make changes to your resources or expose new RPC actions. No manual codegen step required during development!
                    </p>
                  </div>
                  <p className="text-slate-600 mb-4">
                    For production builds or manual generation, you can also run:
                  </p>
                  <pre className="rounded-lg text-sm border">
                    <code className="language-bash">mix ash_typescript.codegen --output "assets/js/ash_generated.ts"</code>
                  </pre>
                </section>

                <section className="bg-white rounded-xl shadow-sm border border-slate-200 p-8">
                  <div className="flex items-center gap-3 mb-6">
                    <div className="w-8 h-8 bg-orange-500 rounded-lg flex items-center justify-center text-white font-bold text-lg">
                      3
                    </div>
                    <h2 className="text-2xl font-bold text-slate-900">
                      Import and Use Generated Functions
                    </h2>
                  </div>
                  <p className="text-slate-700 mb-6 text-lg leading-relaxed">
                    Import the generated RPC functions in your TypeScript/React code:
                  </p>
                  <pre className="rounded-lg overflow-x-auto text-sm border">
                    <code className="language-typescript">
      {\`import { getByEmail, listUsers, getUser } from "./ash_generated";

      // Use the typed RPC functions
      const findUserByEmail = async (email: string) => {
        try {
          const result = await getByEmail({ email });
          if (result.success) {
            console.log("User found:", result.data);
            return result.data;
          } else {
            console.error("User not found:", result.errors);
            return null;
          }
        } catch (error) {
          console.error("Network error:", error);
          return null;
        }
      };

      const fetchUsers = async () => {
        try {
          const result = await listUsers();
          if (result.success) {
            console.log("Users:", result.data);
          } else {
            console.error("Failed to fetch users:", result.errors);
          }
        } catch (error) {
          console.error("Network error:", error);
        }
      };\`}
                    </code>
                  </pre>
                </section>

                <section className="bg-white rounded-xl shadow-sm border border-slate-200 p-8">
                  <h2 className="text-2xl font-bold text-slate-900 mb-8">
                    Learn More & Examples
                  </h2>
                  <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
                    <a
                      href="https://hexdocs.pm/ash_typescript"
                      target="_blank"
                      rel="noopener noreferrer"
                      className="flex flex-col items-start gap-4 p-6 border border-slate-200 rounded-lg hover:border-orange-300 hover:shadow-md transition-all duration-200 group"
                    >
                      <div className="w-12 h-12 bg-orange-100 rounded-lg flex items-center justify-center group-hover:bg-orange-200 transition-colors">
                        <span className="text-orange-600 font-bold text-xl">📚</span>
                      </div>
                      <div>
                        <h3 className="font-bold text-slate-900 text-lg mb-2 group-hover:text-orange-600 transition-colors">Documentation</h3>
                        <p className="text-slate-600">Complete API reference and guides on HexDocs</p>
                      </div>
                    </a>

                    <a
                      href="https://github.com/ash-project/ash_typescript"
                      target="_blank"
                      rel="noopener noreferrer"
                      className="flex flex-col items-start gap-4 p-6 border border-slate-200 rounded-lg hover:border-orange-300 hover:shadow-md transition-all duration-200 group"
                    >
                      <div className="w-12 h-12 bg-orange-100 rounded-lg flex items-center justify-center group-hover:bg-orange-200 transition-colors">
                        <span className="text-orange-600 font-bold text-xl">🔧</span>
                      </div>
                      <div>
                        <h3 className="font-bold text-slate-900 text-lg mb-2 group-hover:text-orange-600 transition-colors">Source Code</h3>
                        <p className="text-slate-600">View the source, report issues, and contribute on GitHub</p>
                      </div>
                    </a>

                    <a
                      href="https://github.com/ChristianAlexander/ash_typescript_demo"
                      target="_blank"
                      rel="noopener noreferrer"
                      className="flex flex-col items-start gap-4 p-6 border border-slate-200 rounded-lg hover:border-orange-300 hover:shadow-md transition-all duration-200 group"
                    >
                      <div className="w-12 h-12 bg-orange-100 rounded-lg flex items-center justify-center group-hover:bg-orange-200 transition-colors">
                        <span className="text-orange-600 font-bold text-xl">🚀</span>
                      </div>
                      <div>
                        <h3 className="font-bold text-slate-900 text-lg mb-2 group-hover:text-orange-600 transition-colors">Demo App</h3>
                        <p className="text-slate-600">See AshTypescript with TanStack Query & Table in action</p>
                        <p className="text-slate-500 text-sm mt-1">by ChristianAlexander</p>
                      </div>
                    </a>
                  </div>
                </section>

                <div className="bg-gradient-to-r from-orange-500 to-orange-600 rounded-xl shadow-lg p-8 text-center">
                  <div className="flex items-center justify-center mb-4">
                    <div className="w-12 h-12 bg-white rounded-full flex items-center justify-center">
                      <span className="text-orange-600 font-bold text-xl">🚀</span>
                    </div>
                  </div>
                  <h3 className="text-2xl font-bold text-white mb-3">
                    Ready to Get Started?
                  </h3>
                  <p className="text-orange-100 text-lg leading-relaxed max-w-2xl mx-auto">
                    Check your generated RPC functions and start building type-safe interactions between your frontend and Ash resources!
                  </p>
                </div>
              </div>
            </div>
          </div>
      """
    end

    # Vue page script and template content
    defp get_vue_page_content do
      script_content = """
      <script setup lang="ts">
      import { onMounted } from "vue";

      declare global {
        interface Window {
          Prism: any;
        }
      }

      onMounted(() => {
        if (window.Prism) {
          window.Prism.highlightAll();
        }
      });

      const elixirCode = `defmodule MyApp.Accounts do
        use Ash.Domain, extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource MyApp.Accounts.User do
            rpc_action :get_by_email, :get_by_email
            rpc_action :list_users, :read
            rpc_action :get_user, :read
          end
        end

        resources do
          resource MyApp.Accounts.User
        end
      end`;

      const typescriptCode = `import { getByEmail, listUsers, getUser } from "./ash_generated";

      // Use the typed RPC functions
      const findUserByEmail = async (email: string) => {
        try {
          const result = await getByEmail({ email });
          if (result.success) {
            console.log("User found:", result.data);
            return result.data;
          } else {
            console.error("User not found:", result.errors);
            return null;
          }
        } catch (error) {
          console.error("Network error:", error);
          return null;
        }
      };

      const fetchUsers = async () => {
        try {
          const result = await listUsers();
          if (result.success) {
            console.log("Users:", result.data);
          } else {
            console.error("Failed to fetch users:", result.errors);
          }
        } catch (error) {
          console.error("Network error:", error);
        }
      };`;
      </script>
      """

      template_content = """
      <template>
        <div class="min-h-screen bg-gradient-to-br from-slate-50 to-orange-50">
          <div class="max-w-4xl mx-auto p-8">
            <div class="flex items-center gap-6 mb-12">
              <img
                src="https://raw.githubusercontent.com/ash-project/ash_typescript/main/logos/ash-typescript.png"
                alt="AshTypescript Logo"
                class="w-20 h-20"
              />
              <div>
                <h1 class="text-5xl font-bold text-slate-900 mb-2">AshTypescript</h1>
                <p class="text-xl text-slate-600 font-medium">
                  Type-safe TypeScript bindings for Ash Framework
                </p>
              </div>
            </div>

            <div class="space-y-12">
              <section class="bg-white rounded-xl shadow-sm border border-slate-200 p-8">
                <div class="flex items-center gap-3 mb-6">
                  <div class="w-8 h-8 bg-orange-500 rounded-lg flex items-center justify-center text-white font-bold text-lg">1</div>
                  <h2 class="text-2xl font-bold text-slate-900">Configure RPC in Your Domain</h2>
                </div>
                <p class="text-slate-700 mb-6 text-lg leading-relaxed">
                  Add the AshTypescript.Rpc extension to your domain and configure RPC actions:
                </p>
                <pre class="rounded-lg overflow-x-auto text-sm border"><code class="language-elixir">{{ elixirCode }}</code></pre>
              </section>

              <section class="bg-white rounded-xl shadow-sm border border-slate-200 p-8">
                <div class="flex items-center gap-3 mb-6">
                  <div class="w-8 h-8 bg-orange-500 rounded-lg flex items-center justify-center text-white font-bold text-lg">2</div>
                  <h2 class="text-2xl font-bold text-slate-900">TypeScript Auto-Generation</h2>
                </div>
                <p class="text-slate-700 mb-6 text-lg leading-relaxed">
                  When running the dev server, TypeScript types are automatically generated for you:
                </p>
                <pre class="rounded-lg text-sm border mb-6"><code class="language-bash">mix phx.server</code></pre>
                <div class="bg-orange-50 border border-orange-200 rounded-lg p-6 mb-6">
                  <p class="text-slate-700 text-lg leading-relaxed">
                    <strong class="text-orange-700">✨ Automatic regeneration:</strong> TypeScript files are automatically regenerated whenever you make changes to your resources or expose new RPC actions. No manual codegen step required during development!
                  </p>
                </div>
                <p class="text-slate-600 mb-4">For production builds or manual generation, you can also run:</p>
                <pre class="rounded-lg text-sm border"><code class="language-bash">mix ash_typescript.codegen --output "assets/js/ash_generated.ts"</code></pre>
              </section>

              <section class="bg-white rounded-xl shadow-sm border border-slate-200 p-8">
                <div class="flex items-center gap-3 mb-6">
                  <div class="w-8 h-8 bg-orange-500 rounded-lg flex items-center justify-center text-white font-bold text-lg">3</div>
                  <h2 class="text-2xl font-bold text-slate-900">Import and Use Generated Functions</h2>
                </div>
                <p class="text-slate-700 mb-6 text-lg leading-relaxed">
                  Import the generated RPC functions in your TypeScript/Vue code:
                </p>
                <pre class="rounded-lg overflow-x-auto text-sm border"><code class="language-typescript">{{ typescriptCode }}</code></pre>
              </section>

              <section class="bg-white rounded-xl shadow-sm border border-slate-200 p-8">
                <h2 class="text-2xl font-bold text-slate-900 mb-8">Learn More & Examples</h2>
                <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
                  <a href="https://hexdocs.pm/ash_typescript" target="_blank" rel="noopener noreferrer"
                     class="flex flex-col items-start gap-4 p-6 border border-slate-200 rounded-lg hover:border-orange-300 hover:shadow-md transition-all duration-200 group">
                    <div class="w-12 h-12 bg-orange-100 rounded-lg flex items-center justify-center group-hover:bg-orange-200 transition-colors">
                      <span class="text-orange-600 font-bold text-xl">📚</span>
                    </div>
                    <div>
                      <h3 class="font-bold text-slate-900 text-lg mb-2 group-hover:text-orange-600 transition-colors">Documentation</h3>
                      <p class="text-slate-600">Complete API reference and guides on HexDocs</p>
                    </div>
                  </a>
                  <a href="https://github.com/ash-project/ash_typescript" target="_blank" rel="noopener noreferrer"
                     class="flex flex-col items-start gap-4 p-6 border border-slate-200 rounded-lg hover:border-orange-300 hover:shadow-md transition-all duration-200 group">
                    <div class="w-12 h-12 bg-orange-100 rounded-lg flex items-center justify-center group-hover:bg-orange-200 transition-colors">
                      <span class="text-orange-600 font-bold text-xl">🔧</span>
                    </div>
                    <div>
                      <h3 class="font-bold text-slate-900 text-lg mb-2 group-hover:text-orange-600 transition-colors">Source Code</h3>
                      <p class="text-slate-600">View the source, report issues, and contribute on GitHub</p>
                    </div>
                  </a>
                  <a href="https://github.com/ChristianAlexander/ash_typescript_demo" target="_blank" rel="noopener noreferrer"
                     class="flex flex-col items-start gap-4 p-6 border border-slate-200 rounded-lg hover:border-orange-300 hover:shadow-md transition-all duration-200 group">
                    <div class="w-12 h-12 bg-orange-100 rounded-lg flex items-center justify-center group-hover:bg-orange-200 transition-colors">
                      <span class="text-orange-600 font-bold text-xl">🚀</span>
                    </div>
                    <div>
                      <h3 class="font-bold text-slate-900 text-lg mb-2 group-hover:text-orange-600 transition-colors">Demo App</h3>
                      <p class="text-slate-600">See AshTypescript with TanStack Query & Table in action</p>
                      <p class="text-slate-500 text-sm mt-1">by ChristianAlexander</p>
                    </div>
                  </a>
                </div>
              </section>

              <div class="bg-gradient-to-r from-orange-500 to-orange-600 rounded-xl shadow-lg p-8 text-center">
                <div class="flex items-center justify-center mb-4">
                  <div class="w-12 h-12 bg-white rounded-full flex items-center justify-center">
                    <span class="text-orange-600 font-bold text-xl">🚀</span>
                  </div>
                </div>
                <h3 class="text-2xl font-bold text-white mb-3">Ready to Get Started?</h3>
                <p class="text-orange-100 text-lg leading-relaxed max-w-2xl mx-auto">
                  Check your generated RPC functions and start building type-safe interactions between your frontend and Ash resources!
                </p>
              </div>
            </div>
          </div>
        </div>
      </template>
      """

      {script_content, template_content}
    end

    # Svelte page script and template content
    defp get_svelte_page_content do
      script_content = """
      <script lang="ts">
        import { onMount } from "svelte";

        declare global {
          interface Window {
            Prism: any;
          }
        }

        onMount(() => {
          if (window.Prism) {
            window.Prism.highlightAll();
          }
        });

        const elixirCode = `defmodule MyApp.Accounts do
        use Ash.Domain, extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource MyApp.Accounts.User do
            rpc_action :get_by_email, :get_by_email
            rpc_action :list_users, :read
            rpc_action :get_user, :read
          end
        end

        resources do
          resource MyApp.Accounts.User
        end
      end`;

        const typescriptCode = `import { getByEmail, listUsers, getUser } from "./ash_generated";

      // Use the typed RPC functions
      const findUserByEmail = async (email: string) => {
        try {
          const result = await getByEmail({ email });
          if (result.success) {
            console.log("User found:", result.data);
            return result.data;
          } else {
            console.error("User not found:", result.errors);
            return null;
          }
        } catch (error) {
          console.error("Network error:", error);
          return null;
        }
      };

      const fetchUsers = async () => {
        try {
          const result = await listUsers();
          if (result.success) {
            console.log("Users:", result.data);
          } else {
            console.error("Failed to fetch users:", result.errors);
          }
        } catch (error) {
          console.error("Network error:", error);
        }
      };`;
      </script>
      """

      template_content = """
      <div class="min-h-screen bg-gradient-to-br from-slate-50 to-orange-50">
        <div class="max-w-4xl mx-auto p-8">
          <div class="flex items-center gap-6 mb-12">
            <img
              src="https://raw.githubusercontent.com/ash-project/ash_typescript/main/logos/ash-typescript.png"
              alt="AshTypescript Logo"
              class="w-20 h-20"
            />
            <div>
              <h1 class="text-5xl font-bold text-slate-900 mb-2">AshTypescript</h1>
              <p class="text-xl text-slate-600 font-medium">
                Type-safe TypeScript bindings for Ash Framework
              </p>
            </div>
          </div>

          <div class="space-y-12">
            <section class="bg-white rounded-xl shadow-sm border border-slate-200 p-8">
              <div class="flex items-center gap-3 mb-6">
                <div class="w-8 h-8 bg-orange-500 rounded-lg flex items-center justify-center text-white font-bold text-lg">1</div>
                <h2 class="text-2xl font-bold text-slate-900">Configure RPC in Your Domain</h2>
              </div>
              <p class="text-slate-700 mb-6 text-lg leading-relaxed">
                Add the AshTypescript.Rpc extension to your domain and configure RPC actions:
              </p>
              <pre class="rounded-lg overflow-x-auto text-sm border"><code class="language-elixir">{elixirCode}</code></pre>
            </section>

            <section class="bg-white rounded-xl shadow-sm border border-slate-200 p-8">
              <div class="flex items-center gap-3 mb-6">
                <div class="w-8 h-8 bg-orange-500 rounded-lg flex items-center justify-center text-white font-bold text-lg">2</div>
                <h2 class="text-2xl font-bold text-slate-900">TypeScript Auto-Generation</h2>
              </div>
              <p class="text-slate-700 mb-6 text-lg leading-relaxed">
                When running the dev server, TypeScript types are automatically generated for you:
              </p>
              <pre class="rounded-lg text-sm border mb-6"><code class="language-bash">mix phx.server</code></pre>
              <div class="bg-orange-50 border border-orange-200 rounded-lg p-6 mb-6">
                <p class="text-slate-700 text-lg leading-relaxed">
                  <strong class="text-orange-700">✨ Automatic regeneration:</strong> TypeScript files are automatically regenerated whenever you make changes to your resources or expose new RPC actions. No manual codegen step required during development!
                </p>
              </div>
              <p class="text-slate-600 mb-4">For production builds or manual generation, you can also run:</p>
              <pre class="rounded-lg text-sm border"><code class="language-bash">mix ash_typescript.codegen --output "assets/js/ash_generated.ts"</code></pre>
            </section>

            <section class="bg-white rounded-xl shadow-sm border border-slate-200 p-8">
              <div class="flex items-center gap-3 mb-6">
                <div class="w-8 h-8 bg-orange-500 rounded-lg flex items-center justify-center text-white font-bold text-lg">3</div>
                <h2 class="text-2xl font-bold text-slate-900">Import and Use Generated Functions</h2>
              </div>
              <p class="text-slate-700 mb-6 text-lg leading-relaxed">
                Import the generated RPC functions in your TypeScript/Svelte code:
              </p>
              <pre class="rounded-lg overflow-x-auto text-sm border"><code class="language-typescript">{typescriptCode}</code></pre>
            </section>

            <section class="bg-white rounded-xl shadow-sm border border-slate-200 p-8">
              <h2 class="text-2xl font-bold text-slate-900 mb-8">Learn More & Examples</h2>
              <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
                <a href="https://hexdocs.pm/ash_typescript" target="_blank" rel="noopener noreferrer"
                   class="flex flex-col items-start gap-4 p-6 border border-slate-200 rounded-lg hover:border-orange-300 hover:shadow-md transition-all duration-200 group">
                  <div class="w-12 h-12 bg-orange-100 rounded-lg flex items-center justify-center group-hover:bg-orange-200 transition-colors">
                    <span class="text-orange-600 font-bold text-xl">📚</span>
                  </div>
                  <div>
                    <h3 class="font-bold text-slate-900 text-lg mb-2 group-hover:text-orange-600 transition-colors">Documentation</h3>
                    <p class="text-slate-600">Complete API reference and guides on HexDocs</p>
                  </div>
                </a>
                <a href="https://github.com/ash-project/ash_typescript" target="_blank" rel="noopener noreferrer"
                   class="flex flex-col items-start gap-4 p-6 border border-slate-200 rounded-lg hover:border-orange-300 hover:shadow-md transition-all duration-200 group">
                  <div class="w-12 h-12 bg-orange-100 rounded-lg flex items-center justify-center group-hover:bg-orange-200 transition-colors">
                    <span class="text-orange-600 font-bold text-xl">🔧</span>
                  </div>
                  <div>
                    <h3 class="font-bold text-slate-900 text-lg mb-2 group-hover:text-orange-600 transition-colors">Source Code</h3>
                    <p class="text-slate-600">View the source, report issues, and contribute on GitHub</p>
                  </div>
                </a>
                <a href="https://github.com/ChristianAlexander/ash_typescript_demo" target="_blank" rel="noopener noreferrer"
                   class="flex flex-col items-start gap-4 p-6 border border-slate-200 rounded-lg hover:border-orange-300 hover:shadow-md transition-all duration-200 group">
                  <div class="w-12 h-12 bg-orange-100 rounded-lg flex items-center justify-center group-hover:bg-orange-200 transition-colors">
                    <span class="text-orange-600 font-bold text-xl">🚀</span>
                  </div>
                  <div>
                    <h3 class="font-bold text-slate-900 text-lg mb-2 group-hover:text-orange-600 transition-colors">Demo App</h3>
                    <p class="text-slate-600">See AshTypescript with TanStack Query & Table in action</p>
                    <p class="text-slate-500 text-sm mt-1">by ChristianAlexander</p>
                  </div>
                </a>
              </div>
            </section>

            <div class="bg-gradient-to-r from-orange-500 to-orange-600 rounded-xl shadow-lg p-8 text-center">
              <div class="flex items-center justify-center mb-4">
                <div class="w-12 h-12 bg-white rounded-full flex items-center justify-center">
                  <span class="text-orange-600 font-bold text-xl">🚀</span>
                </div>
              </div>
              <h3 class="text-2xl font-bold text-white mb-3">Ready to Get Started?</h3>
              <p class="text-orange-100 text-lg leading-relaxed max-w-2xl mx-auto">
                Check your generated RPC functions and start building type-safe interactions between your frontend and Ash resources!
              </p>
            </div>
          </div>
        </div>
      </div>
      """

      {script_content, template_content}
    end

    # ---- End Shared Page Content Generators ----

    defp add_next_steps_notice(igniter, framework, bundler, use_inertia) do
      inertia_entry_file =
        if framework in ["react", "react18"], do: "inertia.tsx", else: "inertia.ts"

      inertia_page_file =
        if framework in ["react", "react18"], do: "pages/App.tsx", else: "pages/App.#{framework}"

      base_notice = """
      AshTypescript has been successfully installed!

      Next Steps:
      1. Configure your domain with the AshTypescript.Rpc extension
      2. Add typescript_rpc configurations for your resources
      3. Generate TypeScript types with: mix ash_typescript.codegen
      4. Start using type-safe RPC functions in your frontend!

      Documentation: https://hexdocs.pm/ash_typescript
      """

      framework_notice_vite = fn name ->
        """
        AshTypescript with #{name} + Vite has been successfully installed!

        Your Phoenix + #{name} + TypeScript + Vite setup is ready!

        Files created:
        - spa_root.html.heex: Layout for SPA pages (loads index.js + app.css)
        - PageController: Uses put_root_layout to switch to spa_root layout

        The root.html.heex layout loads app.js + app.css for LiveView pages.
        The spa_root.html.heex layout loads index.js + app.css for SPA pages.

        Next Steps:
        1. Configure your domain with the AshTypescript.Rpc extension
        2. Add typescript_rpc configurations for your resources
        3. Start your Phoenix server: mix phx.server
        4. Check out http://localhost:4000/ash-typescript for how to get started!

        Documentation: https://hexdocs.pm/ash_typescript
        """
      end

      framework_notice_esbuild = fn name ->
        """
        AshTypescript with #{name} + esbuild has been successfully installed!

        Your Phoenix + #{name} + TypeScript + esbuild setup is ready!

        Files created:
        - spa_root.html.heex: Layout for SPA pages (loads index.js as ES module)
        - PageController: Uses put_root_layout to switch to spa_root layout

        The root.html.heex layout loads app.js + app.css for LiveView pages.
        The spa_root.html.heex layout loads index.js as ES module for SPA pages.

        Next Steps:
        1. Configure your domain with the AshTypescript.Rpc extension
        2. Add typescript_rpc configurations for your resources
        3. Start your Phoenix server: mix phx.server
        4. Check out http://localhost:4000/ash-typescript for how to get started!

        Documentation: https://hexdocs.pm/ash_typescript
        """
      end

      inertia_notice_vite = fn name ->
        """
        AshTypescript with #{name} + Inertia.js + Vite has been successfully installed!

        Your Phoenix + #{name} + Inertia.js + TypeScript + Vite setup is ready!

        Files created:
        - inertia_root.html.heex: Layout for Inertia pages (loads inertia.js + app.css)
        - #{inertia_entry_file}: Inertia client-side entry point with createInertiaApp()
        - #{inertia_page_file}: Getting started guide page
        - PageController: Renders Inertia pages

        The root.html.heex layout loads app.js + app.css for LiveView pages.
        The inertia_root.html.heex layout loads inertia.js + app.css for Inertia pages.

        Next Steps:
        1. Start your Phoenix server: mix phx.server
        2. Visit http://localhost:4000/ash-typescript to see the getting started guide!
        3. Visit http://localhost:4000/ to see LiveView still working!

        Documentation: https://hexdocs.pm/ash_typescript
        Inertia.js: https://inertiajs.com
        """
      end

      inertia_notice_esbuild = fn name ->
        """
        AshTypescript with #{name} + Inertia.js + esbuild has been successfully installed!

        Your Phoenix + #{name} + Inertia.js + TypeScript + esbuild setup is ready!

        Files created:
        - inertia_root.html.heex: Layout for Inertia pages (loads inertia.js as ES module)
        - #{inertia_entry_file}: Inertia client-side entry point with createInertiaApp()
        - #{inertia_page_file}: Getting started guide page
        - PageController: Renders Inertia pages

        The root.html.heex layout loads app.js + app.css for LiveView pages.
        The inertia_root.html.heex layout loads inertia.js as ES module for Inertia pages.

        Next Steps:
        1. Start your Phoenix server: mix phx.server
        2. Visit http://localhost:4000/ash-typescript to see the getting started guide!
        3. Visit http://localhost:4000/ to see LiveView still working!

        Documentation: https://hexdocs.pm/ash_typescript
        Inertia.js: https://inertiajs.com
        """
      end

      notice =
        case {framework, bundler, use_inertia} do
          {_, _, true} ->
            name =
              case framework do
                "react" -> "React"
                "react18" -> "React 18"
                "vue" -> "Vue"
                "svelte" -> "Svelte"
                _ -> "React"
              end

            if bundler == "vite",
              do: inertia_notice_vite.(name),
              else: inertia_notice_esbuild.(name)

          {"react", "vite", _} ->
            framework_notice_vite.("React")

          {"react18", "vite", _} ->
            framework_notice_vite.("React 18")

          {"vue", "vite", _} ->
            framework_notice_vite.("Vue")

          {"svelte", "vite", _} ->
            framework_notice_vite.("Svelte")

          {"react", _, _} ->
            framework_notice_esbuild.("React")

          {"react18", _, _} ->
            framework_notice_esbuild.("React 18")

          {"vue", _, _} ->
            framework_notice_esbuild.("Vue")

          {"svelte", _, _} ->
            framework_notice_esbuild.("Svelte")

          _ ->
            base_notice
        end

      # Run assets.setup to install npm dependencies (including framework deps we added)
      # For both esbuild and vite, we need to run this since we add framework deps to package.json
      igniter =
        if framework in ["react", "react18", "vue", "svelte"] do
          Igniter.add_task(igniter, "assets.setup")
        else
          igniter
        end

      Igniter.add_notice(igniter, notice)
    end
  end
else
  defmodule Mix.Tasks.AshTypescript.Install do
    @moduledoc "Installs AshTypescript into a project. Should be called with `mix igniter.install ash_typescript`"

    @shortdoc @moduledoc

    use Mix.Task

    def run(_argv) do
      Mix.shell().error("""
      The task 'ash_typescript.install' requires igniter to be run.

      Please install igniter and try again.

      For more information, see: https://hexdocs.pm/igniter
      """)

      exit({:shutdown, 1})
    end
  end
end
