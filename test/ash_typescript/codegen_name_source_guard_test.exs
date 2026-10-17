# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.CodegenNameSourceGuardTest do
  @moduledoc """
  Codegen reads client names from the decorated manifest through
  `AshTypescript.Codegen.ClientNames` only, so the generated names are the names
  the runtime accepts. `AshTypescript.RpcMappingSource` and the compile-time
  verifiers (outside these paths) still read the DSL: they are the decoration's
  inputs.

  The scan walks each file's AST, so docs and comments that mention a name don't
  count.
  """
  use ExUnit.Case, async: true

  @moduletag :ash_typescript

  @root Path.expand("../..", __DIR__)

  @globs [
    "lib/ash_typescript/codegen.ex",
    "lib/ash_typescript/codegen/**/*.ex",
    "lib/ash_typescript/rpc/codegen.ex",
    "lib/ash_typescript/rpc/codegen/**/*.ex",
    "lib/ash_typescript/typed_controller/codegen.ex",
    "lib/ash_typescript/typed_controller/codegen/**/*.ex",
    "lib/ash_typescript/typed_channel/codegen.ex"
  ]

  @forbidden [
    :typescript_field_names,
    :get_mapped_field_name,
    :get_mapped_argument_name,
    :format_field_for_client,
    :format_mapped_output_field,
    :has_typescript_field_names?,
    :get_typescript_field_names_map,
    :get_mapped_metadata_field_name
  ]

  @allowed %{
    "lib/ash_typescript/codegen/client_names.ex" =>
      "the one codegen module that turns Elixir names into client names (reads the manifest)"
  }

  test "codegen names come only from Codegen.ClientNames" do
    offenders =
      for glob <- @globs,
          path <- @root |> Path.join(glob) |> Path.wildcard() |> Enum.sort(),
          rel = Path.relative_to(path, @root),
          not Map.has_key?(@allowed, rel),
          name <- path |> File.read!() |> forbidden_names() |> Enum.uniq(),
          do: "#{rel}: #{name}"

    assert offenders == [],
           "read names through AshTypescript.Codegen.ClientNames:\n" <>
             Enum.join(offenders, "\n")
  end

  defp forbidden_names(source) do
    {_ast, acc} =
      source
      |> Code.string_to_quoted!()
      |> Macro.prewalk([], fn
        {:., _, [_, name]} = node, acc when name in @forbidden ->
          {node, [name | acc]}

        {name, _, args} = node, acc when name in @forbidden and is_list(args) ->
          {node, [name | acc]}

        name, acc when name in @forbidden ->
          {name, [name | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(acc)
  end
end
