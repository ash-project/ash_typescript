# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.ClientNamesAgreementTest do
  # Characterization test: the keys codegen emits for resource schemas and named
  # typed containers must be decorated client names (`custom.ash_rpc`), under every
  # output formatter. It guards the move of codegen onto `AshTypescript.Codegen.ClientNames`.
  use ExUnit.Case, async: true

  @moduletag :ash_typescript

  alias AshRpc.Manifest.Custom
  alias AshTypescript.Codegen.ResourceSchemas
  alias AshTypescript.Codegen.TypeMapper

  @formatters [:camel_case, :snake_case, :pascal_case]
  @container_kinds [:map, :keyword, :tuple, :struct]
  @ignored_keys ["__type", "__primitiveFields"]

  setup_all do
    base = AshTypescript.manifest()

    manifests =
      Map.new(@formatters, fn
        :camel_case -> {:camel_case, base}
        f -> {f, AshTypescript.Manifest.redecorate(base, output_formatter: f)}
      end)

    %{manifests: manifests}
  end

  for formatter <- @formatters do
    @formatter formatter

    test "resource schema keys are decorated field names (#{formatter})", %{manifests: manifests} do
      AshTypescript.with_manifest(manifests[@formatter], fn ->
        lookup = AshTypescript.resource_lookup()
        exposed = lookup |> Map.values() |> Enum.filter(&Custom.exposed?/1)
        assert exposed != []

        for resource <- exposed do
          schema =
            ResourceSchemas.generate_unified_resource_schema(resource.module, Map.keys(lookup))

          [_, body] = String.split(schema, "ResourceSchema = ", parts: 2)
          keys = depth_one_keys(body) -- @ignored_keys
          allowed = Map.values(Custom.field_names(resource))

          if allowed != [],
            do: assert(keys != [], "#{inspect(resource.module)} schema has no keys: #{schema}")

          assert keys -- allowed == [],
                 "#{inspect(resource.module)} emits #{inspect(keys -- allowed)}, " <>
                   "not among its decorated names #{inspect(allowed)}"
        end
      end)
    end

    test "named typed-container keys are decorated field names (#{formatter})", %{
      manifests: manifests
    } do
      AshTypescript.with_manifest(manifests[@formatter], fn ->
        types =
          AshTypescript.type_lookup()
          |> Map.values()
          |> Enum.filter(&(&1.kind in @container_kinds and Custom.type_field_names(&1) != %{}))

        assert types != []

        for type <- types, direction <- [:output, :input] do
          keys = type |> TypeMapper.map_type([], direction) |> depth_one_keys()
          keys = keys -- @ignored_keys
          allowed = Map.values(Custom.type_field_names(type))

          assert keys -- allowed == [],
                 "#{inspect(type.name)} (#{direction}) emits #{inspect(keys -- allowed)}, " <>
                   "not among its decorated names #{inspect(allowed)}"
        end
      end)
    end
  end

  test "key extraction reads only depth-1 keys of the first object" do
    ts =
      ~S'export type XResourceSchema = { __type: "Resource"; a: string; b?: { c: number }; ' <>
        ~S'd: Array<{ e: string }>; f: ("x:y" | null); };'

    assert depth_one_keys(ts) == ["__type", "a", "b", "d", "f"]

    assert depth_one_keys(~S"{cacheEnabled1?: boolean | null, retryLimit: number}") ==
             ["cacheEnabled1", "retryLimit"]

    assert depth_one_keys(~S"{ cb: (x: string) => void; after: number }") == ["cb", "after"]
  end

  # Keys of the first top-level object literal in `ts`. Nested brackets and string
  # literals are blanked out, so only depth-1 `key:` / `key?:` pairs remain. A `?`
  # before `:` is TS optionality, not part of the key; `=>` is dropped so its `>`
  # doesn't close a bracket.
  defp depth_one_keys(ts) do
    case :binary.match(ts, "{") do
      :nomatch ->
        []

      {start, _} ->
        ts
        |> binary_part(start + 1, byte_size(ts) - start - 1)
        |> String.replace("=>", "  ")
        |> String.graphemes()
        |> blank_nested()
        |> then(&Regex.scan(~r/(?:^|[\s{,;])([A-Za-z_$][\w$]*)\??:\s/, &1))
        |> Enum.map(fn [_, key] -> key end)
    end
  end

  defp blank_nested(chars) do
    chars
    |> Enum.reduce_while({[], 0, false}, fn
      ~s("), {acc, depth, in_string?} ->
        {:cont, {[" " | acc], depth, not in_string?}}

      _char, {acc, depth, true} ->
        {:cont, {[" " | acc], depth, true}}

      char, {acc, depth, false} when char in ["{", "<", "("] ->
        {:cont, {[" " | acc], depth + 1, false}}

      "}", {acc, 0, false} ->
        {:halt, {acc, 0, false}}

      char, {acc, depth, false} when char in ["}", ">", ")"] ->
        {:cont, {[" " | acc], depth - 1, false}}

      char, {acc, 0, false} ->
        {:cont, {[char | acc], 0, false}}

      _char, {acc, depth, false} ->
        {:cont, {[" " | acc], depth, false}}
    end)
    |> elem(0)
    |> Enum.reverse()
    |> Enum.join()
  end
end
