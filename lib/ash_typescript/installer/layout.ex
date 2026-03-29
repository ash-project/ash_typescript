# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

if Code.ensure_loaded?(Igniter) do
  defmodule AshTypescript.Installer.Layout do
    @moduledoc false

    alias AshTypescript.Installer.Esbuild

    @doc "Create spa_root layout from the appropriate template."
    def create_spa_root_layout(igniter, web_module, "vite", framework)
        when framework == "react" do
      app_name = Igniter.Project.Application.app_name(igniter)
      clean_web_module = clean_module(web_module)

      layout_content =
        render_install_template("spa_root_vite_react.html.heex", %{
          "__WEB_MODULE__" => clean_web_module,
          "__APP_NAME__" => to_string(app_name),
          "__ENTRY_FILE__" => Esbuild.get_entry_file(framework)
        })

      create_layout_file(igniter, web_module, "spa_root.html.heex", layout_content)
    end

    def create_spa_root_layout(igniter, web_module, "vite", framework) do
      app_name = Igniter.Project.Application.app_name(igniter)
      clean_web_module = clean_module(web_module)

      layout_content =
        render_install_template("spa_root_vite.html.heex", %{
          "__WEB_MODULE__" => clean_web_module,
          "__APP_NAME__" => to_string(app_name),
          "__ENTRY_FILE__" => Esbuild.get_entry_file(framework)
        })

      create_layout_file(igniter, web_module, "spa_root.html.heex", layout_content)
    end

    def create_spa_root_layout(igniter, web_module, "esbuild", _framework) do
      layout_content = render_install_template("spa_root_esbuild.html.heex")
      create_layout_file(igniter, web_module, "spa_root.html.heex", layout_content)
    end

    def create_spa_root_layout(igniter, _web_module, _bundler, _framework), do: igniter

    @doc "Create inertia_root layout from the appropriate template."
    def create_inertia_root_layout(igniter, web_module, "esbuild", _framework) do
      layout_content = render_install_template("inertia_root_esbuild.html.heex")
      create_layout_file(igniter, web_module, "inertia_root.html.heex", layout_content)
    end

    def create_inertia_root_layout(igniter, _web_module, _bundler, _framework), do: igniter

    @doc """
    Create or update the page controller. When `use_spa_layout` is true,
    uses `put_root_layout` to switch to spa_root layout.
    """
    def create_or_update_page_controller(igniter, web_module, opts \\ []) do
      use_spa_layout = Keyword.get(opts, :use_spa_layout, false)
      clean = clean_module(web_module)

      controller_path =
        clean
        |> String.replace_suffix("Web", "")
        |> Macro.underscore()

      page_controller_path = "lib/#{controller_path}_web/controllers/page_controller.ex"

      index_body =
        if use_spa_layout do
          """
              conn
              |> put_root_layout(html: {#{clean}.Layouts, :spa_root})
              |> render(:index)
          """
        else
          "    render(conn, :index)"
        end

      page_controller_content = """
      defmodule #{clean}.PageController do
        use #{clean}, :controller

        def index(conn, _params) do
      #{index_body}
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
                          if use_spa_layout do
                            quote do
                              def index(conn, _params) do
                                conn
                                |> put_root_layout(
                                  html: {unquote(Module.concat([clean, Layouts])), :spa_root}
                                )
                                |> render(:index)
                              end
                            end
                          else
                            quote do
                              def index(conn, _params) do
                                render(conn, :index)
                              end
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

    @doc "Create the index.html.heex template (just the mount point div)."
    def create_index_template(igniter, web_module, bundler, _framework)
        when bundler in ["vite", "esbuild"] do
      clean = clean_module(web_module)
      web_path = Macro.underscore(clean)

      Igniter.create_new_file(
        igniter,
        "lib/#{web_path}/controllers/page_html/index.html.heex",
        "<div id=\"app\"></div>\n",
        on_exists: :warning
      )
    end

    def create_index_template(igniter, web_module, _bundler, _framework) do
      clean = clean_module(web_module)
      web_path = Macro.underscore(clean)

      content = """
      <div id="app"></div>
      <script defer phx-track-static type="text/javascript" src={~p"/assets/index.js"}>
      </script>
      """

      Igniter.create_new_file(
        igniter,
        "lib/#{web_path}/controllers/page_html/index.html.heex",
        content,
        on_exists: :warning
      )
    end

    @doc "Add the /ash-typescript route to the router."
    def add_page_index_route(igniter, web_module) do
      {igniter, router_module} = Igniter.Libs.Phoenix.select_router(igniter)

      case Igniter.Project.Module.find_module(igniter, router_module) do
        {:ok, {igniter, source, _zipper}} ->
          router_content = Rewrite.Source.get(source, :content)

          if String.contains?(router_content, "get \"/ash-typescript\"") do
            igniter
          else
            route_string = "  get \"/ash-typescript\", PageController, :index"

            Igniter.Libs.Phoenix.append_to_scope(igniter, "/", route_string,
              arg2: web_module,
              placement: :after
            )
          end

        {:error, igniter} ->
          Igniter.add_warning(
            igniter,
            "Could not find router. Please manually add the /ash-typescript route."
          )
      end
    end

    @doc "Render a template from priv/templates/install/ with placeholder replacements."
    def render_install_template(template_name, replacements \\ %{}) do
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

    # -- Private helpers --

    defp clean_module(web_module) do
      web_module |> to_string() |> String.replace_prefix("Elixir.", "")
    end

    defp create_layout_file(igniter, web_module, filename, content) do
      clean = clean_module(web_module)
      web_path = Macro.underscore(clean)
      layout_path = "lib/#{web_path}/components/layouts/#{filename}"

      Igniter.create_new_file(igniter, layout_path, content, on_exists: :warning)
    end

    defp function_named?(zipper, name, arity) do
      case Sourceror.Zipper.node(zipper) do
        {:def, _, [{^name, _, args}, _]} when length(args) == arity -> true
        _ -> false
      end
    end
  end
end
