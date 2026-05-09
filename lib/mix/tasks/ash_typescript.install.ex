# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.AshTypescript.Install do
    @shortdoc "Installs AshTypescript into a project. Should be called with `mix igniter.install ash_typescript`"

    @moduledoc """
    #{@shortdoc}

    ## Options

    * `--framework` - The frontend framework to use (react, vue, svelte, solid).
      If omitted, you'll be prompted to choose interactively.

    * `--bundler` - The bundler to use (esbuild, vite). Default: esbuild.

    * `--bun` - Use Bun instead of npm for package management.

    * `--inertia` - Install with Inertia.js support for SSR.
      Requires a framework and `--bundler esbuild`.

    ## Examples

        mix igniter.install ash_typescript
        mix igniter.install ash_typescript --framework react --bundler vite
        mix igniter.install ash_typescript --framework svelte --inertia
    """

    use Igniter.Mix.Task

    alias AshTypescript.Installer.{Esbuild, Framework, Inertia, Layout, PackageJson, Vite}

    @impl Igniter.Mix.Task
    def info(argv, _source) do
      installs =
        if "--bundler" in argv and vite_requested?(argv),
          do: [{:phoenix_vite, "~> 0.4.2"}],
          else: []

      %Igniter.Mix.Task.Info{
        group: :ash,
        installs: installs,
        schema: [framework: :string, bundler: :string, bun: :boolean, inertia: :boolean],
        defaults: [framework: nil, bundler: nil, bun: false, inertia: false],
        composes: [],
        extra_args?: true
      }
    end

    defp vite_requested?(argv) do
      argv
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.any?(fn [flag, val] -> flag == "--bundler" and val == "vite" end)
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      app_name = Igniter.Project.Application.app_name(igniter)
      web_module = Igniter.Libs.Phoenix.web_module(igniter)
      yes? = igniter.args.options[:yes] || false

      # Resolve options: CLI flags take precedence, otherwise prompt interactively
      framework = resolve_framework(igniter, yes?)
      bundler = resolve_bundler(igniter, framework, yes?)
      use_bun = resolve_package_manager(igniter, yes?)
      use_inertia = resolve_inertia(igniter, framework, bundler, yes?)

      # Validate
      igniter = Framework.validate_framework(igniter, framework)
      igniter = Framework.validate_bundler(igniter, bundler)
      igniter = validate_inertia_constraints(igniter, framework, bundler, use_inertia)

      # Core setup (always runs)
      # Note: phoenix_vite is installed via `installs` in info/2 when --bundler vite
      igniter =
        igniter
        |> Igniter.Project.IgniterConfig.add_extension(Igniter.Extensions.Phoenix)
        |> Igniter.Project.Formatter.import_dep(:ash_typescript)
        |> add_ash_typescript_config()
        |> create_rpc_controller(app_name, web_module)
        |> add_rpc_routes(web_module)
        |> Vite.maybe_fix_runtime_manifest_cache(bundler, app_name)

      # Framework-specific setup
      igniter =
        setup_framework(igniter, app_name, web_module, framework, bundler, use_bun, use_inertia)

      # Finalize
      igniter =
        if framework do
          Igniter.add_task(igniter, "assets.setup")
        else
          igniter
        end

      add_next_steps_notice(igniter, framework, bundler, use_inertia)
    end

    # -- Interactive prompt resolution --

    defp resolve_framework(igniter, yes?) do
      case Keyword.get(igniter.args.options, :framework) do
        nil ->
          if yes? do
            nil
          else
            Igniter.Util.IO.select(
              "Which frontend framework would you like to use?",
              [nil, "react", "vue", "svelte", "solid"],
              display: fn
                nil -> "None (TypeScript RPC only)"
                "react" -> "React"
                "vue" -> "Vue"
                "svelte" -> "Svelte"
                "solid" -> "SolidJS"
              end,
              default: nil
            )
          end

        value ->
          value
      end
    end

    defp resolve_bundler(igniter, framework, yes?) do
      if is_nil(framework) do
        "esbuild"
      else
        case Keyword.get(igniter.args.options, :bundler) do
          nil ->
            if yes? do
              "esbuild"
            else
              Igniter.Util.IO.select(
                "Which bundler would you like to use?",
                ["esbuild", "vite"],
                display: fn
                  "esbuild" -> "esbuild (Phoenix default)"
                  "vite" -> "Vite"
                end,
                default: "esbuild"
              )
            end

          value ->
            value
        end
      end
    end

    defp resolve_package_manager(igniter, yes?) do
      case Keyword.get(igniter.args.options, :bun) do
        nil ->
          if yes?, do: false, else: Igniter.Util.IO.yes?("Use Bun instead of npm?")

        value ->
          value
      end
    end

    defp resolve_inertia(igniter, framework, bundler, yes?) do
      cond do
        is_nil(framework) ->
          false

        framework == "solid" ->
          false

        bundler == "vite" ->
          false

        Keyword.get(igniter.args.options, :inertia) != nil ->
          Keyword.get(igniter.args.options, :inertia)

        yes? ->
          false

        true ->
          Igniter.Util.IO.yes?("Use Inertia.js for server-side rendering?")
      end
    end

    defp validate_inertia_constraints(igniter, framework, bundler, use_inertia) do
      cond do
        use_inertia and is_nil(framework) ->
          Igniter.add_issue(igniter, "Inertia requires a framework to be specified.")

        use_inertia and framework == "solid" ->
          Igniter.add_issue(igniter, "Solid is not currently supported with Inertia.")

        use_inertia and bundler == "vite" ->
          Igniter.add_issue(igniter, "Inertia currently only supports esbuild.")

        true ->
          igniter
      end
    end

    # -- Framework dispatch --

    defp setup_framework(igniter, _app_name, _web_module, nil, _bundler, _use_bun, _use_inertia) do
      igniter
    end

    defp setup_framework(igniter, app_name, web_module, framework, bundler, use_bun, true) do
      igniter
      |> PackageJson.create_package_json(bundler, framework)
      |> Framework.update_tsconfig(framework)
      |> Inertia.setup(app_name, web_module, bundler, use_bun, framework)
    end

    defp setup_framework(igniter, app_name, web_module, framework, bundler, use_bun, false) do
      igniter
      |> PackageJson.create_package_json(bundler, framework)
      |> Framework.create_index_page(framework)
      |> Framework.update_tsconfig(framework)
      |> setup_bundler(app_name, bundler, use_bun, framework)
      |> Layout.create_spa_root_layout(web_module, bundler, framework)
      |> Layout.create_or_update_page_controller(web_module,
        use_spa_layout: bundler in ["vite", "esbuild"]
      )
      |> Layout.create_index_template(web_module, bundler, framework)
      |> Layout.add_page_index_route(web_module)
    end

    defp setup_bundler(igniter, app_name, "esbuild", use_bun, framework)
         when framework in ["vue", "svelte", "solid"] do
      igniter
      |> Esbuild.create_esbuild_script(framework)
      |> Esbuild.update_esbuild_config_with_script(app_name, use_bun)
      |> Esbuild.update_root_layout_for_esbuild()
    end

    defp setup_bundler(igniter, app_name, "esbuild", use_bun, framework) do
      igniter
      |> Esbuild.update_esbuild_config(app_name, use_bun, framework)
      |> Esbuild.update_root_layout_for_esbuild()
    end

    defp setup_bundler(igniter, _app_name, "vite", _use_bun, framework) do
      Vite.update_vite_config_with_framework(igniter, framework)
    end

    defp setup_bundler(igniter, _app_name, _bundler, _use_bun, _framework), do: igniter

    # -- Core setup --

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

      Igniter.create_new_file(igniter, controller_path, controller_content, on_exists: :warning)
    end

    defp add_rpc_routes(igniter, web_module) do
      run_endpoint = Application.get_env(:ash_typescript, :run_endpoint)
      validate_endpoint = Application.get_env(:ash_typescript, :validate_endpoint)

      {igniter, router_module} = Igniter.Libs.Phoenix.select_router(igniter)

      case Igniter.Project.Module.find_module(igniter, router_module) do
        {:ok, {igniter, source, _zipper}} ->
          router_content = Rewrite.Source.get(source, :content)

          routes_to_add =
            []
            |> maybe_add_route(
              router_content,
              "AshTypescriptRpcController, :run",
              "  post \"#{run_endpoint}\", AshTypescriptRpcController, :run"
            )
            |> maybe_add_route(
              router_content,
              "AshTypescriptRpcController, :validate",
              "  post \"#{validate_endpoint}\", AshTypescriptRpcController, :validate"
            )

          if routes_to_add != [] do
            routes_string = Enum.join(Enum.reverse(routes_to_add), "\n") <> "\n"

            Igniter.Libs.Phoenix.append_to_scope(igniter, "/", routes_string,
              arg2: web_module,
              placement: :after
            )
          else
            igniter
          end

        {:error, igniter} ->
          Igniter.add_warning(
            igniter,
            "Could not find router. Please manually add RPC routes."
          )
      end
    end

    defp maybe_add_route(routes, router_content, check, route) do
      if String.contains?(router_content, check), do: routes, else: [route | routes]
    end

    # -- Next steps notice --

    defp add_next_steps_notice(igniter, nil, _bundler, _use_inertia) do
      Igniter.add_notice(igniter, """
      AshTypescript installed!

      Next Steps:
      1. Configure your domain with the AshTypescript.Rpc extension
      2. Add typescript_rpc configurations for your resources
      3. Generate TypeScript types: mix ash_typescript.codegen
      4. Start using type-safe RPC functions in your frontend!

      Documentation: https://hexdocs.pm/ash_typescript
      """)
    end

    defp add_next_steps_notice(igniter, framework, bundler, use_inertia) do
      name = framework_display_name(framework)

      notice =
        if use_inertia do
          """
          AshTypescript with #{name} + Inertia.js + #{bundler} installed!

          Next Steps:
          1. Start your Phoenix server: mix phx.server
          2. Visit http://localhost:4000/ash-typescript
          3. Configure your domain with the AshTypescript.Rpc extension

          Documentation: https://hexdocs.pm/ash_typescript
          Inertia.js: https://inertiajs.com
          """
        else
          """
          AshTypescript with #{name} + #{bundler} installed!

          Next Steps:
          1. Start your Phoenix server: mix phx.server
          2. Visit http://localhost:4000/ash-typescript
          3. Configure your domain with the AshTypescript.Rpc extension

          Documentation: https://hexdocs.pm/ash_typescript
          """
        end

      Igniter.add_notice(igniter, notice)
    end

    defp framework_display_name("react"), do: "React"
    defp framework_display_name("vue"), do: "Vue"
    defp framework_display_name("svelte"), do: "Svelte"
    defp framework_display_name("solid"), do: "SolidJS"
    defp framework_display_name(other), do: other
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
