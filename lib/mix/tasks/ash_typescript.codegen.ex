defmodule Mix.Tasks.AshTypescript.Codegen do
  @moduledoc """
  Generates TypeScript types for Ash RPC-calls.

  Usage:
    mix ash_typescript.codegen --output "assets/js/ash_generated.ts"
  """

  @shortdoc "Generates TypeScript types for Ash RPC-calls"

  use Mix.Task
  import AshTypescript.RPC.Codegen

  def run(args) do
    Mix.Task.run("compile")

    {opts, _remaining, _invalid} =
      OptionParser.parse(args,
        switches: [
          output: :string,
          process_endpoint: :string,
          validate_endpoint: :string
        ],
        aliases: [o: :string, p: :process_endpoint, v: :validate_endpoint]
      )

    otp_app = Mix.Project.config()[:app]

    output_file = Keyword.get(opts, :output, "assets/js/ash_rpc.ts")

    codegen_opts = [
      process_endpoint: Keyword.get(opts, :process_endpoint, "/rpc/run"),
      validate_endpoint: Keyword.get(opts, :validate_endpoint, "/rpc/validate")
    ]

    # Generate TypeScript types and write to file
    typescript_content = generate_typescript_types(otp_app, codegen_opts)
    File.write!(output_file, typescript_content)
  end
end
