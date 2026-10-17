# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.WithManifestTest do
  use ExUnit.Case, async: true

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

  test "CodegenTestHelper honours manifest:", %{pascal: pascal} do
    {:ok, camel} = CodegenTestHelper.generate_all_content()

    {:ok, pascal_content} =
      CodegenTestHelper.generate_all_content(:ash_typescript, manifest: pascal)

    assert camel != pascal_content
  end
end
