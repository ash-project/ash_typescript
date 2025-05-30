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
      igniter
      |> Igniter.Project.Formatter.import_dep(:ash_typescript)
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
