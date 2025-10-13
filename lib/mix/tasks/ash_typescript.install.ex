# SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
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
        schema: [framework: :string],
        defaults: [framework: nil]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      app_name = Igniter.Project.Application.app_name(igniter)
      web_module = Igniter.Libs.Phoenix.web_module(igniter)
      framework = Keyword.get(igniter.args.options, :framework, nil)

      # Validate framework parameter
      igniter = validate_framework(igniter, framework)

      react_enabled = framework == "react"

      igniter =
        igniter
        |> Igniter.Project.IgniterConfig.add_extension(Igniter.Extensions.Phoenix)
        |> Igniter.Project.Formatter.import_dep(:ash_typescript)
        |> add_ash_typescript_config()
        |> create_rpc_controller(app_name, web_module)
        |> add_rpc_routes(web_module)

      igniter =
        if react_enabled do
          igniter
          |> create_package_json()
          |> create_react_index()
          |> update_tsconfig()
          |> update_esbuild_config(app_name)
          |> create_or_update_page_controller(web_module)
          |> create_index_template(web_module)
          |> add_page_index_route(web_module)
        else
          igniter
        end

      igniter
      |> add_next_steps_notice(framework)
    end

    defp validate_framework(igniter, framework) do
      case framework do
        nil ->
          igniter

        "react" ->
          igniter

        invalid_framework ->
          Igniter.add_issue(
            igniter,
            "Invalid framework '#{invalid_framework}'. Currently supported frameworks: react"
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
      router_path = Igniter.Project.Module.proper_location(igniter, router_module)

      igniter = Igniter.include_existing_file(igniter, router_path)
      router_file = Map.get(igniter.rewrite.sources, router_path)
      router_content = router_file.content
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

    defp create_package_json(igniter) do
      package_json_content = """
      {
        "devDependencies": {
          "@types/react": "^19.1.13",
          "@types/react-dom": "^19.1.9"
        },
        "dependencies": {
          "@tanstack/react-query": "^5.89.0",
          "@tanstack/react-table": "^8.21.3",
          "@tanstack/react-virtual": "^3.13.12",
          "react": "^19.1.1",
          "react-dom": "^19.1.1"
        }
      }
      """

      igniter
      |> Igniter.create_new_file("assets/package.json", package_json_content, on_exists: :warning)
    end

    defp create_react_index(igniter) do
      react_index_content = """
      import React, { useEffect } from "react";
      import { createRoot } from "react-dom/client";

      // Declare Prism for TypeScript
      declare global {
        interface Window {
          Prism: any;
        }
      }

      const AshTypescriptGuide = () => {
        useEffect(() => {
          // Trigger Prism highlighting after component mounts
          if (window.Prism) {
            window.Prism.highlightAll();
          }
        }, []);

        return (
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
        );
      };

      const root = createRoot(document.getElementById("app")!);

      root.render(
        <React.StrictMode>
          <AshTypescriptGuide />
        </React.StrictMode>,
      );
      """

      igniter
      |> Igniter.create_new_file("assets/js/index.tsx", react_index_content, on_exists: :warning)
    end

    defp update_tsconfig(igniter) do
      igniter
      |> Igniter.update_file("assets/tsconfig.json", fn source ->
        content = source.content

        needs_jsx = not String.contains?(content, ~s("jsx":))
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

    defp update_esbuild_config(igniter, app_name) do
      igniter
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
            if String.contains?(args_string, "js/index.tsx") do
              zipper
            else
              new_args_string = "js/index.tsx " <> args_string

              new_args_node =
                {{:__block__, block_meta, [:args]},
                 {:sigil_w, sigil_meta, [{:<<>>, string_meta, [new_args_string]}, sigil_opts]}}

              Sourceror.Zipper.replace(zipper, new_args_node)
            end

          _ ->
            zipper
        end
      end)
    end

    defp create_or_update_page_controller(igniter, web_module) do
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

    defp create_index_template(igniter, web_module) do
      clean_web_module = web_module |> to_string() |> String.replace_prefix("Elixir.", "")

      web_path = Macro.underscore(clean_web_module)

      index_template_path = "lib/#{web_path}/controllers/page_html/index.html.heex"

      index_template_content = """
      <link href="https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/themes/prism-tomorrow.min.css" rel="stylesheet" />
      <script src="https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/components/prism-core.min.js"></script>
      <script src="https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/plugins/autoloader/prism-autoloader.min.js"></script>

      <div id="app"></div>
      <script defer phx-track-static type="text/javascript" src={~p"/assets/js/index.js"}>
      </script>
      """

      igniter
      |> Igniter.create_new_file(index_template_path, index_template_content, on_exists: :warning)
    end

    defp add_page_index_route(igniter, web_module) do
      {igniter, router_module} = Igniter.Libs.Phoenix.select_router(igniter)
      router_path = Igniter.Project.Module.proper_location(igniter, router_module)
      igniter = Igniter.include_existing_file(igniter, router_path)
      router_file = Map.get(igniter.rewrite.sources, router_path)
      router_content = router_file.content

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
    end

    defp function_named?(zipper, name, arity) do
      case Sourceror.Zipper.node(zipper) do
        {:def, _, [{^name, _, args}, _]} when length(args) == arity -> true
        _ -> false
      end
    end

    defp add_next_steps_notice(igniter, framework) do
      base_notice = """
      🎉 AshTypescript has been successfully installed!

      Next Steps:
      1. Configure your domain with the AshTypescript.Rpc extension
      2. Add typescript_rpc configurations for your resources
      3. Generate TypeScript types with: mix ash_typescript.codegen
      4. Start using type-safe RPC functions in your frontend!

      📚 Documentation: https://hexdocs.pm/ash_typescript
      """

      react_notice = """
      🎉 AshTypescript with React has been successfully installed!

      Your Phoenix + React + TypeScript setup is ready!

      Next Steps:
      1. Configure your domain with the AshTypescript.Rpc extension
      2. Add typescript_rpc configurations for your resources
      3. Start your Phoenix server: mix phx.server
      4. Check out http://localhost:4000/ash-typescript for how to get started!

      📚 Documentation: https://hexdocs.pm/ash_typescript
      """

      notice = if framework == "react", do: react_notice, else: base_notice

      igniter =
        if framework == "react" do
          Igniter.add_task(igniter, "ash_typescript.npm_install")
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
