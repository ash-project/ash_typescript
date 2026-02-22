# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.CodegenTestHelper do
  @moduledoc """
  Test helper that wraps `Orchestrator.generate/2` to provide convenient
  access to generated TypeScript content for tests.
  """

  alias AshTypescript.Codegen.Orchestrator

  @doc """
  Generates all files and concatenates their contents into a single string.

  Files are sorted by path to ensure deterministic ordering.
  """
  def generate_all_content(otp_app \\ :ash_typescript, opts \\ []) do
    case Orchestrator.generate(otp_app, opts) do
      {:ok, files} ->
        content =
          files
          |> Enum.sort_by(fn {path, _} -> path end)
          |> Enum.map_join("\n", fn {_path, content} -> content end)

        {:ok, content}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Generates all files and returns the raw `%{path => content}` map.

  Use when tests need to inspect specific files.
  """
  def generate_files(otp_app \\ :ash_typescript, opts \\ []) do
    Orchestrator.generate(otp_app, opts)
  end

  @doc """
  Extracts the RPC file content from a files map.
  """
  def rpc_content(files) do
    path = Application.get_env(:ash_typescript, :output_file)
    Map.get(files, path, "")
  end

  @doc """
  Extracts the shared types file content from a files map.
  """
  def types_content(files) do
    path = AshTypescript.types_output_file()
    Map.get(files, path, "")
  end

  @doc """
  Extracts the shared Zod file content from a files map.
  """
  def zod_content(files) do
    path = AshTypescript.zod_output_file()
    Map.get(files, path, "")
  end

  @doc """
  Extracts the routes file content from a files map.
  """
  def routes_content(files) do
    path = AshTypescript.routes_output_file()
    Map.get(files, path, "")
  end

  @doc """
  Generates typed controller content directly (bypassing the Orchestrator).

  Thin passthrough to `AshTypescript.TypedController.Codegen.generate_controller_content/1`.
  Use when tests need to pass custom options like a specific router.
  """
  def generate_controller_content(opts \\ []) do
    AshTypescript.TypedController.Codegen.generate_controller_content(opts)
  end
end
