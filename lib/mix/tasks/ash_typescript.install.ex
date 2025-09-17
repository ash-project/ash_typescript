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
        group: :ash
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      app_name = Igniter.Project.Application.app_name(igniter)
      web_module = Igniter.Libs.Phoenix.web_module(igniter)

      igniter
      |> Igniter.Project.IgniterConfig.add_extension(Igniter.Extensions.Phoenix)
      |> Igniter.Project.Formatter.import_dep(:ash_typescript)
      |> add_ash_typescript_config()
      |> create_rpc_controller(app_name, web_module)
      |> add_rpc_routes(web_module)
    end

    defp create_rpc_controller(igniter, app_name, web_module) do
      # Remove Elixir. prefix if present
      clean_web_module = web_module |> to_string() |> String.replace_prefix("Elixir.", "")

      controller_content = """
      defmodule #{clean_web_module}.AshTypescriptRpcController do
        use #{clean_web_module}, :controller

        def run(conn, params) do
          # AshTypescriptRpc expects that the actor and tenant (if they are needed) is set using
          # Ash.PlugHelpers.set_actor() & Ash.PlugHelpers.set_tenant().
          # If your request pipeline doesn't take care of this before this controller is called,
          # you can set the actor and tenant manually here like this:
          # conn =
          #   conn
          #   |> Ash.PlugHelpers.set_actor(conn.assigns[:current_user])
          #   |> Ash.PlugHelpers.set_tenant(conn.assigns[:current_tenant])
          result = AshTypescript.Rpc.run_action(:#{app_name}, conn, params)
          json(conn, result)
        end

        def validate(conn, params) do
          # AshTypescriptRpc expects that the actor and tenant (if they are needed) is set using
          # Ash.PlugHelpers.set_actor() & Ash.PlugHelpers.set_tenant().
          # If your request pipeline doesn't take care of this before this controller is called,
          # you can set the actor and tenant manually here like this:
          # conn =
          #   conn
          #   |> Ash.PlugHelpers.set_actor(conn.assigns[:current_user])
          #   |> Ash.PlugHelpers.set_tenant(conn.assigns[:current_tenant])
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
      # Get route paths from application config with fallback defaults
      run_endpoint = Application.get_env(:ash_typescript, :run_endpoint)
      validate_endpoint = Application.get_env(:ash_typescript, :validate_endpoint)

      # Check if routes already exist using mix phx.routes
      {routes_output, _exit_code} = System.cmd("mix", ["phx.routes"], stderr_to_stdout: true)

      run_route_exists =
        routes_output
        |> String.split("\n")
        |> Enum.any?(&String.contains?(&1, "#{run_endpoint}") && String.contains?(&1, "AshTypescriptRpcController") && String.contains?(&1, ":run"))

      validate_route_exists =
        routes_output
        |> String.split("\n")
        |> Enum.any?(&String.contains?(&1, "#{validate_endpoint}") && String.contains?(&1, "AshTypescriptRpcController") && String.contains?(&1, ":validate"))

      # Build routes to add based on what's missing
      routes_to_add = []

      routes_to_add =
        if not run_route_exists do
          ["  post \"#{run_endpoint}\", AshTypescriptRpcController, :run" | routes_to_add]
        else
          routes_to_add
        end

      routes_to_add =
        if not validate_route_exists do
          [
            "  post \"#{validate_endpoint}\", AshTypescriptRpcController, :validate"
            | routes_to_add
          ]
        else
          routes_to_add
        end

      # Only add routes if any are missing
      if routes_to_add != [] do
        routes_string = Enum.join(Enum.reverse(routes_to_add), "\n") <> "\n"

        # Try to append to existing scope, or create new one if no match found
        # Use the web_module as-is (atom) to match existing scopes
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
