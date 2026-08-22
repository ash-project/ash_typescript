# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.AshTypescript.Codegen do
  @moduledoc """
  Generates TypeScript types for Ash Rpc-calls.

  Output file locations are controlled by configuration (`output_file` and
  friends) — see the Configuration Reference.

  Usage:
    mix ash_typescript.codegen [--check | --dry-run] [--dev]
      [--run-endpoint PATH] [--validate-endpoint PATH]
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
          check: :boolean,
          dev: :boolean,
          dry_run: :boolean,
          run_endpoint: :string,
          validate_endpoint: :string
        ],
        aliases: [r: :run_endpoint, v: :validate_endpoint]
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

        files
        |> Map.merge(manifest_files(otp_app))
        |> handle_files(opts)

      {:error, error_message} ->
        Mix.raise(error_message)
    end
  end

  defp handle_files(files, opts) do
    changed = changed_files(files)

    cond do
      opts[:check] && !(opts[:dev] && AshTypescript.always_regenerate?()) ->
        if changed != %{} do
          raise Ash.Error.Framework.PendingCodegen, diff: changed
        end

      opts[:dry_run] ->
        Enum.each(changed, fn {path, content} -> IO.puts("##{path}:\n\n#{content}") end)

      true ->
        Enum.each(changed, fn {path, content} ->
          File.mkdir_p!(Path.dirname(path))
          File.write!(path, content)
        end)
    end
  end

  defp changed_files(files) do
    Map.filter(files, fn {path, content} ->
      current = if File.exists?(path), do: File.read!(path), else: ""
      content != current
    end)
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

  # The Markdown and JSON manifests are generated artifacts like any other, so
  # they join the same changed-file map — otherwise `--check` would pass with a
  # stale manifest and `--dry-run` would not preview it.
  defp manifest_files(otp_app) do
    %{}
    |> put_manifest(AshTypescript.Rpc.manifest_file(), fn _path ->
      ManifestGenerator.generate_manifest()
    end)
    |> put_manifest(AshTypescript.Rpc.json_manifest_file(), fn path ->
      stabilize_generated_at(path, JsonManifestGenerator.generate_json_manifest(otp_app))
    end)
  end

  defp put_manifest(files, nil, _build), do: files
  defp put_manifest(files, path, build), do: Map.put(files, path, build.(path))

  # The JSON manifest stamps `generatedAt` with today's date, so a byte
  # comparison would report a change on every new day even when nothing else
  # moved — failing `--check` and churning the committed file. When the only
  # difference is that field, reuse the existing content so the manifest counts
  # as unchanged everywhere.
  defp stabilize_generated_at(path, content) do
    with true <- File.exists?(path),
         existing = File.read!(path),
         {:ok, new_decoded} <- Jason.decode(content),
         {:ok, old_decoded} <- Jason.decode(existing),
         true <-
           Map.delete(new_decoded, "generatedAt") == Map.delete(old_decoded, "generatedAt") do
      existing
    else
      _ -> content
    end
  end
end
