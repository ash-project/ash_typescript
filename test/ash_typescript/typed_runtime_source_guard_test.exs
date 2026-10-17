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
end
