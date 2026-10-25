# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.CustomTypeCodegenTest do
  # Declared custom types (manifest entries, type callbacks, built-ins) are
  # generated from their fields, through the existing typed-map codegen.
  use ExUnit.Case, async: false

  setup_all do
    {:ok, content} = AshTypescript.Test.CodegenTestHelper.generate_all_content()
    %{content: content}
  end

  describe "the built-in Money entry (Task.price)" do
    test "the resource schema types it as a typed map of its fields", %{content: content} do
      assert content =~
               ~s(price: {currency: string, amount: Decimal, __type: "TypedMap", __primitiveFields: "currency" | "amount"} | null;)
    end

    test "the input type is an object of its fields", %{content: content} do
      assert content =~ "price?: {currency: string, amount: Decimal} | null;"
    end

    test "the zod and valibot schemas are objects of its fields", %{content: content} do
      assert content =~
               "price: z.object({ currency: z.string(), amount: z.string() }).nullable().optional(),"

      assert content =~
               "price: v.optional(v.nullable(v.object({ currency: v.string(), amount: v.string() }))),"
    end
  end

  describe "a type declaring typescript_fields/0 (Todo.color_palette)" do
    test "the input type is an object of its fields", %{content: content} do
      assert content =~
               "colorPalette?: {primary: string, secondary: string, accent: string} | null;"
    end

    test "the zod and valibot schemas are objects of its fields", %{content: content} do
      assert content =~
               "colorPalette: z.object({ primary: z.string(), secondary: z.string(), accent: z.string() })"

      assert content =~
               "colorPalette: v.optional(v.nullable(v.object({ primary: v.string(), secondary: v.string(), accent: v.string() })))"
    end
  end
end
