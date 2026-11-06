# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.ResourceNotInLookupTest do
  @moduledoc """
  The per-resource generators take the resources to render and the manifest's
  resource lookup separately; a resource the lookup doesn't hold raises with
  the generator's name rather than rendering nothing.
  """
  use ExUnit.Case, async: true

  alias AshTypescript.Codegen.{
    FilterTypes,
    ResourceSchemas,
    SchemaCore,
    SortTypes,
    TypeAliases,
    ZodSchemaGenerator
  }

  alias AshTypescript.Test.Todo

  @message "resource AshTypescript.Test.Todo not found in resource_lookup"

  test "filter types" do
    assert_raise RuntimeError, "FilterTypes: " <> @message, fn ->
      FilterTypes.generate_filter_type(Todo, [Todo], %{})
    end

    assert_raise RuntimeError, "FilterTypes: " <> @message, fn ->
      FilterTypes.generate_filter_field_array(Todo, %{})
    end
  end

  test "sort types" do
    assert_raise RuntimeError, "SortTypes: " <> @message, fn ->
      SortTypes.generate_sort_type(Todo, %{})
    end
  end

  test "resource schemas" do
    assert_raise RuntimeError, "ResourceSchemas: " <> @message, fn ->
      ResourceSchemas.generate_all_schemas_for_resources([Todo], [Todo], [], %{})
    end

    assert_raise RuntimeError,
                 "ResourceSchemas: resource String not found in resource_lookup",
                 fn -> ResourceSchemas.generate_unified_resource_schema(String, []) end
  end

  test "type alias roots" do
    assert_raise RuntimeError, "TypeAliases: " <> @message, fn ->
      TypeAliases.roots([Todo], %{}, [])
    end
  end

  test "validation schemas" do
    assert_raise ArgumentError,
                 "resources [String] are not in the manifest; schemas are named " <>
                   "from decorated manifest resources only",
                 fn -> SchemaCore.generate_schemas_for_resources(ZodSchemaGenerator, [String]) end
  end
end
