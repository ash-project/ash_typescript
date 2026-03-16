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

  alias AshTypescript.Codegen.Orchestrator
  alias AshTypescript.Rpc.Codegen.JsonManifestGenerator
  alias AshTypescript.Rpc.Codegen.ManifestGenerator

  def run(args) do
    Mix.Task.run("compile")

    {opts, _remaining, _invalid} =
      OptionParser.parse(args,
        switches: [
          output: :string,
          check: :boolean,
          dev: :boolean,
          dry_run: :boolean,
          run_endpoint: :string,
          validate_endpoint: :string
        ],
        aliases: [o: :string, r: :run_endpoint, v: :validate_endpoint]
      )

    otp_app = Mix.Project.config()[:app]

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

    case Orchestrator.generate(otp_app, codegen_opts) do
      {:ok, files} ->
        marker = AshTypescript.Rpc.Codegen.namespace_custom_code_marker()

        # Preserve custom content in namespace files
        files =
          Map.new(files, fn {path, content} ->
            {path, maybe_preserve_custom_content(path, content, marker)}
          end)

        handle_files(files, opts, otp_app)

      {:error, error_message} ->
        Mix.raise(error_message)
    end
  end

  defp handle_files(files, opts, otp_app) do
    cond do
      opts[:check] && !(opts[:dev] && AshTypescript.always_regenerate?()) ->
        changes =
          files
          |> Enum.filter(fn {path, content} ->
            current = if File.exists?(path), do: File.read!(path), else: ""
            content != current
          end)
          |> Map.new()

        if map_size(changes) > 0 do
          raise Ash.Error.Framework.PendingCodegen, diff: changes
        end

      opts[:dry_run] ->
        Enum.each(files, fn {path, content} ->
          current = if File.exists?(path), do: File.read!(path), else: ""

          if content != current do
            IO.puts("##{path}:\n\n#{content}")
          end
        end)

      true ->
        changed_files =
          Enum.filter(files, fn {path, content} ->
            current = if File.exists?(path), do: File.read!(path), else: ""
            content != current
          end)

        if changed_files != [] do
          # Create directories for all changed files
          Enum.each(changed_files, fn {path, _content} ->
            File.mkdir_p!(Path.dirname(path))
          end)

          Enum.each(changed_files, fn {path, content} ->
            File.write!(path, content)
          end)
        end

        maybe_write_manifests(otp_app)
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

  defp maybe_write_manifests(otp_app) do
    if path = AshTypescript.Rpc.manifest_file() do
      write_if_changed(path, ManifestGenerator.generate_manifest())
    end

    if path = AshTypescript.Rpc.json_manifest_file() do
      write_if_changed(path, JsonManifestGenerator.generate_json_manifest(otp_app))
    end
  end

  defp write_if_changed(path, content) do
    current = if File.exists?(path), do: File.read!(path), else: ""

    if content != current do
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, content)
    end
  end
end
