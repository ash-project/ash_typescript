# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
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

  alias AshTypescript.Rpc.Codegen.ManifestGenerator

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
      validate_endpoint: validate_endpoint,
      rpc_action_before_request_hook: AshTypescript.rpc_action_before_request_hook(),
      rpc_action_after_request_hook: AshTypescript.rpc_action_after_request_hook(),
      rpc_validation_before_request_hook: AshTypescript.rpc_validation_before_request_hook(),
      rpc_validation_after_request_hook: AshTypescript.rpc_validation_after_request_hook(),
      rpc_action_hook_context_type: AshTypescript.rpc_action_hook_context_type(),
      rpc_validation_hook_context_type: AshTypescript.rpc_validation_hook_context_type(),
      rpc_action_before_channel_push_hook: AshTypescript.rpc_action_before_channel_push_hook(),
      rpc_action_after_channel_response_hook:
        AshTypescript.rpc_action_after_channel_response_hook(),
      rpc_validation_before_channel_push_hook:
        AshTypescript.rpc_validation_before_channel_push_hook(),
      rpc_validation_after_channel_response_hook:
        AshTypescript.rpc_validation_after_channel_response_hook(),
      rpc_action_channel_hook_context_type: AshTypescript.rpc_action_channel_hook_context_type(),
      rpc_validation_channel_hook_context_type:
        AshTypescript.rpc_validation_channel_hook_context_type()
    ]

    # Generate TypeScript types and write to file
    case generate_typescript_types(otp_app, codegen_opts) do
      {:ok, %{main: main_content, namespaces: namespace_files}} ->
        # Multi-file output
        handle_multi_file_output(output_file, main_content, namespace_files, opts)

      {:ok, typescript_content} when is_binary(typescript_content) ->
        # Single-file output (backwards compatible)
        handle_single_file_output(output_file, typescript_content, opts, otp_app)

      {:error, error_message} ->
        Mix.raise(error_message)
    end
  end

  defp handle_single_file_output(output_file, typescript_content, opts, otp_app) do
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
          IO.puts("##{output_file}:\n\n#{typescript_content}")
        end

      true ->
        File.write!(output_file, typescript_content)

        if manifest_path = AshTypescript.Rpc.manifest_file() do
          manifest = ManifestGenerator.generate_manifest(otp_app)
          File.write!(manifest_path, manifest)
        end
    end
  end

  defp handle_multi_file_output(output_file, main_content, namespace_files, opts) do
    output_dir = AshTypescript.Rpc.namespace_output_dir() || Path.dirname(output_file)
    marker = AshTypescript.Rpc.Codegen.namespace_custom_code_marker()

    # Build namespace files with preserved custom content
    namespace_files_with_custom =
      Enum.map(namespace_files, fn {namespace, content} ->
        path = Path.join(output_dir, "#{namespace}.ts")
        content_with_custom = maybe_preserve_custom_content(path, content, marker)
        {path, content_with_custom}
      end)

    # Build all file changes for check/dry-run
    all_files = [{output_file, main_content}] ++ namespace_files_with_custom

    cond do
      opts[:check] ->
        # Check if any files have changed
        changes =
          all_files
          |> Enum.filter(fn {path, content} ->
            current = if File.exists?(path), do: File.read!(path), else: ""
            content != current
          end)
          |> Map.new()

        if map_size(changes) > 0 do
          raise Ash.Error.Framework.PendingCodegen, diff: changes
        end

      opts[:dry_run] ->
        Enum.each(all_files, fn {path, content} ->
          current = if File.exists?(path), do: File.read!(path), else: ""

          if content != current do
            IO.puts("##{path}:\n\n#{content}")
          end
        end)

      true ->
        # Ensure output directory exists
        File.mkdir_p!(output_dir)

        # Write all files
        Enum.each(all_files, fn {path, content} ->
          File.write!(path, content)
        end)

        if manifest_path = AshTypescript.Rpc.manifest_file() do
          otp_app = Mix.Project.config()[:app]
          manifest = ManifestGenerator.generate_manifest(otp_app)
          File.write!(manifest_path, manifest)
        end
    end
  end

  # Preserves custom content below the marker comment when regenerating namespace files
  defp maybe_preserve_custom_content(path, new_content, marker) do
    if File.exists?(path) do
      existing_content = File.read!(path)

      case String.split(existing_content, marker, parts: 2) do
        [_generated, custom_part] ->
          # There's custom content after the marker - preserve it
          custom_content = String.trim_leading(custom_part, "\n")

          if custom_content != "" do
            new_content <> "\n" <> custom_content
          else
            new_content
          end

        [_only_generated] ->
          # No marker found or nothing after it
          new_content
      end
    else
      new_content
    end
  end
end
