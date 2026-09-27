# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.ImportResolver do
  @moduledoc """
  Resolves relative import paths between generated TypeScript files
  and generates namespace re-export content.

  Used when generating namespace re-export files that need to import
  from the main generated file, or when any generated file needs to
  import from another.
  """

  alias AshTypescript.Codegen.SchemaFormatter

  @namespace_custom_code_marker "// --- Custom code below this line is preserved on regeneration (do not edit this line) ---"

  @doc """
  The marker comment used to separate generated code from custom code in namespace files.
  Content below this marker is preserved when regenerating namespace files.
  """
  def namespace_custom_code_marker, do: @namespace_custom_code_marker

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
    from_dir = from_file |> Path.dirname() |> Path.expand()
    to_dir = to_file |> Path.dirname() |> Path.expand()
    to_name = Path.basename(to_file, ".ts")

    if from_dir == to_dir do
      "./#{to_name}"
    else
      relative_dir = Path.relative_to(to_dir, from_dir, force: true)

      if String.starts_with?(relative_dir, "..") do
        "#{relative_dir}/#{to_name}"
      else
        "./#{relative_dir}/#{to_name}"
      end
    end
  end

  @doc """
  Resolves custom import paths from `import_into_generated` config entries
  relative to a target output file.

  Each import config is a map with `:import_name` and `:file` keys, where `:file`
  is a project-root-relative path (e.g., `"assets/js/hooks.ts"`).

  ## Parameters

    * `target_output_file` - The output file that will contain the import statements
    * `imports` - List of import config maps with `:import_name` and `:file` keys

  ## Examples

      iex> resolve_custom_imports("assets/js/ash_rpc.ts", [%{import_name: "Hooks", file: "assets/js/hooks.ts"}])
      "import * as Hooks from \\"./hooks\\";"
  """
  @spec resolve_custom_imports(String.t(), list(map())) :: String.t()
  def resolve_custom_imports(target_output_file, imports) do
    imports
    |> Enum.map(fn import_config ->
      import_name = Map.get(import_config, :import_name)
      file_path = Map.get(import_config, :file)

      if import_name && file_path do
        resolved = resolve_import_path(target_output_file, file_path)
        "import * as #{import_name} from \"#{resolved}\";"
      else
        ""
      end
    end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  @doc """
  Builds import and re-export lines for shared types.

  Generates an `export type * from` re-export, plus a local `import type { ... }`
  for only the type names actually referenced in `body_content`.

  ## Parameters

    * `import_paths` - Map with optional `:types` key containing the import path
    * `shared_type_names` - List of type names exported by the shared types file
    * `body_content` - The generated TypeScript body to scan for type usage
  """
  def build_shared_type_imports(import_paths, shared_type_names, body_content) do
    if import_paths[:types] do
      reexport = "export type * from \"#{import_paths.types}\";"

      used_types = filter_used_types(shared_type_names, body_content)

      if used_types != [] do
        type_list = Enum.join(used_types, ", ")
        local_import = "import type { #{type_list} } from \"#{import_paths.types}\";"
        local_import <> "\n" <> reexport
      else
        reexport
      end
    else
      ""
    end
  end

  @doc """
  Generates a namespace re-export file from a list of categorized exports.

  This is the shared implementation used by both RPC and controller namespace generation.

  ## Parameters

    * `namespace` - The namespace name (used in the header comment)
    * `exports` - List of `{name, kind}` tuples where kind is `:value`, `:type`, or
      `{:schema, formatter}` for a validation schema produced by that
      `AshTypescript.Codegen.SchemaFormatter`
    * `namespace_file` - Full path of the namespace file being generated (for import resolution)
    * `main_file_path` - Path to the main source file (RPC or routes)
    * `schema_files` - Map of formatter module to its schema file path; a formatter
      missing from the map re-exports from the main file
  """
  def generate_namespace_reexport_content(
        namespace,
        exports,
        namespace_file,
        main_file_path,
        schema_files \\ %{}
      ) do
    main_import_path = resolve_import_path(namespace_file, main_file_path)
    names_by_kind = Enum.group_by(exports, &elem(&1, 1), &elem(&1, 0))

    schema_sources =
      Enum.map(SchemaFormatter.all(), fn formatter ->
        import_path =
          case Map.get(schema_files, formatter) do
            nil -> main_import_path
            path -> resolve_import_path(namespace_file, path)
          end

        {{:schema, formatter}, "export", import_path}
      end)

    blocks =
      [{:type, "export type", main_import_path}, {:value, "export", main_import_path}]
      |> Kernel.++(schema_sources)
      |> Enum.flat_map(fn {kind, keyword, import_path} ->
        case Map.get(names_by_kind, kind, []) do
          [] ->
            []

          names ->
            names = Enum.sort(names)
            ["#{keyword} {\n  #{Enum.join(names, ",\n  ")}\n} from \"#{import_path}\";\n"]
        end
      end)

    header = """
    // Generated by AshTypescript - Namespace: #{namespace}
    // WARNING: Do not edit this section - it will be overwritten on regeneration
    """

    # Each section ends in a newline, so joining on "\n" leaves exactly one
    # blank line between sections, whichever export kinds are present.
    Enum.join([header | blocks] ++ [@namespace_custom_code_marker], "\n") <> "\n"
  end

  defp filter_used_types(type_names, content) do
    type_names
    |> Enum.filter(fn name ->
      Regex.match?(~r/\b#{Regex.escape(name)}\b/, content)
    end)
  end
end
