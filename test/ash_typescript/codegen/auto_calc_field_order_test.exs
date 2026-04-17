# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.AutoCalcFieldOrderTest do
  @moduledoc """
  Regression: `:auto`-typed calculations with literal-map expressions must
  emit a stable, deterministic TypeScript field order across compiles.

  Ash resolves `expr(%{a: ..., b: ...})` through a runtime Erlang map whose
  iteration order depends on atom term ordering at BEAM load time (warm
  `_build/dev` vs clean `_build/test` can differ). Without a local sort
  this leaks into generated TS as non-deterministic field order. The fix
  is narrow: sort only at calc- and publication-introspection sites that
  carry auto-derived constraints — user-declared typed maps are unaffected.
  """
  use ExUnit.Case, async: true

  alias AshTypescript.Codegen.Helpers
  alias AshTypescript.Codegen.TypeMapper

  @moduletag :ash_typescript

  describe "Helpers.sort_auto_fields/1" do
    test "sorts :fields alphabetically by key" do
      constraints = [
        fields: [
          z: [type: :string],
          a: [type: :integer],
          m: [type: :boolean]
        ]
      ]

      sorted = Helpers.sort_auto_fields(constraints)

      assert sorted |> Keyword.fetch!(:fields) |> Keyword.keys() == [:a, :m, :z]
    end

    test "yields identical output regardless of input order" do
      base = %{
        z: [type: :string],
        a: [type: :integer],
        m: [type: :boolean]
      }

      variants = [
        [z: base.z, a: base.a, m: base.m],
        [a: base.a, z: base.z, m: base.m],
        [m: base.m, z: base.z, a: base.a]
      ]

      outputs =
        Enum.map(variants, fn fields ->
          Helpers.sort_auto_fields(fields: fields)
        end)

      assert outputs |> Enum.uniq() |> length() == 1
    end

    test "passes constraints without :fields through unchanged" do
      assert Helpers.sort_auto_fields([]) == []

      assert Helpers.sort_auto_fields(instance_of: SomeModule) ==
               [instance_of: SomeModule]
    end
  end

  describe "Helpers.auto_safe_calc_constraints/1" do
    test "sorts fields for expression-based calcs" do
      calc =
        calc_fixture(
          fields: shuffled_fields(),
          calculation: {Ash.Resource.Calculation.Expression, [expr: nil]}
        )

      fields =
        calc
        |> Helpers.auto_safe_calc_constraints()
        |> Keyword.fetch!(:fields)

      assert Keyword.keys(fields) == [:a, :m, :z]
    end

    test "leaves non-expression calcs untouched (preserves user-declared order)" do
      calc =
        calc_fixture(
          fields: shuffled_fields(),
          calculation: {__MODULE__.FakeCustomCalc, []}
        )

      fields =
        calc
        |> Helpers.auto_safe_calc_constraints()
        |> Keyword.fetch!(:fields)

      assert Keyword.keys(fields) == [:z, :a, :m]
    end
  end

  describe "map_type/3 through auto-safe helper produces stable output" do
    test "byte-identical TS across shuffled synthetic constraints" do
      variants = [
        [
          z: [type: Ash.Type.UUID, allow_nil?: false],
          a: [type: Ash.Type.String, allow_nil?: false],
          m: [type: Ash.Type.String, allow_nil?: false]
        ],
        [
          a: [type: Ash.Type.String, allow_nil?: false],
          z: [type: Ash.Type.UUID, allow_nil?: false],
          m: [type: Ash.Type.String, allow_nil?: false]
        ],
        [
          m: [type: Ash.Type.String, allow_nil?: false],
          z: [type: Ash.Type.UUID, allow_nil?: false],
          a: [type: Ash.Type.String, allow_nil?: false]
        ]
      ]

      outputs =
        Enum.map(variants, fn fields ->
          calc =
            calc_fixture(
              fields: fields,
              calculation: {Ash.Resource.Calculation.Expression, [expr: nil]}
            )

          constraints = Helpers.auto_safe_calc_constraints(calc)
          TypeMapper.map_type(calc.type, constraints, :output)
        end)

      assert outputs |> Enum.uniq() |> length() == 1,
             "expected byte-identical TS for shuffled inputs, got: #{inspect(outputs)}"

      [single] = Enum.uniq(outputs)
      # :a before :m before :z
      assert String.match?(single, ~r/\{a:.*m:.*z:/)
    end
  end

  describe "full typed-channel codegen for :auto map calc" do
    test "TrackerOrderedCardPayload emits fields in alphabetical order" do
      content =
        AshTypescript.TypedChannel.Codegen.generate_channel_types(
          AshTypescript.Test.TrackerChannel,
          "tracker:*"
        )

      line =
        content
        |> String.split("\n")
        |> Enum.find(&String.contains?(&1, "TrackerOrderedCardPayload"))

      assert line, "expected a TrackerOrderedCardPayload line in generated TS"

      assert line =~
               ~r/export type TrackerOrderedCardPayload = \{a: [^,]+, m: [^,]+, z: [^}]+\};/
    end
  end

  defmodule FakeCustomCalc do
    @moduledoc false
  end

  defp shuffled_fields do
    [
      z: [type: :string],
      a: [type: :integer],
      m: [type: :boolean]
    ]
  end

  defp calc_fixture(opts) do
    %Ash.Resource.Calculation{
      name: :fixture,
      type: Ash.Type.Map,
      constraints: [fields: Keyword.fetch!(opts, :fields)],
      calculation: Keyword.fetch!(opts, :calculation),
      allow_nil?: false,
      arguments: [],
      description: nil,
      load: [],
      public?: true,
      sortable?: true,
      filterable?: true,
      sensitive?: false,
      async?: false,
      field?: true,
      multitenancy: nil,
      __spark_metadata__: nil
    }
  end
end
