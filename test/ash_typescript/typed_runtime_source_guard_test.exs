# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.TypedRuntimeSourceGuardTest do
  @moduledoc """
  Typed controller and channel runtime code reads route and publication shape
  from the decorated manifest only.
  """
  use ExUnit.Case, async: true

  @moduletag :ash_typescript

  @files [
    "lib/ash_typescript/typed_controller/request_handler.ex",
    "lib/ash_typescript/typed_controller.ex",
    "lib/ash_typescript/typed_channel/payload_formatter.ex"
  ]

  @forbidden [
    "TypeResolver",
    "RpcMappingSource",
    "input_field_formatter",
    "parse_input_field",
    "format_output_field",
    "find_publication"
  ]

  for file <- @files do
    test "#{file} reads shape from the manifest" do
      source = File.read!(Path.expand("../../" <> unquote(file), __DIR__))

      for needle <- @forbidden do
        refute String.contains?(source, needle),
               "#{unquote(file)} must not contain #{inspect(needle)}"
      end
    end
  end

  @renderer "lib/ash_typescript/typed_controller/codegen/route_renderer.ex"

  # Requiredness (may the argument be omitted?) has one owner,
  # `RouteArgument.required?/1`; `allow_nil?` is read only for nullability
  # (the `| null` suffix of the two TS types and the schema's nullable flag).
  test "the renderer reads requiredness only through RouteArgument.required?/1" do
    {:ok, ast} =
      @renderer
      |> Path.expand(Path.join(__DIR__, "../.."))
      |> File.read!()
      |> Code.string_to_quoted()

    reads = fn field ->
      {_, lines} =
        Macro.prewalk(ast, [], fn
          {{:., meta, [_, ^field]}, _, []} = node, acc -> {node, [meta[:line] | acc]}
          node, acc -> {node, acc}
        end)

      Enum.reverse(lines)
    end

    assert reads.(:has_default?) == [],
           "#{@renderer} reads has_default? at lines #{inspect(reads.(:has_default?))}; " <>
             "use RouteArgument.required?/1"

    assert length(reads.(:allow_nil?)) == 3,
           "#{@renderer} reads allow_nil? at lines #{inspect(reads.(:allow_nil?))}; only the " <>
             "two `| null` decisions and the schema's nullable flag may read it"

    {_, required_calls} =
      Macro.prewalk(ast, 0, fn
        {{:., _, [{:__aliases__, _, [:RouteArgument]}, :required?]}, _, [_]} = node, n ->
          {node, n + 1}

        node, n ->
          {node, n}
      end)

    assert required_calls > 0
  end
end
