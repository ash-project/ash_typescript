# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.ImportResolver do
  @moduledoc """
  Resolves relative import paths between generated TypeScript files.

  Used when generating namespace re-export files that need to import
  from the main generated file, or when any generated file needs to
  import from another.
  """

  @doc """
  Computes a relative TypeScript import path from one file to another.

  Both paths should be relative to the project root (e.g., "assets/js/ash_rpc.ts").
  Returns a relative path suitable for TypeScript `import` statements (without `.ts` extension).

  ## Examples

      iex> resolve_import_path("assets/js/namespace/todos.ts", "assets/js/ash_rpc.ts")
      "../ash_rpc"

      iex> resolve_import_path("assets/js/todos.ts", "assets/js/ash_rpc.ts")
      "./ash_rpc"
  """
  @spec resolve_import_path(String.t(), String.t()) :: String.t()
  def resolve_import_path(from_file, to_file) do
    from_dir = Path.dirname(from_file)
    to_dir = Path.dirname(to_file)
    to_name = Path.basename(to_file, ".ts")

    if from_dir == to_dir do
      "./#{to_name}"
    else
      relative_dir = Path.relative_to(to_dir, from_dir)
      "./#{relative_dir}/#{to_name}"
    end
  end
end
