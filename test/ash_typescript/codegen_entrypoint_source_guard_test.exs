# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.CodegenEntrypointSourceGuardTest do
  @moduledoc """
  Codegen reads per-rpc_action options (`get?`, `get_by`, `enable_filter?`,
  load restrictions, `not_found_error?`, `identities`, `show_metadata`) from the
  wire entrypoint the runtime uses, through
  `AshTypescript.Rpc.Codegen.Helpers.EntrypointOptions` only, so the generated
  types follow what the runtime does. `AshTypescript.RpcMappingSource` (outside
  these paths) still reads the DSL: it builds the wire entrypoint.

  The scan walks each file's AST, so docs and comments that mention an option
  don't count.
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

  @options [
    :enable_filter?,
    :enable_sort?,
    :allowed_loads,
    :denied_loads,
    :get?,
    :get_by,
    :not_found_error?,
    :identities,
    :show_metadata
  ]

  @map_readers [get: [2, 3], fetch: [2], fetch!: [2], has_key?: [2]]

  @option_holders [:rpc_action, :rpc_action_config, :rpc, :action, :entrypoint]

  @allowed %{
    "lib/ash_typescript/rpc/codegen/helpers/entrypoint_options.ex" =>
      "the one codegen module that reads options off the wire entrypoint"
  }

  test "codegen reads rpc_action options only through EntrypointOptions" do
    offenders =
      for glob <- @globs,
          path <- @root |> Path.join(glob) |> Path.wildcard() |> Enum.sort(),
          rel = Path.relative_to(path, @root),
          not Map.has_key?(@allowed, rel),
          {line, read} <- path |> File.read!() |> option_reads(),
          do: "#{rel}:#{line}: #{read}"

    assert offenders == [],
           "read rpc_action options through EntrypointOptions:\n" <> Enum.join(offenders, "\n")
  end

  defp option_reads(source) do
    {_ast, acc} =
      source
      |> Code.string_to_quoted!()
      |> Macro.prewalk([], fn node, acc ->
        case option_read(node) do
          nil -> {node, acc}
          read -> {node, [read | acc]}
        end
      end)

    Enum.reverse(acc)
  end

  defp option_read({{:., meta, [{:__aliases__, _, [:Map]}, fun]}, _, [_, key | _] = args})
       when is_atom(key) and key in @options do
    if length(args) in Keyword.get(@map_readers, fun, []),
      do: {meta[:line], "Map.#{fun}(_, #{inspect(key)})"}
  end

  defp option_read({{:., meta, [{var, _, ctx}, field]}, _, []})
       when var in @option_holders and is_atom(ctx) and field in @options,
       do: {meta[:line], "#{var}.#{field}"}

  defp option_read({{:., meta, [{:__aliases__, _, aliases}, :not_found_error?]}, _, []})
       when aliases in [[:AshTypescript, :Rpc], [:Rpc]],
       do: {meta[:line], "AshTypescript.Rpc.not_found_error?()"}

  defp option_read(_node), do: nil
end
