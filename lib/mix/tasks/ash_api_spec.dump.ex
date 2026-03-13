# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.AshApiSpec.Dump do
  @shortdoc "Dump API specification as JSON"
  @moduledoc """
  Generates a JSON API specification from Ash resources.

      mix ash_api_spec.dump [--output FILE] [--format json]

  ## Options

    * `--output` / `-o` - Output file path (default: stdout)
    * `--format` - Output format, currently only "json" (default: "json")

  ## Examples

      mix ash_api_spec.dump
      mix ash_api_spec.dump --output api_spec.json
      mix ash_api_spec.dump -o api_spec.json --format json
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("compile")

    {opts, _remaining, _invalid} =
      OptionParser.parse(args,
        switches: [output: :string, format: :string],
        aliases: [o: :output]
      )

    otp_app = Mix.Project.config()[:app]
    format = Keyword.get(opts, :format, "json")
    output = Keyword.get(opts, :output)

    case format do
      "json" ->
        generate_json(otp_app, output)

      other ->
        Mix.raise("Unsupported format: #{other}. Currently only \"json\" is supported.")
    end
  end

  defp generate_json(otp_app, output) do
    {:ok, spec} = AshApiSpec.generate(otp_app: otp_app)

    case AshApiSpec.JsonSerializer.to_json(spec, pretty: true) do
      {:ok, json} ->
        if output do
          File.write!(output, json)
          Mix.shell().info("API spec written to #{output}")
        else
          Mix.shell().info(json)
        end

      {:error, error} ->
        Mix.raise("Failed to serialize API spec: #{error}")
    end
  end
end
