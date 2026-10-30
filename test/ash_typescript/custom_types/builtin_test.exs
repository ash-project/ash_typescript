# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.CustomTypes.BuiltinTest do
  use ExUnit.Case, async: true

  alias AshTypescript.CustomTypes.{Builtin, Field, MapType, Scalar}

  defp entry(module), do: Enum.find(Builtin.entries(), &(&1.module == module))

  test "entries/0 lists Money, ULID and Ltree, one entry each" do
    assert Builtin.entries() |> Enum.map(& &1.module) |> Enum.sort() ==
             Enum.sort([AshMoney.Types.Money, AshDoubleEntry.ULID, AshPostgres.Ltree])
  end

  test "Money is a map of a non-null currency string and a non-null decimal amount" do
    assert %MapType{
             module: AshMoney.Types.Money,
             fields: [
               %Field{name: :currency, type: Ash.Type.String, allow_nil?: false},
               %Field{name: :amount, type: Ash.Type.Decimal, allow_nil?: false}
             ],
             zod: nil,
             valibot: nil
           } = entry(AshMoney.Types.Money)
  end

  test "ULID is a scalar over a string, exported as ULID" do
    assert %Scalar{
             module: AshDoubleEntry.ULID,
             type: Ash.Type.String,
             constraints: [],
             ts_type: nil,
             zod: nil,
             valibot: nil,
             ts_alias: "ULID"
           } = entry(AshDoubleEntry.ULID)
  end

  test "Ltree is a scalar over a string array with MFA mappings and names" do
    assert %Scalar{
             module: AshPostgres.Ltree,
             type: {:array, Ash.Type.String},
             ts_type: {Builtin, :ltree_typescript, []},
             zod: {Builtin, :ltree_zod, []},
             valibot: {Builtin, :ltree_valibot, []},
             ts_alias: {Builtin, :ltree_ts_alias, []}
           } = entry(AshPostgres.Ltree)
  end

  test "the Ltree names depend on escape?" do
    assert Builtin.ltree_ts_alias(escape?: true) == "AshPostgresLtreeArray"
    assert Builtin.ltree_ts_alias([]) == "AshPostgresLtreeFlexible"
    assert Builtin.ltree_ts_alias(escape?: false) == "AshPostgresLtreeFlexible"
    assert Builtin.ltree_ts_alias(nil) == "AshPostgresLtreeFlexible"
  end

  test "the Ltree mappings depend on escape?" do
    assert Builtin.ltree_typescript(escape?: true) == "string[]"
    assert Builtin.ltree_typescript([]) == "string | string[]"
    assert Builtin.ltree_typescript(escape?: false) == "string | string[]"

    assert Builtin.ltree_zod(escape?: true) == "z.array(z.string())"
    assert Builtin.ltree_zod([]) == "z.union([z.string(), z.array(z.string())])"

    assert Builtin.ltree_valibot(escape?: true) == "v.array(v.string())"
    assert Builtin.ltree_valibot([]) == "v.union([v.string(), v.array(v.string())])"
  end
end
