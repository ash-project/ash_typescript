# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.WithManifestTest do
  use ExUnit.Case, async: true

  alias AshTypescript.Manifest.Custom
  alias AshTypescript.Test.CodegenTestHelper

  setup_all do
    %{
      pascal:
        AshTypescript.Manifest.redecorate(AshTypescript.manifest(),
          output_formatter: :pascal_case
        )
    }
  end

  test "with_manifest/2 scopes manifest, lookups and formatters to the process", %{pascal: pascal} do
    AshTypescript.with_manifest(pascal, fn ->
      assert AshTypescript.manifest() == pascal
      assert AshTypescript.output_field_formatter() == :pascal_case
      assert AshTypescript.resource_lookup() == AshRpc.Manifest.resource_lookup(pascal)
      assert AshTypescript.entrypoints() == pascal.entrypoints
    end)

    assert AshTypescript.output_field_formatter() == :camel_case
  end

  test "the override is restored even when the function raises", %{pascal: pascal} do
    assert_raise RuntimeError, fn -> AshTypescript.with_manifest(pascal, fn -> raise "x" end) end
    assert AshTypescript.output_field_formatter() == :camel_case
  end

  test "typed_query_lookup/0 honours the override", %{pascal: pascal} do
    expected =
      pascal.entrypoints
      |> Enum.filter(&Custom.typed_query/1)
      |> Map.new(&{to_string(Custom.typed_query(&1).name), &1})

    assert expected != %{}
    assert expected != AshTypescript.typed_query_lookup()

    AshTypescript.with_manifest(pascal, fn ->
      assert AshTypescript.typed_query_lookup() == expected
      assert AshTypescript.typed_query_lookup() == AshTypescript.typed_query_lookup(pascal)
    end)
  end

  test "typed_query_lookup/1 accepts a manifest struct" do
    from_struct = AshTypescript.typed_query_lookup(AshTypescript.manifest())

    assert from_struct != %{}

    assert Map.keys(from_struct) ==
             Map.keys(AshTypescript.typed_query_lookup(AshTypescript.Test.Manifest))
  end

  test "nested with_manifest restores the outer override", %{pascal: pascal} do
    snake =
      AshTypescript.Manifest.redecorate(AshTypescript.manifest(), output_formatter: :snake_case)

    AshTypescript.with_manifest(pascal, fn ->
      AshTypescript.with_manifest(snake, fn ->
        assert AshTypescript.output_field_formatter() == :snake_case
      end)

      assert AshTypescript.output_field_formatter() == :pascal_case
    end)

    assert AshTypescript.output_field_formatter() == :camel_case
  end

  test "CodegenTestHelper honours manifest:", %{pascal: pascal} do
    {:ok, camel} = CodegenTestHelper.generate_all_content()

    {:ok, pascal_content} =
      CodegenTestHelper.generate_all_content(:ash_typescript, manifest: pascal)

    assert camel != pascal_content
  end
end
