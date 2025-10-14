# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.AshTypescript.Codegen do
  @moduledoc """
  Generates TypeScript types for Ash Rpc-calls.

  Usage:
    mix ash_typescript.codegen --output "assets/js/ash_generated.ts"
  """

  @shortdoc "Generates TypeScript types for Ash Rpc-calls"

  use Mix.Task
  import AshTypescript.Rpc.Codegen

  def run(args) do
    Mix.Task.run("compile")

    {opts, _remaining, _invalid} =
      OptionParser.parse(args,
        switches: [
          output: :string,
          check: :boolean,
          dry_run: :boolean,
          run_endpoint: :string,
          validate_endpoint: :string
        ],
        aliases: [o: :string, r: :run_endpoint, v: :validate_endpoint]
      )

    otp_app = Mix.Project.config()[:app]

    output_file =
      Keyword.get(opts, :output) || Application.get_env(:ash_typescript, :output_file)

    run_endpoint =
      Keyword.get(opts, :run_endpoint) || Application.get_env(:ash_typescript, :run_endpoint)

    validate_endpoint =
      Keyword.get(opts, :validate_endpoint) ||
        Application.get_env(:ash_typescript, :validate_endpoint)

    codegen_opts = [
      run_endpoint: run_endpoint,
      validate_endpoint: validate_endpoint
    ]

    # Generate TypeScript types and write to file
    case generate_typescript_types(otp_app, codegen_opts) do
      {:ok, typescript_content} ->
        current_content =
          if File.exists?(output_file) do
            File.read!(output_file)
          else
            ""
          end

        cond do
          opts[:check] ->
            if typescript_content != current_content do
              raise Ash.Error.Framework.PendingCodegen,
                diff: %{
                  output_file => typescript_content
                }
            end

          opts[:dry_run] ->
            if typescript_content != current_content do
              "##{output_file}:\n\n#{typescript_content}"
            end

          true ->
            File.write!(output_file, typescript_content)
        end

      {:error, error_message} ->
        IO.puts(:stderr, "\nTypeScript generation failed due to verifier errors:\n")
        IO.puts(:stderr, error_message)
        System.halt(1)
    end
  end
end
