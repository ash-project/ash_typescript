# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.RpcMappingSourceTest do
  use ExUnit.Case, async: true

  alias AshRpc.Manifest.Custom

  setup_all do
    %{manifest: AshTypescript.manifest()}
  end

  test "the configured manifest carries custom.ash_rpc from RpcMappingSource", %{manifest: m} do
    assert AshRpc.Manifest.mapping_source(m) == AshTypescript.RpcMappingSource
    assert AshRpc.Manifest.output_formatter(m) == :camel_case
    assert AshRpc.Manifest.input_formatter(m) == :camel_case
  end

  test "wire entrypoints mirror rpc_action DSL", %{manifest: m} do
    e = AshRpc.Manifest.entrypoint_lookup(m)["list_todos"]

    assert %AshRpc.Entrypoint{
             resource: AshTypescript.Test.Todo,
             domain: AshTypescript.Test.Domain
           } =
             e

    assert is_boolean(e.not_found_error?)
  end

  test "typed queries are not on the wire", %{manifest: m} do
    names = AshTypescript.typed_query_lookup() |> Map.keys()
    assert names != []
    assert Enum.all?(names, &(not Map.has_key?(AshRpc.Manifest.entrypoint_lookup(m), &1)))
  end

  test "resources without AshTypescript.Resource are not exposed", %{manifest: m} do
    refute Custom.exposed?(AshRpc.Manifest.resource_lookup(m)[AshTypescript.Test.NotExposed])
  end

  test "field_names DSL overrides land in custom.ash_rpc", %{manifest: m} do
    user = AshRpc.Manifest.resource_lookup(m)[AshTypescript.Test.User]
    assert Custom.field_names(user)[:address_line_1] == "addressLine1"
  end
end
