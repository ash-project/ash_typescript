# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.SchemaCoreFallbacksTest do
  @moduledoc """
  `SchemaCore.get_type/2` on nodes the test domain doesn't produce: a
  primitive kind whose module has no schema of its own, a float-storage
  custom type, one whose `storage_type/1` raises and a union without
  members.
  """
  use ExUnit.Case, async: true

  alias Ash.Info.Manifest.Type
  alias AshTypescript.Codegen.{SchemaCore, ValibotSchemaGenerator, ZodSchemaGenerator}

  defmodule FloatStorage do
    @moduledoc false
    use AshTypescript.Test.PassThroughType, storage: :float

    def typescript_type, do: "number"
  end

  defmodule RaisingStorage do
    @moduledoc false
    use Ash.Type

    def typescript_type, do: "string"

    @impl true
    def storage_type(_), do: raise("no storage")
    @impl true
    def cast_input(value, _), do: {:ok, value}
    @impl true
    def cast_stored(value, _), do: {:ok, value}
    @impl true
    def dump_to_native(value, _), do: {:ok, value}
  end

  defp zod(type), do: SchemaCore.get_type(ZodSchemaGenerator, type)
  defp valibot(type), do: SchemaCore.get_type(ValibotSchemaGenerator, type)

  test "a primitive kind maps by kind when its module has no schema of its own" do
    type = %Type{kind: :boolean, module: MyApp.FlagLike}
    assert zod(type) == "z.boolean()"
    assert valibot(type) == "v.boolean()"
  end

  test "a kind with no schema is permissive" do
    assert zod(%Type{kind: :opaque_kind, module: MyApp.Opaque}) == "z.any()"
    assert valibot(%Type{kind: :opaque_kind, module: MyApp.Opaque}) == "v.any()"
  end

  test "an :unknown node of an Ash primitive module uses the primitive's schema" do
    assert zod(%Type{kind: :unknown, module: Ash.Type.Boolean}) == "z.boolean()"
  end

  test "an :unknown node of a module that maps to nothing is permissive" do
    assert zod(%Type{kind: :unknown, module: MyApp.Opaque}) == "z.any()"
  end

  test "a float-storage custom type validates as a number" do
    assert zod(%Type{kind: :unknown, module: FloatStorage}) == "z.number()"
    assert valibot(%Type{kind: :unknown, module: FloatStorage}) == "v.number()"
  end

  test "a custom type whose storage_type/1 raises is permissive" do
    assert zod(%Type{kind: :unknown, module: RaisingStorage}) == "z.any()"
  end

  test "a union without members is permissive" do
    assert zod(%Type{kind: :union, members: []}) == "z.any()"
  end
end
