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
      {:ok, content} ->
        handle_output(output_file, content, opts, otp_app)

      {:error, error_message} ->
        Mix.raise(error_message)
    end
  end

  defp handle_output(output_file, content, opts, otp_app) do
    all_files = build_all_files(output_file, content)

    cond do
      opts[:check] ->
        check_for_changes(all_files, output_file, content, otp_app)

      opts[:dry_run] ->
        print_changes(all_files)

      true ->
        write_files(output_file, content, otp_app)
    end
  end

  defp build_all_files(output_file, %{main: main_content, namespaces: namespace_files}) do
    output_dir = AshTypescript.Rpc.namespace_output_dir() || Path.dirname(output_file)
    marker = AshTypescript.Rpc.Codegen.namespace_custom_code_marker()

    namespace_files_with_custom =
      Enum.map(namespace_files, fn {namespace, content} ->
        path = Path.join(output_dir, "#{namespace}.ts")
        content_with_custom = maybe_preserve_custom_content(path, content, marker)
        {path, content_with_custom}
      end)

    [{output_file, main_content}] ++ namespace_files_with_custom
  end

  defp build_all_files(output_file, typescript_content) when is_binary(typescript_content) do
    [{output_file, typescript_content}]
  end

  defp check_for_changes(all_files, output_file, content, otp_app) do
    changes =
      all_files
      |> Enum.filter(fn {path, new_content} ->
        current = if File.exists?(path), do: File.read!(path), else: ""
        new_content != current
      end)
      |> Map.new()

    if map_size(changes) > 0 do
      if Application.get_env(:ash_typescript, :auto_generate_typescript_file, false) do
        # Auto-generate instead of raising
        write_files(output_file, content, otp_app)
      else
        raise Ash.Error.Framework.PendingCodegen, diff: changes
      end
    end
  end

  defp print_changes(all_files) do
    Enum.each(all_files, fn {path, content} ->
      current = if File.exists?(path), do: File.read!(path), else: ""

      if content != current do
        IO.puts("##{path}:\n\n#{content}")
      end
    end)
  end

  defp write_files(output_file, %{main: main_content, namespaces: namespace_files}, otp_app) do
    output_dir = AshTypescript.Rpc.namespace_output_dir() || Path.dirname(output_file)
    marker = AshTypescript.Rpc.Codegen.namespace_custom_code_marker()

    File.mkdir_p!(output_dir)
    File.write!(output_file, main_content)

    Enum.each(namespace_files, fn {namespace, content} ->
      path = Path.join(output_dir, "#{namespace}.ts")
      content_with_custom = maybe_preserve_custom_content(path, content, marker)
      File.write!(path, content_with_custom)
    end)

    maybe_generate_manifest(otp_app)
  end

  defp write_files(output_file, typescript_content, otp_app) when is_binary(typescript_content) do
    File.write!(output_file, typescript_content)
    maybe_generate_manifest(otp_app)
  end

  defp maybe_preserve_custom_content(path, new_content, marker) do
    if File.exists?(path) do
      existing_content = File.read!(path)

      case String.split(existing_content, marker, parts: 2) do
        [_generated, custom_part] ->
          custom_content = String.trim_leading(custom_part, "\n")

          if custom_content != "" do
            new_content <> "\n" <> custom_content
          else
            new_content
          end

        [_only_generated] ->
          new_content
      end
    else
      new_content
    end
  end

  defp maybe_generate_manifest(otp_app) do
    if manifest_path = AshTypescript.Rpc.manifest_file() do
      manifest = ManifestGenerator.generate_manifest(otp_app)
      File.write!(manifest_path, manifest)
    end
  end
end
