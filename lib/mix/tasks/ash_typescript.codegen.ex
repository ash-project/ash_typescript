defmodule Mix.Tasks.AshTypescript.Codegen do
  @moduledoc """
  Generates TypeScript types for Ash RPC-calls.

  Usage:
    mix ash_typescript.codegen --files "assets/js/ash_rpc/*.json, assets/list_users.json" --output "assets/js/ash_generated.ts"
  """

  @shortdoc "Generates TypeScript types for Ash RPC-calls"

  use Mix.Task
  import AshTypescript.RPC.Codegen

  def run(args) do
    Mix.Task.run("compile")

    {opts, _remaining, _invalid} =
      OptionParser.parse(args,
        switches: [
          files: :string,
          output: :string,
          process_endpoint: :string,
          validate_endpoint: :string
        ],
        aliases: [f: :files, o: :string, p: :process_endpoint, v: :validate_endpoint]
      )

    otp_app = Mix.Project.config()[:app]

    pattern = Keyword.get(opts, :files, "assets/js/ash_rpc/*.json")
    output_file = Keyword.get(opts, :output, "assets/js/ash_rpc.ts")

    # Parse file patterns
    patterns = String.split(pattern, ",", trim: true)
    files = Enum.flat_map(patterns, &Path.wildcard/1) |> Enum.uniq()

    if files == [] do
      raise "No files matched the pattern: #{pattern}"
    end

    rpc_specs =
      files
      |> Enum.flat_map(fn file ->
        file
        |> File.read!()
        |> Jason.decode!()
        |> List.wrap()
      end)

    codegen_opts = [
      process_endpoint: Keyword.get(opts, :process_endpoint, "/rpc/run"),
      validate_endpoint: Keyword.get(opts, :validate_endpoint, "/rpc/validate")
    ]

    # Generate TypeScript types and write to file
    typescript_content = generate_typescript_types(otp_app, rpc_specs, codegen_opts)
    File.write!(output_file, typescript_content)
  end
end
