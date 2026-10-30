# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.CustomTypes.Builtin do
  @moduledoc """
  The built-in custom type entries, in the same structs as a manifest
  module's `custom_types` section:

    * `AshMoney.Types.Money`: a map of `currency` (string) and `amount`
      (decimal), both non-null, exported as `Money` (`ts_alias`);
    * `AshDoubleEntry.ULID`: a scalar over `:string`, exported as `ULID`;
    * `AshPostgres.Ltree`: a scalar over `{:array, :string}` whose
      `ts_type`, `zod`, `valibot` and `ts_alias` depend on the `escape?`
      constraint (`AshPostgresLtreeArray` with `escape?: true`, else
      `AshPostgresLtreeFlexible`).

  A manifest entry for one of these modules replaces the built-in whole.
  The modules belong to optional dependencies, so the entries hold only
  atoms and nothing here calls into them.
  """

  alias AshTypescript.CustomTypes.{Field, MapType, Scalar}

  @doc "The built-in entries."
  @spec entries() :: [Scalar.t() | MapType.t()]
  def entries do
    [
      %MapType{
        module: AshMoney.Types.Money,
        ts_alias: "Money",
        fields: [
          %Field{name: :currency, type: Ash.Type.String, allow_nil?: false},
          %Field{name: :amount, type: Ash.Type.Decimal, allow_nil?: false}
        ]
      },
      %Scalar{module: AshDoubleEntry.ULID, type: Ash.Type.String, ts_alias: "ULID"},
      %Scalar{
        module: AshPostgres.Ltree,
        type: {:array, Ash.Type.String},
        ts_type: {__MODULE__, :ltree_typescript, []},
        zod: {__MODULE__, :ltree_zod, []},
        valibot: {__MODULE__, :ltree_valibot, []},
        ts_alias: {__MODULE__, :ltree_ts_alias, []}
      }
    ]
  end

  @doc "The built-in entries keyed by module."
  @spec by_module() :: %{module() => Scalar.t() | MapType.t()}
  def by_module, do: Map.new(entries(), &{&1.module, &1})

  @doc "Ltree's TypeScript: `string[]` with `escape?: true`, else `string | string[]`."
  @spec ltree_typescript(Keyword.t()) :: String.t()
  def ltree_typescript(constraints),
    do: by_escape(constraints, "string[]", "string | string[]")

  @doc "Ltree's zod schema, by `escape?` like `ltree_typescript/1`."
  @spec ltree_zod(Keyword.t()) :: String.t()
  def ltree_zod(constraints),
    do:
      by_escape(constraints, "z.array(z.string())", "z.union([z.string(), z.array(z.string())])")

  @doc "Ltree's valibot schema, by `escape?` like `ltree_typescript/1`."
  @spec ltree_valibot(Keyword.t()) :: String.t()
  def ltree_valibot(constraints),
    do:
      by_escape(constraints, "v.array(v.string())", "v.union([v.string(), v.array(v.string())])")

  @doc "Ltree's alias, by `escape?` like `ltree_typescript/1`."
  @spec ltree_ts_alias(Keyword.t() | nil) :: String.t()
  def ltree_ts_alias(constraints),
    do: by_escape(constraints, "AshPostgresLtreeArray", "AshPostgresLtreeFlexible")

  defp by_escape(constraints, escaped, unescaped) do
    if Keyword.get(constraints || [], :escape?, false) in [false, nil],
      do: unescaped,
      else: escaped
  end
end
