# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

if Code.ensure_loaded?(Igniter) do
  defmodule AshTypescript.Installer.Esbuild do
    @moduledoc false

    alias AshTypescript.Installer.PackageJson

    @doc "Entry file for a given framework."
    def get_entry_file("react"), do: "js/index.tsx"

    def get_entry_file("solid"), do: "js/index.tsx"
    def get_entry_file("vue"), do: "js/index.ts"
    def get_entry_file("svelte"), do: "js/index.ts"
    def get_entry_file(_), do: "js/index.ts"

    @doc """
    Update the vendored esbuild config in config.exs to add the framework entry file,
    change output dir, and enable ESM splitting. Used for React (which doesn't need plugins).
    """
    def update_esbuild_config(igniter, app_name, use_bun, framework) do
      npm_install_task = npm_install_task(use_bun)
      entry_file = get_entry_file(framework)

      igniter
      |> Igniter.Project.TaskAliases.add_alias("assets.setup", npm_install_task,
        if_exists: :append
      )
      |> update_esbuild_args(app_name, entry_file)
      |> normalize_esbuild_node_path_env()
    end

    @doc """
    Switch from vendored esbuild to a custom build.js script (needed for Vue/Svelte/Solid plugins).
    Removes the Elixir esbuild dep, adds esbuild as npm dep, and updates watchers + aliases.
    """
    def update_esbuild_config_with_script(igniter, app_name, use_bun) do
      npm_install_task = npm_install_task(use_bun)

      igniter
      |> PackageJson.add_esbuild_npm_dep()
      |> Igniter.Project.Config.remove_application_configuration("config.exs", :esbuild)
      |> Igniter.Project.Deps.remove_dep(:esbuild)
      |> remove_esbuild_install_from_assets_setup()
      |> Igniter.Project.TaskAliases.add_alias("assets.setup", npm_install_task,
        if_exists: :append
      )
      |> update_dev_watcher_for_build_script(app_name, use_bun)
      |> update_build_aliases_for_script(app_name, use_bun)
    end

    @doc "Create a custom esbuild build.js for frameworks that need plugins (Vue/Svelte/Solid)."
    def create_esbuild_script(igniter, framework, opts \\ []) do
      config = esbuild_plugin_config(framework)
      include_ssr = Keyword.get(opts, :ssr, false)
      build_script = generate_build_script(config, include_ssr)

      Igniter.create_new_file(igniter, "assets/build.js", build_script, on_exists: :warning)
    end

    @doc """
    Update the vendored esbuild config for Inertia (same as update_esbuild_config but for inertia entry file).
    """
    def update_esbuild_config_for_inertia(igniter, app_name, use_bun, framework) do
      npm_install_task = npm_install_task(use_bun)
      entry_file = get_inertia_entry_file(framework)

      igniter
      |> Igniter.Project.TaskAliases.add_alias("assets.setup", npm_install_task,
        if_exists: :append
      )
      |> update_esbuild_args(app_name, entry_file)
      |> normalize_esbuild_node_path_env()
    end

    @doc "Update root.html.heex for esbuild ESM output (path and script type changes)."
    def update_root_layout_for_esbuild(igniter) do
      web_module = Igniter.Libs.Phoenix.web_module(igniter)
      clean_web_module = web_module |> to_string() |> String.replace_prefix("Elixir.", "")
      web_path = Macro.underscore(clean_web_module)
      root_layout_path = "lib/#{web_path}/components/layouts/root.html.heex"

      igniter
      |> Igniter.update_file(root_layout_path, fn source ->
        content = source.content

        updated_content =
          content
          |> String.replace(
            ~s|src={~p"/assets/js/app.js"}|,
            ~s|src={~p"/assets/app.js"}|
          )
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

    def get_inertia_entry_file("react"),
      do: "js/index.tsx"

    def get_inertia_entry_file(_), do: "js/index.ts"

    def get_inertia_ssr_entry_file("react"),
      do: "ssr.tsx"

    def get_inertia_ssr_entry_file(_), do: "ssr.ts"

    # -- Private --

    defp npm_install_task(use_bun) do
      if use_bun, do: "ash_typescript.npm_install --bun", else: "ash_typescript.npm_install"
    end

    defp update_esbuild_args(igniter, app_name, entry_file) do
      Igniter.update_elixir_file(igniter, "config/config.exs", fn zipper ->
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
            zipper |> Sourceror.Zipper.node() |> is_esbuild_node.()
          end)

        {:ok, zipper} =
          Igniter.Code.Common.move_to(zipper, fn zipper ->
            zipper |> Sourceror.Zipper.node() |> is_app_node.()
          end)

        is_args_node = fn
          {{:__block__, _, [:args]}, {:sigil_w, _, _}} -> true
          _ -> false
        end

        {:ok, zipper} =
          Igniter.Code.Common.move_to(zipper, fn zipper ->
            zipper |> Sourceror.Zipper.node() |> is_args_node.()
          end)

        args_node = Sourceror.Zipper.node(zipper)

        case args_node do
          {{:__block__, block_meta, [:args]},
           {:sigil_w, sigil_meta, [{:<<>>, string_meta, [args_string]}, sigil_opts]}} ->
            new_args_string =
              args_string
              |> maybe_prepend_entry(entry_file)
              |> String.replace(
                "--outdir=../priv/static/assets/js",
                "--outdir=../priv/static/assets"
              )
              |> maybe_append_flag("--splitting")
              |> maybe_append_flag("--format=esm")

            new_args_node =
              {{:__block__, block_meta, [:args]},
               {:sigil_w, sigil_meta, [{:<<>>, string_meta, [new_args_string]}, sigil_opts]}}

            Sourceror.Zipper.replace(zipper, new_args_node)

          _ ->
            zipper
        end
      end)
    end

    defp maybe_prepend_entry(args_string, entry_file) do
      if String.contains?(args_string, entry_file),
        do: args_string,
        else: entry_file <> " " <> args_string
    end

    defp maybe_append_flag(args_string, flag) do
      if String.contains?(args_string, flag),
        do: args_string,
        else: args_string <> " " <> flag
    end

    defp normalize_esbuild_node_path_env(igniter) do
      joined_node_path =
        ~s|env: %{"NODE_PATH" => Enum.join([Path.expand("../deps", __DIR__), Path.expand(Mix.Project.build_path()), Path.expand("../_build/dev", __DIR__)], ":")}|

      Igniter.update_file(igniter, "config/config.exs", fn source ->
        content = source.content

        updated_content =
          content
          |> String.replace(
            ~s|env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}|,
            joined_node_path
          )
          |> String.replace(
            ~s|env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}|,
            joined_node_path
          )
          |> String.replace(
            ~s|env: %{"NODE_PATH" => Enum.join([Path.expand("../deps", __DIR__), Mix.Project.build_path()], ":")}|,
            joined_node_path
          )

        if updated_content == content do
          source
        else
          Rewrite.Source.update(source, :content, updated_content)
        end
      end)
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

    defp update_dev_watcher_for_build_script(igniter, app_name, use_bun) do
      runner = if use_bun, do: "bun", else: "node"

      {igniter, endpoint} = Igniter.Libs.Phoenix.select_endpoint(igniter)

      endpoint =
        case endpoint do
          nil ->
            web_module = Igniter.Libs.Phoenix.web_module(igniter)
            Module.concat(web_module, Endpoint)

          endpoint ->
            endpoint
        end

      watcher_code =
        Sourceror.parse_string!("""
        [
          #{runner}: ["build.js", "--watch",
            cd: Path.expand("../assets", __DIR__),
            env: %{"NODE_PATH" => Enum.join([Path.expand("../deps", __DIR__), Path.expand(Mix.Project.build_path()), Path.expand("../_build/dev", __DIR__)], ":")}
          ],
          tailwind: {Tailwind, :install_and_run, [:#{app_name}, ~w(--watch)]}
        ]
        """)

      Igniter.Project.Config.configure(
        igniter,
        "dev.exs",
        app_name,
        [endpoint, :watchers],
        {:code, watcher_code},
        updater: fn zipper ->
          {:ok, Igniter.Code.Common.replace_code(zipper, watcher_code)}
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
            ~s|["tailwind #{app_name} --minify", "cmd --cd assets #{runner} build.js --deploy", "phx.digest"]|
          )

        {:ok, Igniter.Code.Common.replace_code(zipper, alias_code)}
      end)
    end

    # -- Build script generation (parameterized) --

    defp esbuild_plugin_config("vue") do
      %{
        require_line: ~s|const vuePlugin = require("esbuild-plugin-vue3");|,
        client_plugins: ~s|[vuePlugin()]|,
        ssr_plugins: ~s|[vuePlugin({ renderSSR: true })]|,
        entry_ext: "ts",
        extra_opts: ""
      }
    end

    defp esbuild_plugin_config("svelte") do
      %{
        require_line: ~s|const sveltePlugin = require("esbuild-svelte");|,
        client_plugins:
          ~s|[\n  sveltePlugin({\n    compilerOptions: { css: "injected" },\n  }),\n]|,
        ssr_plugins:
          ~s|[\n  sveltePlugin({\n    compilerOptions: { generate: "server", css: "external" },\n  }),\n]|,
        entry_ext: "ts",
        extra_opts:
          ~s|mainFields: ["svelte", "browser", "module", "main"],\n    conditions: ["svelte", "browser"],|
      }
    end

    defp esbuild_plugin_config("solid") do
      %{
        require_line: ~s|const { solidPlugin } = require("esbuild-plugin-solid");|,
        client_plugins: ~s|[solidPlugin()]|,
        ssr_plugins: nil,
        entry_ext: "tsx",
        extra_opts: ""
      }
    end

    defp generate_build_script(config, include_ssr) do
      entry_file = "js/index.#{config.entry_ext}"

      extra_opts =
        if config.extra_opts != "" do
          "\n    #{config.extra_opts}"
        else
          ""
        end

      ssr_section =
        if include_ssr && config.ssr_plugins do
          ssr_entry = if config.entry_ext == "tsx", do: "js/ssr.tsx", else: "js/ssr.ts"

          """

          const ssrPlugins = #{config.ssr_plugins};

          let ssrOpts = {
            entryPoints: ["#{ssr_entry}"],
            bundle: true,
            platform: "node",
            target: "node20",
            format: "cjs",
            outfile: "../priv/ssr.js",
            logLevel: "info",
            loader,
            plugins: ssrPlugins,
            nodePaths: [
              "../deps",
              mixBuildPath,
              fallbackDevBuildPath,
              ...(process.env.NODE_PATH ? process.env.NODE_PATH.split(path.delimiter) : []),
            ],#{if config.extra_opts != "", do: "\n    " <> String.replace(config.extra_opts, ~s|"browser", |, "") <> "\n", else: ""}
          };
          """
        else
          ""
        end

      deploy_ssr =
        if include_ssr && config.ssr_plugins do
          """

              ssrOpts = {
                ...ssrOpts,
                minify: true,
              };
          """
        else
          ""
        end

      watch_ssr =
        if include_ssr && config.ssr_plugins do
          """

              ssrOpts = {
                ...ssrOpts,
                sourcemap: "linked",
              };
          """
        else
          ""
        end

      build_logic =
        if include_ssr && config.ssr_plugins do
          """
          async function run() {
            if (watch) {
              clientOpts = {
                ...clientOpts,
                sourcemap: "linked",
              };
          #{String.trim(watch_ssr)}

              const [clientCtx, ssrCtx] = await Promise.all([
                esbuild.context(clientOpts),
                esbuild.context(ssrOpts),
              ]);

              await Promise.all([clientCtx.watch(), ssrCtx.watch()]);
              return;
            }

            await Promise.all([esbuild.build(clientOpts), esbuild.build(ssrOpts)]);
          }

          run().catch((error) => {
            console.error(error);
            process.exit(1);
          });
          """
        else
          """
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
        end

      client_var = if include_ssr && config.ssr_plugins, do: "clientOpts", else: "opts"

      """
      const esbuild = require("esbuild");
      #{config.require_line}
      const path = require("path");

      const args = process.argv.slice(2);
      const watch = args.includes("--watch");
      const deploy = args.includes("--deploy");
      const mixBuildPath =
        process.env.MIX_BUILD_PATH ||
        path.resolve(__dirname, "..", "_build", process.env.MIX_ENV || "dev");
      const fallbackDevBuildPath = path.resolve(__dirname, "..", "_build", "dev");

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

      const plugins = #{config.client_plugins};

      let #{client_var} = {
        entryPoints: ["#{entry_file}", "js/app.js"],
        bundle: true,
        target: "es2020",
        outdir: "../priv/static/assets",
        logLevel: "info",
        loader,
        plugins,
        nodePaths: [
          "../deps",
          mixBuildPath,
          fallbackDevBuildPath,
          ...(process.env.NODE_PATH ? process.env.NODE_PATH.split(path.delimiter) : []),
        ],
        external: ["/fonts/*", "/images/*"],#{extra_opts}
        splitting: true,
        format: "esm",
      };
      #{ssr_section}
      if (deploy) {
        #{client_var} = {
          ...#{client_var},
          minify: true,
        };
      #{String.trim(deploy_ssr)}
      }

      #{String.trim(build_logic)}
      """
    end
  end
end
