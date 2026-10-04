# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.AgentDocsPathsTest do
  @moduledoc """
  Keeps the agent docs (`AGENTS.md`, `agent-docs/`) pointing at things that exist:
  backticked repo paths resolve, relative links resolve, and nothing points into a
  dependency's files (`deps/…`, `../<dep>`). Dependencies are referenced by public
  module name and `mix usage_rules.docs` instead, because their internal files are
  not part of the published package.
  """
  use ExUnit.Case, async: true

  @root Path.expand("../..", __DIR__)

  @repo_path_prefixes ~w(lib/ test/ agent-docs/ documentation/ config/)

  # Deliberate mentions of paths that don't exist in this repo.
  @allowed_missing [
    # prose saying the directory no longer exists
    "lib/ash_typescript/rpc/verifiers/",
    # placeholder in a troubleshooting example
    "lib/...",
    # example app path the installer creates
    "lib/my_app/ash_typescript_manifest.ex"
  ]

  @dep_names Mix.Project.deps_paths() |> Map.keys() |> Enum.map(&to_string/1)

  test "backticked repo paths exist" do
    violations =
      for {file, line_no, line} <- prose_lines(),
          [_, code] <- Regex.scan(~r/`([^`]+)`/, line),
          path = normalize_path(code),
          repo_path?(path),
          not glob?(path),
          path not in @allowed_missing,
          not File.exists?(Path.join(@root, path)) do
        "#{file}:#{line_no}: #{path}"
      end

    assert violations == [], failure("Backticked paths that don't exist", violations)
  end

  test "relative links resolve" do
    violations =
      for {file, line_no, line} <- prose_lines(),
          [_, target] <- Regex.scan(~r/\]\(([^)\s]+)\)/, line),
          target = target |> String.split("#") |> hd(),
          target != "",
          not String.match?(target, ~r/^[a-z]+:/),
          not File.exists?(Path.join([@root, Path.dirname(file), target])) do
        "#{file}:#{line_no}: #{target}"
      end

    assert violations == [], failure("Links that don't resolve", violations)
  end

  test "no paths into dependency files" do
    dep_pattern =
      ~r/(?<![\w.@-])(?:deps\/[\w.-]+|\.\.\/(?:#{Enum.join(@dep_names, "|")})(?![\w-]))/

    violations =
      for {file, line_no, line} <- doc_lines(),
          [match] <- Regex.scan(dep_pattern, line) do
        "#{file}:#{line_no}: #{match}"
      end

    assert violations == [],
           failure(
             "Paths into dependency files (use module names and `mix usage_rules.docs`)",
             violations
           )
  end

  defp doc_files do
    ["AGENTS.md" | Path.wildcard(Path.join(@root, "agent-docs/**/*.md"))]
    |> Enum.map(&Path.relative_to(&1, @root))
  end

  defp doc_lines, do: Enum.flat_map(doc_files(), &file_lines/1)

  # Doc lines outside fenced code blocks.
  defp prose_lines do
    Enum.flat_map(doc_files(), fn file ->
      file |> file_lines() |> reject_blocks(&fence?/1, &fence?/1)
    end)
  end

  # A file's lines, minus the usage-rules block: `mix usage_rules.sync` generates it,
  # and it legitimately includes `@deps/...` lines.
  defp file_lines(file) do
    @root
    |> Path.join(file)
    |> File.read!()
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.map(fn {line, line_no} -> {file, line_no, line} end)
    |> reject_blocks(
      &String.contains?(&1, "<!-- usage-rules-start -->"),
      &String.contains?(&1, "<!-- usage-rules-end -->")
    )
  end

  # Drops each block from an opening line through its closing line.
  defp reject_blocks(entries, opens?, closes?) do
    entries
    |> Enum.reduce({[], false}, fn {_, _, line} = entry, {acc, inside?} ->
      cond do
        inside? -> {acc, not closes?.(line)}
        opens?.(line) -> {acc, true}
        true -> {[entry | acc], false}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp fence?(line), do: line |> String.trim_leading() |> String.starts_with?("```")

  defp normalize_path(code) do
    code
    |> String.trim()
    |> String.replace(~r/:\d+(-\d+)?$/, "")
    |> String.replace(~r/(?<!\.)[.,;]$/, "")
  end

  defp repo_path?(path),
    do: String.starts_with?(path, @repo_path_prefixes) and not String.contains?(path, " ")

  defp glob?(path), do: String.contains?(path, ["*", "{", "<"])

  defp failure(title, violations), do: Enum.join([title <> ":" | violations], "\n  ")
end
